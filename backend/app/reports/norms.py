"""Норми и периоди по Наредба № 6/2006 за показателите за шум в околната среда.

Периоди (чл. 5): ден 07:00-19:00, вечер 19:00-23:00, нощ 23:00-07:00.
Граничните стойности (по зони) са в таблицата zones в базата и се управляват от администратора.
Периодът може да се избере ръчно за цялото измерване; иначе се определя по часа на всяка секунда.
"""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import numpy as np

from app.config import settings

PERIODS = ("day", "evening", "night")
PERIOD_NAMES = {"day": "Ден", "evening": "Вечер", "night": "Нощ"}


def local_tz() -> ZoneInfo:
    return ZoneInfo(settings.timezone)


def to_local(utc_naive: datetime) -> datetime:
    """Време от базата (UTC без зона) -> местно време."""
    return utc_naive.replace(tzinfo=ZoneInfo("UTC")).astimezone(local_tz())


def period_of(utc_naive: datetime) -> str:
    hour = to_local(utc_naive).hour
    if 7 <= hour < 19:
        return "day"
    if 19 <= hour < 23:
        return "evening"
    return "night"


def norm_for(measurement, period: str) -> float | None:
    return getattr(measurement, f"norm_{period}")


def place_label(measurement) -> str:
    """Мястото за отчетите; при серия от точки в едно помещение се добавя и № на точката."""
    label = measurement.location or ""
    if measurement.point_no and (measurement.point_count or 0) > 1:
        label = f"{label}, т. {measurement.point_no}" if label else f"т. {measurement.point_no}"
    return label


def energy_mean(levels) -> float | None:
    arr = np.asarray(list(levels), dtype=float)
    if arr.size == 0:
        return None
    return round(float(10 * np.log10(np.mean(10 ** (arr / 10)))), 2)


def frame_period(measurement, utc_naive: datetime) -> str:
    """Периодът на една секунда: избраният за измерването или определеният по часа."""
    return measurement.period if measurement.period in PERIODS else period_of(utc_naive)


def period_levels(frames, forced_period: str | None = None) -> dict[str, dict]:
    """LAeq за всеки период (ден/вечер/нощ), в който попада измерването.

    frames: редове с атрибути ts и leq_a (по един на секунда).
    forced_period: ако е зададен, цялото измерване се отнася към този период.
    Връща {"day": {"laeq": 54.3, "seconds": 600, "start": dt, "end": dt}, ...}
    """
    groups: dict[str, list] = {}
    for f in frames:
        key = forced_period if forced_period in PERIODS else period_of(f.ts)
        groups.setdefault(key, []).append(f)
    out = {}
    for period in PERIODS:
        items = groups.get(period)
        if items:
            out[period] = {
                "laeq": energy_mean(f.leq_a for f in items),
                "seconds": len(items),
                "start": items[0].ts,
                "end": items[-1].ts + timedelta(seconds=1),
            }
    return out


def within_limit(value: float | None, norm: float | None) -> bool | None:
    """True/False, ако има норма; None, ако нормата не е зададена."""
    if value is None or norm is None:
        return None
    return value <= norm


def apply_zone(db, measurement, zone_code: str | None) -> None:
    """Задава зоната на измерването и копира нормите ѝ (ден/вечер/нощ) от таблицата zones.
    Копието пази записа непроменен, дори администраторът по-късно да промени нормите."""
    from sqlalchemy import select

    from app.models import Zone

    measurement.zone_code = zone_code or None
    zone = db.scalar(select(Zone).where(Zone.code == zone_code)) if zone_code else None
    for period in PERIODS:
        setattr(measurement, f"norm_{period}", getattr(zone, period) if zone else None)
