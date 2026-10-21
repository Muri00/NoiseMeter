from fastapi import APIRouter

from app.audio import indicators
from app.deps import CurrentUser, DbSession
from app.models import User, UserSettings
from app.schemas import IndicatorInfo, SettingsIn, SettingsOut

router = APIRouter(prefix="/api/settings", tags=["Настройки"])


def get_or_create_settings(db, user: User) -> UserSettings:
    if user.settings is None:
        user.settings = UserSettings(indicators=list(indicators.DEFAULT_INDICATORS))
        db.commit()
    return user.settings


@router.get("", response_model=SettingsOut)
def read_settings(user: CurrentUser, db: DbSession):
    return get_or_create_settings(db, user)


@router.put("", response_model=SettingsOut)
def update_settings(data: SettingsIn, user: CurrentUser, db: DbSession):
    s = get_or_create_settings(db, user)
    for key, value in data.model_dump().items():
        setattr(s, key, value)
    db.commit()
    return s


@router.get("/indicators", response_model=list[IndicatorInfo])
def available_indicators():
    """Всички показатели, които потребителят може да избере."""
    return [IndicatorInfo(code=c, name=indicators.display_name(c)) for c in indicators.all_indicators()]
