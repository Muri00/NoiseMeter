"""Калибровка на устройство (изискване 6): автоматична с акустичен калибратор и ръчна.

Всяка калибровка се пази като протокол (EN ISO/IEC 17025): кой и кога я е направил,
с какъв еталон, при какви условия, какво е показал уредът, каква корекция е приложена
и колко се различава от предишната.
"""

import numpy as np
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app.audio import calibration as cal_analysis
from app.audio.source import AudioSourceError, audio_blocks, microphone_lock
from app.config import settings
from app.deps import CurrentUser, DbSession
from app.models import Calibration, utcnow
from app.routers.devices import get_own_device
from app.schemas import AutoCalibrationIn, CalibrationOut, ManualCalibrationIn

router = APIRouter(prefix="/api/devices/{device_id}/calibrations", tags=["Калибровка"])

# Първата секунда се пропуска - микрофонът и калибраторът се установяват.
SETTLE_S = 1.0


@router.get("", response_model=list[CalibrationOut])
def list_calibrations(device_id: int, user: CurrentUser, db: DbSession):
    get_own_device(db, user, device_id)
    return db.scalars(
        select(Calibration).where(Calibration.device_id == device_id).order_by(Calibration.created_at.desc())
    ).all()


async def _record(seconds: float) -> np.ndarray:
    fs = settings.sample_rate
    needed = int(seconds * fs)
    parts, total = [], 0
    blocks = audio_blocks(fs, int(fs * settings.block_duration))
    try:
        async for block in blocks:
            parts.append(block)
            total += len(block)
            if total >= needed:
                break
    finally:
        await blocks.aclose()
    return np.concatenate(parts)[:needed]


@router.post("/auto", response_model=CalibrationOut, status_code=status.HTTP_201_CREATED)
async def auto_calibration(device_id: int, data: AutoCalibrationIn, user: CurrentUser, db: DbSession):
    """Записва сигнала от калибратора и изчислява корекцията. Резултатът е в статус
    "pending" - прилага се едва след потвърждение от потребителя (/apply)."""
    device = get_own_device(db, user, device_id)

    if microphone_lock.locked():
        raise HTTPException(status.HTTP_409_CONFLICT, "Микрофонът в момента се използва от измерване")
    async with microphone_lock:
        try:
            x = await _record(SETTLE_S + data.duration_s)
        except AudioSourceError as e:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(e)) from e

    fs = settings.sample_rate
    # Нивото се мери само с номиналната чувствителност, без старата корекция.
    base_offset = 94.0 - device.sensitivity_dbfs
    try:
        result = cal_analysis.analyze(x[int(SETTLE_S * fs):], fs, data.reference_freq_hz, base_offset)
    except cal_analysis.CalibrationSignalError as e:
        raise HTTPException(422, str(e)) from e

    offset = round(data.reference_level_db - result.level_db, 2)
    before = device.calibration_offset_db
    cal = Calibration(
        device_id=device.id, user_id=user.id, method="auto", status="pending",
        measured_level_db=result.level_db, measured_freq_hz=result.freq_hz,
        stability_db=result.stability_db, offset_before_db=before, offset_db=offset,
        drift_db=round(offset - (before or 0.0), 2),
        **data.model_dump(exclude={"duration_s"}),
    )
    db.add(cal)
    db.commit()
    return cal


@router.post("/manual", response_model=CalibrationOut, status_code=status.HTTP_201_CREATED)
def manual_calibration(device_id: int, data: ManualCalibrationIn, user: CurrentUser, db: DbSession):
    """Ръчна калибровка - прилага се веднага.

    По показание: микрофонът е в калибратора, потребителят отчита нивото от екрана
    "Измерване" (с текущата корекция) и въвежда еталонната стойност.
    Корекцията се изчислява като: нова = текуща + (еталон - показание).
    """
    device = get_own_device(db, user, device_id)
    before = device.calibration_offset_db
    if data.offset_db is not None:
        offset = data.offset_db
    else:
        offset = (before or 0.0) + data.reference_level_db - data.measured_level_db
    offset = round(offset, 2)

    now = utcnow()
    cal = Calibration(
        device_id=device.id, user_id=user.id, method="manual", status="applied", applied_at=now,
        offset_before_db=before, drift_db=round(offset - (before or 0.0), 2),
        **(data.model_dump() | {"offset_db": offset}),
    )
    device.calibration_offset_db = offset
    db.add(cal)
    db.commit()
    return cal


def _get_pending(db, device_id: int, calibration_id: int) -> Calibration:
    cal = db.get(Calibration, calibration_id)
    if cal is None or cal.device_id != device_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Калибровката не е намерена")
    if cal.status != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Калибровката вече е приложена или отхвърлена")
    return cal


@router.post("/{calibration_id}/apply", response_model=CalibrationOut)
def apply_calibration(device_id: int, calibration_id: int, user: CurrentUser, db: DbSession):
    device = get_own_device(db, user, device_id)
    cal = _get_pending(db, device_id, calibration_id)
    cal.status = "applied"
    cal.applied_at = utcnow()
    # Отклонението се смята спрямо корекцията в момента на прилагане.
    cal.offset_before_db = device.calibration_offset_db
    cal.drift_db = round(cal.offset_db - (device.calibration_offset_db or 0.0), 2)
    device.calibration_offset_db = cal.offset_db
    db.commit()
    return cal


@router.post("/{calibration_id}/reject", response_model=CalibrationOut)
def reject_calibration(device_id: int, calibration_id: int, user: CurrentUser, db: DbSession):
    get_own_device(db, user, device_id)
    cal = _get_pending(db, device_id, calibration_id)
    cal.status = "rejected"
    db.commit()
    return cal
