"""Начални данни: зони с норми и стандарти. Записват се само ако таблиците са празни;
след това се управляват от администратора."""

from sqlalchemy import select

from app.audio import weighting
from app.database import SessionLocal
from app.models import Standard, Zone

# Наредба № 6/2006, Приложение 2, таблица 2 - открити територии.
DEFAULT_ZONES = [
    ("1", "Жилищни зони и територии", 55, 50, 45),
    ("2", "Централни градски части", 60, 55, 50),
    ("3", "Територии, подложени на въздействие на интензивен автомобилен трафик", 60, 55, 50),
    ("4", "Територии, подложени на въздействие на железопътен трафик", 65, 60, 55),
    ("5", "Територии, подложени на въздействие на самолетен шум", 65, 65, 55),
    ("6", "Производствено-складови територии и зони", 70, 70, 70),
    ("7", "Зони за отдих", 45, 40, 35),
    ("8", "Курортни зони", 45, 40, 35),
]

# Наредба № 6/2006, Приложение 2, таблица 1 - помещения в жилищни и обществени сгради.
DEFAULT_INDOOR_ZONES = [
    ("П1", "Стаи в лечебни заведения и санаториуми, операционни зали", 30, 30, 30),
    ("П2", "Жилищни стаи, спални в детски заведения и общежития, почивни станции, хотелски стаи", 35, 35, 30),
    ("П3", "Лекарски кабинети, зали за конференции, зрителни зали на театри и кинозали", 40, 40, 35),
    ("П4", "Класни стаи и аудитории, помещения за научноизследователска дейност, читални", 40, 40, 40),
    ("П5", "Работни помещения в административни сгради", 50, 50, 50),
    ("П6", "Кафе-сладкарници, столове, фоайета, ресторанти, клубове, салони", 55, 55, 55),
    ("П7", "Търговски зали на магазини, зали за пътници в гари", 60, 60, 60),
]

_TAUS = {"fast": weighting.TAU_FAST, "slow": weighting.TAU_SLOW,
         "impulse_rise": weighting.TAU_IMPULSE_RISE, "impulse_decay": weighting.TAU_IMPULSE_DECAY}

DEFAULT_STANDARDS = [
    {
        "code": "IEC61672-1:2013",
        "name": "БДС EN IEC 61672-1:2013",
        "is_default": True,
        # Точните полюсни честоти от приложение E на IEC 61672-1.
        "params": {"poles": list(weighting.IEC_POLES), **_TAUS},
    },
    {
        "code": "ANSI-S1.4-1983",
        "name": "ANSI S1.4-1983 (R2006)",
        "is_default": False,
        # Закръглените полюсни честоти от ANSI S1.4 / IEC 60651.
        "params": {"poles": [20.6, 107.7, 737.9, 12200.0], **_TAUS},
    },
]


def seed() -> None:
    with SessionLocal() as db:
        if db.scalar(select(Zone.id).limit(1)) is None:
            for i, (code, name, day, evening, night) in enumerate(DEFAULT_ZONES):
                db.add(Zone(code=code, name=name, category="outdoor", day=day, evening=evening,
                            night=night, sort_order=i))
        # Помещенията се добавят и към вече създадена база, ако там още няма такива.
        if db.scalar(select(Zone.id).where(Zone.category == "indoor").limit(1)) is None:
            for i, (code, name, day, evening, night) in enumerate(DEFAULT_INDOOR_ZONES):
                if db.scalar(select(Zone.id).where(Zone.code == code)) is None:
                    db.add(Zone(code=code, name=name, category="indoor", day=day, evening=evening,
                                night=night, sort_order=i))
        if db.scalar(select(Standard.id).limit(1)) is None:
            for i, s in enumerate(DEFAULT_STANDARDS):
                db.add(Standard(sort_order=i, **s))
        db.commit()
