from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.security import decode_access_token

_bearer = HTTPBearer(auto_error=False)

DbSession = Annotated[Session, Depends(get_db)]


def user_from_token(db: Session, token: str | None) -> User | None:
    if not token:
        return None
    decoded = decode_access_token(token)
    if decoded is None:
        return None
    user_id, issued_at = decoded
    user = db.get(User, user_id)
    # Токените, издадени преди последната смяна на паролата, вече не са валидни.
    if user is None or (user.password_changed_at and issued_at < user.password_changed_at):
        return None
    return user


def get_current_user(
    db: DbSession,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    user = user_from_token(db, creds.credentials if creds else None)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Невалиден или изтекъл токен",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
