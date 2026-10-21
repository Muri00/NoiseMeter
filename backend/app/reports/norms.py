"""Норми и периоди по Наредба № 6/2006 за показателите за шум в околната среда.

Периоди (чл. 5): ден 07:00-19:00, вечер 19:00-23:00, нощ 23:00-07:00.
Граничните стойности са от Приложение 2, таблица 2 - еквивалентно ниво в dB(A).
Преди официална употреба сверете стойностите с действащата редакция на наредбата.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import numpy as np

from app.config import settings

PERIODS = ("day", "evening", "night")
PERIOD_NAMES = {"day": "Ден", "evening": "Вечер", "night": "Нощ"}


@dataclass(frozen=True)
class Zone:
    code: str
    name: str
    day: float
    evening: float
    night: float


ZONES = [
    Zone("1", "Жилищни зони и територии", 55, 50, 45),
    Zone("2", "Централни градски части", 60, 55, 50),
    Zone("3", "Територии, подложени на въздействие на интензивен автомобилен трафик", 60, 55, 50),
    Zone("4", "Територии, подложени на въздействие на железопътен трафик", 65, 60, 55),
    Zone("5", "Територии, подложени на въздействие на самолетен шум", 65, 65, 55),
    Zone("6", "Производствено-складови територии и зони", 70, 70, 70),
    Zone("7", "Зони за отдих", 45, 40, 35),
    Zone("8", "Курортни зони", 45, 40, 35),
]
ZONES_BY_CODE = {z.code: z for z in ZONES}


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


def energy_mean(levels) -> float | None:
    arr = np.asarray(list(levels), dtype=float)
    if arr.size == 0:
        return None
    return round(float(10 * np.log10(np.mean(10 ** (arr / 10)))), 2)


def period_levels(frames) -> dict[str, dict]:
    """LAeq за всеки период (ден/вечер/нощ), в който попада измерването.

    frames: редове с атрибути ts и leq_a (по един на секунда).
    Връща {"day": {"laeq": 54.3, "seconds": 600, "start": dt, "end": dt}, ...}
    """
    groups: dict[str, list] = {}
    for f in frames:
        groups.setdefault(period_of(f.ts), []).append(f)
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
