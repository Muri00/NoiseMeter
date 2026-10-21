from datetime import UTC, datetime, timedelta

import bcrypt
import jwt

from app.config import settings

# bcrypt обработва само първите 72 байта от паролата.
_BCRYPT_MAX_BYTES = 72


def hash_password(password: str) -> str:
    """Хешира паролата с bcrypt (адаптивна хеш функция с уникална сол за всеки потребител)."""
    data = password.encode("utf-8")[:_BCRYPT_MAX_BYTES]
    return bcrypt.hashpw(data, bcrypt.gensalt(rounds=12)).decode("ascii")


def verify_password(password: str, password_hash: str) -> bool:
    data = password.encode("utf-8")[:_BCRYPT_MAX_BYTES]
    try:
        return bcrypt.checkpw(data, password_hash.encode("ascii"))
    except ValueError:
        return False


def create_access_token(user_id: int) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=settings.jwt_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> tuple[int, datetime] | None:
    """Връща (id на потребителя, време на издаване) или None, ако токенът е невалиден или изтекъл."""
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        return int(payload["sub"]), datetime.fromtimestamp(payload["iat"], UTC).replace(tzinfo=None)
    except (jwt.PyJWTError, KeyError, ValueError, TypeError):
        return None
