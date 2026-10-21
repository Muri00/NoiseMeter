from pathlib import Path

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import or_, select

from app.deps import CurrentUser, DbSession
from app.models import Measurement, User, utcnow
from app.schemas import (
    AccountDelete, LoginRequest, PasswordChange, ProfileUpdate, TokenOut, UserCreate, UserOut,
)
from app.security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/api/auth", tags=["Акаунти"])

# Хеш на произволна парола: проверява се при несъществуващ потребител, за да
# отнема входът еднакво време и да не издава кои потребителски имена съществуват.
_DUMMY_HASH = hash_password("dummy-password-1")


@router.post("/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def register(data: UserCreate, db: DbSession):
    exists = db.scalar(
        select(User).where(or_(User.username == data.username, User.email == data.email))
    )
    if exists:
        raise HTTPException(status.HTTP_409_CONFLICT, "Потребителското име или имейлът вече са заети")

    user = User(
        username=data.username,
        email=data.email.lower(),
        password_hash=hash_password(data.password),
        first_name=data.first_name,
        last_name=data.last_name,
    )
    db.add(user)
    db.commit()
    return TokenOut(access_token=create_access_token(user.id), user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
def login(data: LoginRequest, db: DbSession):
    login_value = data.login.strip()
    user = db.scalar(
        select(User).where(or_(User.username == login_value, User.email == login_value.lower()))
    )
    if user is None:
        verify_password(data.password, _DUMMY_HASH)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Грешно потребителско име или парола")
    if not verify_password(data.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Грешно потребителско име или парола")
    return TokenOut(access_token=create_access_token(user.id), user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser):
    return user


# ---------- Профил ----------

@router.put("/me", response_model=UserOut)
def update_profile(data: ProfileUpdate, user: CurrentUser, db: DbSession):
    email = data.email.lower()
    taken = db.scalar(select(User).where(User.email == email, User.id != user.id))
    if taken:
        raise HTTPException(status.HTTP_409_CONFLICT, "Имейлът вече се използва от друг акаунт")
    user.email = email
    user.first_name = (data.first_name or "").strip() or None
    user.last_name = (data.last_name or "").strip() or None
    db.commit()
    return user


@router.post("/change-password", response_model=TokenOut)
def change_password(data: PasswordChange, user: CurrentUser, db: DbSession):
    """Сменя паролата и обезсилва всички стари сесии. Връща нов токен за текущото устройство."""
    if not verify_password(data.current_password, user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Текущата парола е грешна")
    if verify_password(data.new_password, user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Новата парола трябва да е различна от текущата")
    user.password_hash = hash_password(data.new_password)
    # До секунда, защото времето на издаване в токена (iat) е в цели секунди.
    user.password_changed_at = utcnow().replace(microsecond=0)
    db.commit()
    return TokenOut(access_token=create_access_token(user.id), user=UserOut.model_validate(user))


@router.post("/delete-account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(data: AccountDelete, user: CurrentUser, db: DbSession):
    """Изтрива акаунта с всички устройства, измервания, калибровки и сертификати."""
    if not verify_password(data.password, user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Грешна парола")
    wav_files = db.scalars(
        select(Measurement.wav_path).where(Measurement.user_id == user.id, Measurement.wav_path.is_not(None))
    ).all()
    db.delete(user)
    db.commit()
    for path in wav_files:
        Path(path).unlink(missing_ok=True)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
