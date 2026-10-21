"""Запис на измерване: нивата в базата (по един ред на секунда) и сигналът в WAV файл."""

from datetime import timedelta
from pathlib import Path

import numpy as np
from sqlalchemy import select

from app.audio.meter import LevelMeter
from app.audio.wavfile import WavWriter
from app.config import settings
from app.database import SessionLocal
from app.models import Calibration, Device, Measurement, MeasurementFrame, utcnow

# Редовете се записват в базата на пакети, за да не се пише при всяка секунда.
_FLUSH_EVERY = 5


def device_snapshot(db, device: Device) -> dict:
    """Данните за входното устройство към момента на записа (изискване 4)."""
    last_cal = db.scalar(
        select(Calibration)
        .where(Calibration.device_id == device.id, Calibration.status == "applied")
        .order_by(Calibration.applied_at.desc())
    )
    return {
        "id": device.id,
        "brand": device.brand,
        "model": device.model,
        "serial_number": device.serial_number,
        "sensitivity_dbfs": device.sensitivity_dbfs,
        "freq_min_hz": device.freq_min_hz,
        "freq_max_hz": device.freq_max_hz,
        "calibration_offset_db": device.calibration_offset_db,
        "calibration_id": last_cal.id if last_cal else None,
        "calibration_date": last_cal.applied_at.isoformat() + "Z" if last_cal and last_cal.applied_at else None,
        "calibration_valid_until": (
            device.next_calibration_due.isoformat() + "Z" if device.next_calibration_due else None
        ),
        "level_offset_db": device.level_offset_db,
    }


class Recorder:
    def __init__(
        self, *, user_id: int, device_id: int, meter: LevelMeter, indicators: list[str],
        name: str | None, save_wav: bool,
    ):
        self.meter = meter
        self.pending: list[MeasurementFrame] = []
        cfg = meter.cfg

        with SessionLocal() as db:
            device = db.get(Device, device_id)
            info = device_snapshot(db, device)
            m = Measurement(
                user_id=user_id, device_id=device_id, name=name, sample_rate=int(cfg.fs),
                f_min_hz=cfg.f_min, f_max_hz=cfg.f_max, band_mode=cfg.band_mode,
                device_info=info, indicators=indicators,
            )
            db.add(m)
            db.commit()
            self.measurement_id = m.id
            self.started_at = m.started_at

        self.wav: WavWriter | None = None
        if save_wav:
            folder = Path(settings.recordings_dir)
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / f"measurement_{self.measurement_id}_{self.started_at:%Y%m%d_%H%M%S}.wav"
            self.wav = WavWriter(path, int(cfg.fs), {
                "INAM": name or f"Измерване {self.measurement_id}",
                "ISRC": f"{info['brand']} {info['model']}, S/N {info['serial_number']}",
                "ICMT": (
                    f"Устройство: {info['brand']} {info['model']}; сериен №: {info['serial_number']}; "
                    f"чувствителност: {info['sensitivity_dbfs']} dBFS при 94 dB SPL; "
                    f"работна лента: {info['freq_min_hz']:g}-{info['freq_max_hz']:g} Hz; "
                    f"калибровъчна корекция: {info['calibration_offset_db'] or 0:+.2f} dB; "
                    f"ниво при 0 dBFS: {info['level_offset_db']:.2f} dB SPL; "
                    f"измервателен интервал: {cfg.f_min:g}-{cfg.f_max:g} Hz"
                ),
                "ICRD": f"{self.started_at:%Y-%m-%dT%H:%M:%S}Z",
                "ISFT": "NoiseMeter",
            })
            with SessionLocal() as db:
                db.get(Measurement, self.measurement_id).wav_path = str(path)
                db.commit()

    def add_block(self, block: np.ndarray) -> None:
        """Извиква се след meter.process() за всеки блок."""
        if self.wav is not None:
            self.wav.write(block)
        if self.meter.interval_samples >= settings.record_interval * self.meter.cfg.fs:
            self._add_frame()

    def _add_frame(self) -> None:
        levels = self.meter.pop_interval()
        t = self.meter.elapsed
        self.pending.append(MeasurementFrame(
            measurement_id=self.measurement_id,
            ts=self.started_at + timedelta(seconds=t),
            t=round(t, 3),
            leq_a=levels["LAeq"], leq_c=levels["LCeq"], leq_z=levels["LZeq"],
            levels=levels,
            bands=(
                {"centers": self.meter.last_bands["centers"], "levels": self.meter.last_bands["levels"]}
                if self.meter.last_bands else None
            ),
        ))
        if len(self.pending) >= _FLUSH_EVERY:
            self._flush()

    def _flush(self) -> None:
        if not self.pending:
            return
        with SessionLocal() as db:
            db.add_all(self.pending)
            db.commit()
        self.pending = []

    def finish(self, summary: dict) -> None:
        """Записва остатъка и обобщението. Извиква се и при прекъсната връзка."""
        if self.meter.interval_samples > 0.5 * settings.record_interval * self.meter.cfg.fs:
            self._add_frame()
        self._flush()
        if self.wav is not None:
            self.wav.close()
        with SessionLocal() as db:
            m = db.get(Measurement, self.measurement_id)
            m.ended_at = utcnow()
            m.duration_s = round(self.meter.elapsed, 2)
            m.summary = summary
            db.commit()
