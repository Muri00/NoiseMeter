import calendar
from datetime import UTC, datetime, timedelta

from sqlalchemy import (
    JSON, BigInteger, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint, func,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

# Време с точност до милисекунда (в MariaDB DATETIME по подразбиране е до секунда).
PreciseDateTime = DateTime().with_variant(mysql.DATETIME(fsp=3), "mysql")


def utcnow() -> datetime:
    """Текущото време в UTC. В базата се пази UTC без часова зона."""
    return datetime.now(UTC).replace(tzinfo=None)


def add_months(d: datetime, months: int) -> datetime:
    """Добавя месеци към дата (31.01 + 1 месец = 28/29.02)."""
    month_index = d.month - 1 + months
    year, month = d.year + month_index // 12, month_index % 12 + 1
    day = min(d.day, calendar.monthrange(year, month)[1])
    return d.replace(year=year, month=month, day=day)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    # Само bcrypt хеш (със сол); паролата в чист вид никога не се записва.
    password_hash: Mapped[str] = mapped_column(String(255))
    # Време на последната смяна на паролата (UTC, до секунда) - обезсилва старите токени.
    password_changed_at: Mapped[datetime | None] = mapped_column(DateTime)
    first_name: Mapped[str | None] = mapped_column(String(50))
    last_name: Mapped[str | None] = mapped_column(String(50))
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    devices: Mapped[list["Device"]] = relationship(
        back_populates="owner", cascade="all, delete-orphan"
    )
    settings: Mapped["UserSettings | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class Device(Base):
    """Входно устройство (измервателен микрофон) - изискване 2."""

    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("user_id", "serial_number", name="uq_device_user_serial"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    brand: Mapped[str] = mapped_column(String(100))
    model: Mapped[str] = mapped_column(String(100))
    serial_number: Mapped[str] = mapped_column(String(100))
    # Чувствителност в dBFS (RMS) при 94 dB SPL (1 Pa) - каквото показва цифровият
    # (USB) микрофон, когато е поставен в калибратор 94 dB.
    sensitivity_dbfs: Mapped[float] = mapped_column(Float)
    freq_min_hz: Mapped[float] = mapped_column(Float)
    freq_max_hz: Mapped[float] = mapped_column(Float)
    # Корекция, получена от калибровка (етап 2). NULL = използва се само чувствителността.
    calibration_offset_db: Mapped[float | None] = mapped_column(Float)
    # През колко месеца устройството трябва да се калибрира (ISO/IEC 17025: периодична калибровка).
    calibration_interval_months: Mapped[int | None] = mapped_column(Integer, default=12)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    owner: Mapped[User] = relationship(back_populates="devices")
    calibrations: Mapped[list["Calibration"]] = relationship(
        back_populates="device", cascade="all, delete-orphan", passive_deletes=True
    )

    @property
    def last_calibration_at(self) -> datetime | None:
        applied = [c.applied_at for c in self.calibrations if c.status == "applied" and c.applied_at]
        return max(applied, default=None)

    @property
    def next_calibration_due(self) -> datetime | None:
        last = self.last_calibration_at
        if last is None or not self.calibration_interval_months:
            return None
        return add_months(last, self.calibration_interval_months)

    @property
    def calibration_status(self) -> str:
        """"none" (не е калибрирано), "valid", "due_soon" (до 30 дни) или "expired"."""
        if self.last_calibration_at is None:
            return "none"
        due = self.next_calibration_due
        if due is None:
            return "valid"
        now = utcnow()
        if due < now:
            return "expired"
        return "due_soon" if due - now <= timedelta(days=30) else "valid"

    @property
    def level_offset_db(self) -> float:
        """Ниво в dB SPL, което съответства на сигнал с RMS = 1 (0 dBFS)."""
        return 94.0 - self.sensitivity_dbfs + (self.calibration_offset_db or 0.0)


class UserSettings(Base):
    """Лични настройки за измерване, включително избраните показатели - изискване 3.9."""

    __tablename__ = "user_settings"

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    indicators: Mapped[list[str]] = mapped_column(JSON)
    f_min_hz: Mapped[float] = mapped_column(Float, default=20.0)
    f_max_hz: Mapped[float] = mapped_column(Float, default=20000.0)
    band_mode: Mapped[str] = mapped_column(String(8), default="1/3")

    # Данни за организацията - заглавна част на сертификатите (изискване 8).
    org_name: Mapped[str | None] = mapped_column(String(300))
    org_address: Mapped[str | None] = mapped_column(String(300))
    org_accreditation: Mapped[str | None] = mapped_column(Text)

    user: Mapped[User] = relationship(back_populates="settings")


class Measurement(Base):
    """Записано измерване (изискване 4). Данните за устройството се копират в
    device_info, за да остане записът пълен, дори устройството да се промени или изтрие."""

    __tablename__ = "measurements"
    __table_args__ = (Index("ix_measurements_user_started", "user_id", "started_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    device_id: Mapped[int | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"))
    name: Mapped[str | None] = mapped_column(String(200))
    started_at: Mapped[datetime] = mapped_column(PreciseDateTime, default=utcnow)
    ended_at: Mapped[datetime | None] = mapped_column(PreciseDateTime)
    duration_s: Mapped[float] = mapped_column(Float, default=0.0)
    sample_rate: Mapped[int] = mapped_column(Integer)
    f_min_hz: Mapped[float] = mapped_column(Float)
    f_max_hz: Mapped[float] = mapped_column(Float)
    band_mode: Mapped[str] = mapped_column(String(8))
    # Марка, модел, сериен №, чувствителност, лента, калибровка към момента на записа.
    device_info: Mapped[dict] = mapped_column(JSON)
    # Показателите, които потребителят е наблюдавал по време на записа.
    indicators: Mapped[list[str]] = mapped_column(JSON)
    # Крайните стойности за цялото измерване (Leq, max, min за всички филтри).
    summary: Mapped[dict | None] = mapped_column(JSON)
    wav_path: Mapped[str | None] = mapped_column(String(500))

    # Място и норми - за отчетите и сертификатите (изисквания 7 и 8).
    location: Mapped[str | None] = mapped_column(String(200))  # място / точка на измерване
    source: Mapped[str | None] = mapped_column(String(200))  # източник / режим, напр. "Автомобилен трафик"
    zone_code: Mapped[str | None] = mapped_column(String(20))  # ред от табл. 2 на Наредба 6 или "custom"
    norm_day: Mapped[float | None] = mapped_column(Float)
    norm_evening: Mapped[float | None] = mapped_column(Float)
    norm_night: Mapped[float | None] = mapped_column(Float)

    @property
    def has_wav(self) -> bool:
        return self.wav_path is not None

    frames: Mapped[list["MeasurementFrame"]] = relationship(
        back_populates="measurement", cascade="all, delete-orphan", passive_deletes=True,
        order_by="MeasurementFrame.t",
    )


class MeasurementFrame(Base):
    """Един ред на всяка секунда от записа: нивата с филтри и октавните ленти."""

    __tablename__ = "measurement_frames"

    id: Mapped[int] = mapped_column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True)
    measurement_id: Mapped[int] = mapped_column(
        ForeignKey("measurements.id", ondelete="CASCADE"), index=True
    )
    ts: Mapped[datetime] = mapped_column(PreciseDateTime, index=True)
    t: Mapped[float] = mapped_column(Float)  # секунди от началото на измерването
    # Leq за последната секунда - отделни колони за бързи справки по период.
    leq_a: Mapped[float] = mapped_column(Float)
    leq_c: Mapped[float] = mapped_column(Float)
    leq_z: Mapped[float] = mapped_column(Float)
    # Всички показатели за секундата: {"LAF": .., "LAFmax": .., "LAeq": .., ...}
    levels: Mapped[dict] = mapped_column(JSON)
    # Октавни ленти: {"centers": [...], "levels": [...]} или NULL
    bands: Mapped[dict | None] = mapped_column(JSON)

    measurement: Mapped[Measurement] = relationship(back_populates="frames")


class Calibration(Base):
    """Протокол от калибровка на устройство (изискване 6, EN ISO/IEC 17025)."""

    __tablename__ = "calibrations"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = mapped_column(PreciseDateTime, default=utcnow)
    applied_at: Mapped[datetime | None] = mapped_column(PreciseDateTime)
    method: Mapped[str] = mapped_column(String(10))  # "auto" или "manual"
    status: Mapped[str] = mapped_column(String(10))  # "pending", "applied", "rejected"

    # Еталон (акустичен калибратор)
    reference_level_db: Mapped[float | None] = mapped_column(Float)
    reference_freq_hz: Mapped[float | None] = mapped_column(Float)
    calibrator_brand: Mapped[str | None] = mapped_column(String(100))
    calibrator_model: Mapped[str | None] = mapped_column(String(100))
    calibrator_serial: Mapped[str | None] = mapped_column(String(100))
    calibrator_certificate: Mapped[str | None] = mapped_column(String(100))

    # Резултат
    measured_level_db: Mapped[float | None] = mapped_column(Float)  # показание преди корекцията
    measured_freq_hz: Mapped[float | None] = mapped_column(Float)
    stability_db: Mapped[float | None] = mapped_column(Float)  # стандартно отклонение на показанията
    offset_before_db: Mapped[float | None] = mapped_column(Float)
    offset_db: Mapped[float] = mapped_column(Float)  # новата корекция
    drift_db: Mapped[float | None] = mapped_column(Float)  # промяна спрямо предишната калибровка
    uncertainty_db: Mapped[float | None] = mapped_column(Float)  # разширена неопределеност (k=2)

    # Условия на средата
    temperature_c: Mapped[float | None] = mapped_column(Float)
    humidity_pct: Mapped[float | None] = mapped_column(Float)
    pressure_kpa: Mapped[float | None] = mapped_column(Float)
    notes: Mapped[str | None] = mapped_column(Text)

    device: Mapped[Device] = relationship(back_populates="calibrations")


class Certificate(Base):
    """Издаден сертификат (протокол) от измерване (изискване 8). Всички данни, нужни за
    PDF документа, се копират в `data`, за да изглежда сертификатът еднакво и по-късно."""

    __tablename__ = "certificates"
    __table_args__ = (UniqueConstraint("user_id", "number", name="uq_certificate_user_number"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    number: Mapped[str] = mapped_column(String(30))
    issued_at: Mapped[datetime] = mapped_column(PreciseDateTime, default=utcnow)
    data: Mapped[dict] = mapped_column(JSON)
