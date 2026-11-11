"""Зони с норми, стандарти за измерване и роли на потребителите.

Всеки влязъл потребител може да чете зоните и стандартите (за да ги избере при
измерване), но само администраторът може да ги променя.
"""

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.deps import AdminUser, CurrentUser, DbSession
from app.models import Standard, User, Zone
from app.schemas import AdminUserOut, RoleUpdate, StandardIn, StandardOut, ZoneIn, ZoneOut

router = APIRouter(tags=["Администрация"])


def _commit(db, message: str) -> None:
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, message)


# ---------- Зони ----------

@router.get("/api/norms/zones", response_model=list[ZoneOut])
def list_zones(user: CurrentUser, db: DbSession):
    """Гранични стойности по Наредба № 6/2006 за всяка зона."""
    return db.scalars(select(Zone).order_by(Zone.category, Zone.sort_order, Zone.id)).all()


@router.post("/api/admin/zones", response_model=ZoneOut, status_code=status.HTTP_201_CREATED)
def create_zone(data: ZoneIn, admin: AdminUser, db: DbSession):
    zone = Zone(**data.model_dump())
    db.add(zone)
    _commit(db, "Вече има зона с този код")
    return zone


@router.put("/api/admin/zones/{zone_id}", response_model=ZoneOut)
def update_zone(zone_id: int, data: ZoneIn, admin: AdminUser, db: DbSession):
    zone = db.get(Zone, zone_id)
    if zone is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Зоната не е намерена")
    for key, value in data.model_dump().items():
        setattr(zone, key, value)
    _commit(db, "Вече има зона с този код")
    return zone


@router.delete("/api/admin/zones/{zone_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_zone(zone_id: int, admin: AdminUser, db: DbSession):
    zone = db.get(Zone, zone_id)
    if zone is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Зоната не е намерена")
    # Измерванията пазят копие на нормите, затова изтриването не променя старите записи.
    db.delete(zone)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------- Стандарти ----------

@router.get("/api/standards", response_model=list[StandardOut])
def list_standards(user: CurrentUser, db: DbSession):
    return db.scalars(select(Standard).order_by(Standard.sort_order, Standard.id)).all()


def _set_default(db, standard: Standard) -> None:
    """Само един стандарт може да е по подразбиране."""
    if standard.is_default:
        for other in db.scalars(select(Standard).where(Standard.id != standard.id)).all():
            other.is_default = False


@router.post("/api/admin/standards", response_model=StandardOut, status_code=status.HTTP_201_CREATED)
def create_standard(data: StandardIn, admin: AdminUser, db: DbSession):
    standard = Standard(**data.model_dump())
    db.add(standard)
    db.flush()
    _set_default(db, standard)
    _commit(db, "Вече има стандарт с този код")
    return standard


@router.put("/api/admin/standards/{standard_id}", response_model=StandardOut)
def update_standard(standard_id: int, data: StandardIn, admin: AdminUser, db: DbSession):
    standard = db.get(Standard, standard_id)
    if standard is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Стандартът не е намерен")
    for key, value in data.model_dump().items():
        setattr(standard, key, value)
    _set_default(db, standard)
    _commit(db, "Вече има стандарт с този код")
    return standard


@router.delete("/api/admin/standards/{standard_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_standard(standard_id: int, admin: AdminUser, db: DbSession):
    standard = db.get(Standard, standard_id)
    if standard is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Стандартът не е намерен")
    if db.scalar(select(Standard.id).where(Standard.id != standard_id).limit(1)) is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Трябва да остане поне един стандарт")
    db.delete(standard)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------- Потребители и роли ----------

@router.get("/api/admin/users", response_model=list[AdminUserOut])
def list_users(admin: AdminUser, db: DbSession):
    return db.scalars(select(User).order_by(User.username)).all()


@router.put("/api/admin/users/{user_id}/role", response_model=AdminUserOut)
def set_role(user_id: int, data: RoleUpdate, admin: AdminUser, db: DbSession):
    target = db.get(User, user_id)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Потребителят не е намерен")
    if target.id == admin.id and data.role != "admin":
        raise HTTPException(status.HTTP_409_CONFLICT, "Не можете да премахнете собствените си администраторски права")
    target.role = data.role
    db.commit()
    return target
