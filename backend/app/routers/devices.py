from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.deps import CurrentUser, DbSession
from app.models import Device
from app.schemas import DeviceIn, DeviceOut

router = APIRouter(prefix="/api/devices", tags=["Устройства"])


def get_own_device(db, user, device_id: int) -> Device:
    device = db.get(Device, device_id)
    if device is None or device.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Устройството не е намерено")
    return device


def _commit(db) -> None:
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "Вече имате устройство с този сериен номер")


@router.get("", response_model=list[DeviceOut])
def list_devices(user: CurrentUser, db: DbSession):
    return db.scalars(select(Device).where(Device.user_id == user.id).order_by(Device.id)).all()


@router.post("", response_model=DeviceOut, status_code=status.HTTP_201_CREATED)
def create_device(data: DeviceIn, user: CurrentUser, db: DbSession):
    device = Device(user_id=user.id, **data.model_dump())
    db.add(device)
    _commit(db)
    return device


@router.get("/{device_id}", response_model=DeviceOut)
def get_device(device_id: int, user: CurrentUser, db: DbSession):
    return get_own_device(db, user, device_id)


@router.put("/{device_id}", response_model=DeviceOut)
def update_device(device_id: int, data: DeviceIn, user: CurrentUser, db: DbSession):
    device = get_own_device(db, user, device_id)
    # Калибровката е направена спрямо старата чувствителност и вече не е валидна.
    if data.sensitivity_dbfs != device.sensitivity_dbfs:
        device.calibration_offset_db = None
    for key, value in data.model_dump().items():
        setattr(device, key, value)
    _commit(db)
    return device


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(device_id: int, user: CurrentUser, db: DbSession):
    db.delete(get_own_device(db, user, device_id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
