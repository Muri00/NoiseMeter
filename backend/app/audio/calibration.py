"""Анализ на сигнал от акустичен калибратор (автоматична калибровка, изискване 6.2).

Микрофонът се поставя в калибратор, който дава чист тон с известно ниво
(обикновено 94 dB или 114 dB SPL при 1 kHz). Измерва се нивото в терцоктавната
лента около тона. Така шумът извън лентата не влияе на резултата.
"""

from dataclasses import dataclass

import numpy as np

from app.audio import octave

# Допустими отклонения, при които резултатът се приема за валиден.
MAX_FREQ_DEVIATION = 0.05  # 5% от номиналната честота на калибратора
MAX_NOISE_DB = 1.0  # широколентовото ниво може да надвишава нивото в лентата с най-много 1 dB
MAX_STABILITY_DB = 0.3  # стандартно отклонение на показанията за 0.5 s


class CalibrationSignalError(ValueError):
    pass


@dataclass
class CalibrationResult:
    level_db: float  # ниво в терцоктавата около тона, без калибровъчна корекция
    wideband_db: float
    freq_hz: float
    stability_db: float


def _band_level(x: np.ndarray, fs: float, f_ref: float, offset_db: float) -> float:
    lower, upper = octave.band_edges(np.array([f_ref]), 3)
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    spec[1:-1] *= 2
    spec /= len(x) * np.sum(np.hanning(len(x)) ** 2)
    freqs = np.fft.rfftfreq(len(x), 1 / fs)
    ms = spec[(freqs >= lower[0]) & (freqs < upper[0])].sum()
    return float(10 * np.log10(max(ms, 1e-20)) + offset_db)


def analyze(x: np.ndarray, fs: float, f_ref: float, offset_db: float) -> CalibrationResult:
    """offset_db: ниво при 0 dBFS само от чувствителността (без предишна калибровка)."""
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)

    # Доминиращата честота, с параболична интерполяция между FFT отчетите.
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    k = int(np.argmax(spec[1:])) + 1
    if 1 <= k < len(spec) - 1:
        a, b, c = np.log(spec[k - 1:k + 2] + 1e-30)
        k = k + 0.5 * (a - c) / (a - 2 * b + c)
    freq = float(k * fs / len(x))
    if abs(freq - f_ref) > MAX_FREQ_DEVIATION * f_ref:
        raise CalibrationSignalError(
            f"Не е открит тон {f_ref:g} Hz (доминираща честота {freq:.0f} Hz). "
            "Проверете дали микрофонът е поставен в калибратора и калибраторът е включен."
        )

    level = _band_level(x, fs, f_ref, offset_db)
    wideband = float(10 * np.log10(max(np.mean(x**2), 1e-20)) + offset_db)
    if wideband - level > MAX_NOISE_DB:
        raise CalibrationSignalError(
            f"Твърде много шум: общото ниво е с {wideband - level:.1f} dB над нивото на тона. "
            "Проверете дали микрофонът е плътно поставен в калибратора."
        )

    chunk = int(0.5 * fs)
    chunks = [x[i:i + chunk] for i in range(0, len(x) - chunk + 1, chunk)]
    stability = float(np.std([_band_level(c, fs, f_ref, offset_db) for c in chunks]))
    if stability > MAX_STABILITY_DB:
        raise CalibrationSignalError(
            f"Нестабилно показание (отклонение {stability:.2f} dB). Повторете, без да местите микрофона."
        )

    return CalibrationResult(
        level_db=round(level, 2), wideband_db=round(wideband, 2),
        freq_hz=round(freq, 1), stability_db=round(stability, 3),
    )
