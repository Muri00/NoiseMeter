"""Шумомер: обработва аудио блок по блок и изчислява всички нива едновременно."""

from dataclasses import dataclass

import numpy as np

from app.audio import octave
from app.audio.indicators import FREQUENCY_WEIGHTINGS, TIME_WEIGHTINGS
from app.audio.weighting import (
    IEC_POLES, SosFilter, design_bandpass, design_weighting, make_time_weighting,
)

# Долна граница при логаритмуване, за да няма log(0).
_TINY = 1e-20


def to_db(mean_square: float | np.ndarray, offset_db: float):
    return 10 * np.log10(np.maximum(mean_square, _TINY)) + offset_db


@dataclass
class MeterConfig:
    fs: float
    offset_db: float  # dB SPL, съответстващи на RMS = 1 (0 dBFS)
    f_min: float
    f_max: float
    band_mode: str = "1/3"  # "off", "1/1" или "1/3"
    # Коефициенти от избрания стандарт: полюсни честоти f1..f4 и времеви константи.
    poles: tuple | None = None
    taus: dict | None = None


class _Stats:
    """Натрупана енергия и екстремуми на времево претеглените стойности за даден период."""

    def __init__(self):
        self.energy = {fw: 0.0 for fw in FREQUENCY_WEIGHTINGS}
        self.max_ms: dict[tuple[str, str], float] = {}
        self.min_ms: dict[tuple[str, str], float] = {}
        # Lp - ниво без честотен и без времеви филтър (средноквадратично за всеки блок от 100 ms).
        self.lp_max = 0.0
        self.lp_min = np.inf
        self.samples = 0

    def levels(self, offset_db: float) -> dict[str, float]:
        out = {}
        for fw in FREQUENCY_WEIGHTINGS:
            out[f"L{fw}eq"] = to_db(self.energy[fw] / max(self.samples, 1), offset_db)
        for (fw, tw), v in self.max_ms.items():
            out[f"L{fw}{tw}max"] = to_db(v, offset_db)
        for (fw, tw), v in self.min_ms.items():
            out[f"L{fw}{tw}min"] = to_db(v, offset_db)
        if self.samples:
            out["Lpmax"] = to_db(self.lp_max, offset_db)
            out["Lpmin"] = to_db(self.lp_min, offset_db)
        return out


class LevelMeter:
    """Изчислява за всяка комбинация от честотен (A/C/Z) и времеви (F/S/I) филтър:
    текущото ниво, максимума и минимума, както и Leq.

    Статистиките се водят в два периода: от началото на измерването (за екрана) и
    от последното извикване на pop_interval() (за записа - по един ред на секунда).
    """

    def __init__(self, cfg: MeterConfig):
        self.cfg = cfg
        self.bandpass = SosFilter(design_bandpass(cfg.f_min, cfg.f_max, cfg.fs))
        poles = cfg.poles or IEC_POLES
        self.freq_filters = {fw: SosFilter(design_weighting(fw, cfg.fs, poles)) for fw in FREQUENCY_WEIGHTINGS}
        self.time_filters = {
            (fw, tw): make_time_weighting(tw, cfg.fs, cfg.taus)
            for fw in FREQUENCY_WEIGHTINGS
            for tw in TIME_WEIGHTINGS
        }
        self.total = _Stats()
        self.interval = _Stats()
        self.current: dict[str, float] = {}  # текущите времево претеглени нива (LAF, LCS, ...)
        self.last_bands: dict | None = None

        self.bands: octave.BandAnalyzer | None = None
        if cfg.band_mode in ("1/1", "1/3"):
            fraction = 1 if cfg.band_mode == "1/1" else 3
            self.bands = octave.BandAnalyzer(fraction, cfg.f_min, cfg.f_max, cfg.fs)

    @property
    def elapsed(self) -> float:
        return self.total.samples / self.cfg.fs

    @property
    def interval_samples(self) -> int:
        return self.interval.samples

    def process(self, block: np.ndarray) -> dict:
        """Обработва един блок и връща кадър с всички текущи стойности в dB."""
        off = self.cfg.offset_db
        x = self.bandpass(np.asarray(block, dtype=np.float64))
        block_ms = float(np.mean(x * x))
        for stats in (self.total, self.interval):
            stats.samples += len(x)
            stats.lp_max = max(stats.lp_max, block_ms)
            stats.lp_min = min(stats.lp_min, block_ms)
        self.current["Lp"] = to_db(block_ms, off)

        for fw in FREQUENCY_WEIGHTINGS:
            xw = self.freq_filters[fw](x)
            x2 = xw * xw
            energy = float(np.sum(x2))
            for tw in TIME_WEIGHTINGS:
                key = (fw, tw)
                y = self.time_filters[key](x2)
                y_max, y_min = float(np.max(y)), float(np.min(y))
                for stats in (self.total, self.interval):
                    stats.max_ms[key] = max(stats.max_ms.get(key, 0.0), y_max)
                    stats.min_ms[key] = min(stats.min_ms.get(key, np.inf), y_min)
                self.current[f"L{fw}{tw}"] = to_db(float(y[-1]), off)
            for stats in (self.total, self.interval):
                stats.energy[fw] += energy

        frame = {"t": round(self.elapsed, 3), "levels": self.summary()}

        if self.bands is not None:
            self.bands.push(x)
            ms = self.bands.mean_squares()
            if ms is not None:
                self.last_bands = {
                    "mode": self.cfg.band_mode,
                    "centers": [octave.nominal(c) for c in self.bands.centers],
                    "levels": [round(float(v), 2) for v in to_db(ms, off)],
                }
                frame["bands"] = self.last_bands
        return frame

    def summary(self) -> dict[str, float]:
        """Текущите нива и Leq, max, min от началото на измерването."""
        return _rounded(self.current | self.total.levels(self.cfg.offset_db))

    def pop_interval(self) -> dict[str, float]:
        """Нивата за периода от предишното извикване: Leq, max и min за периода
        и текущите времево претеглени стойности в края му. Нулира периода."""
        levels = _rounded(self.current | self.interval.levels(self.cfg.offset_db))
        self.interval = _Stats()
        return levels


def _rounded(levels: dict) -> dict[str, float]:
    return {k: round(float(v), 2) for k, v in levels.items()}
