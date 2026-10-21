import re
from datetime import UTC, datetime
from typing import Annotated, Literal

from pydantic import (
    BaseModel, ConfigDict, EmailStr, Field, PlainSerializer, field_validator, model_validator,
)

from app.audio import indicators

# Граници на измервателния интервал според заданието (изискване 3).
ABS_F_MIN_HZ = 3.0
ABS_F_MAX_HZ = 80_000.0

BandMode = Literal["off", "1/1", "1/3"]


# ---------- Общи ----------

def _utc_iso(d: datetime) -> str:
    """В базата времената са в UTC без зона; навън ги даваме с "Z", за да ги
    преобразува приложението в местно време."""
    return d.replace(tzinfo=UTC).isoformat().replace("+00:00", "Z")


UtcDatetime = Annotated[datetime, PlainSerializer(_utc_iso, return_type=str)]


# ---------- Акаунти ----------

class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9_.-]+$")
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    first_name: str | None = Field(default=None, max_length=50)
    last_name: str | None = Field(default=None, max_length=50)

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return _check_password_strength(v)


def _check_password_strength(v: str) -> str:
    if not (re.search(r"[A-Za-zА-Яа-я]", v) and re.search(r"\d", v)):
        raise ValueError("Паролата трябва да съдържа поне една буква и една цифра")
    return v


class ProfileUpdate(BaseModel):
    email: EmailStr
    first_name: str | None = Field(default=None, max_length=50)
    last_name: str | None = Field(default=None, max_length=50)


class PasswordChange(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8, max_length=72)

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        return _check_password_strength(v)


class AccountDelete(BaseModel):
    password: str


class LoginRequest(BaseModel):
    login: str = Field(description="Потребителско име или имейл")
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    email: str
    first_name: str | None
    last_name: str | None


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


# ---------- Устройства ----------

class DeviceIn(BaseModel):
    brand: str = Field(min_length=1, max_length=100)
    model: str = Field(min_length=1, max_length=100)
    serial_number: str = Field(min_length=1, max_length=100)
    sensitivity_dbfs: float = Field(
        ge=-80, le=0, description="dBFS (RMS) при 94 dB SPL, напр. -18 за miniDSP UMIK-1"
    )
    freq_min_hz: float = Field(ge=ABS_F_MIN_HZ, le=ABS_F_MAX_HZ)
    freq_max_hz: float = Field(ge=ABS_F_MIN_HZ, le=ABS_F_MAX_HZ)
    calibration_interval_months: int | None = Field(
        default=12, ge=1, le=120, description="Интервал между калибровките; празно = без срок"
    )

    @model_validator(mode="after")
    def check_range(self):
        if self.freq_min_hz >= self.freq_max_hz:
            raise ValueError("Минималната честота трябва да е по-малка от максималната")
        return self


class DeviceOut(DeviceIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    last_calibration_at: UtcDatetime | None
    next_calibration_due: UtcDatetime | None
    calibration_status: str
    calibration_offset_db: float | None


# ---------- Настройки / показатели ----------

class SettingsIn(BaseModel):
    indicators: list[str] = Field(min_length=indicators.MIN_INDICATORS)
    f_min_hz: float = Field(default=20.0, ge=ABS_F_MIN_HZ, le=ABS_F_MAX_HZ)
    f_max_hz: float = Field(default=20000.0, ge=ABS_F_MIN_HZ, le=ABS_F_MAX_HZ)
    band_mode: BandMode = "1/3"

    @field_validator("indicators")
    @classmethod
    def check_indicators(cls, v: list[str]) -> list[str]:
        bad = [c for c in v if not indicators.is_valid(c)]
        if bad:
            raise ValueError(f"Невалидни показатели: {', '.join(bad)}")
        if len(set(v)) != len(v):
            raise ValueError("Показателите не трябва да се повтарят")
        return v

    @model_validator(mode="after")
    def check_range(self):
        if self.f_min_hz >= self.f_max_hz:
            raise ValueError("Минималната честота трябва да е по-малка от максималната")
        return self


class SettingsOut(SettingsIn):
    model_config = ConfigDict(from_attributes=True)


class IndicatorInfo(BaseModel):
    code: str
    name: str




# ---------- Измервания и история ----------

class MeasurementOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str | None
    started_at: UtcDatetime
    ended_at: UtcDatetime | None
    duration_s: float
    sample_rate: int
    f_min_hz: float
    f_max_hz: float
    band_mode: str
    device_id: int | None
    device_info: dict
    indicators: list[str]
    summary: dict | None
    has_wav: bool
    location: str | None = None
    source: str | None = None
    zone_code: str | None = None
    norm_day: float | None = None
    norm_evening: float | None = None
    norm_night: float | None = None


class BandsOut(BaseModel):
    mode: str
    centers: list[float]
    levels: list[float]


class MeasurementDetailOut(MeasurementOut):
    frame_count: int
    average_bands: BandsOut | None


class SeriesOut(BaseModel):
    t: list[float]
    series: dict[str, list[float]]


class TimelinePoint(BaseModel):
    ts: UtcDatetime
    LAeq: float
    LCeq: float
    LZeq: float
    LAeq_max: float  # най-високото 1-секундно LAeq в интервала


class HistoryOut(BaseModel):
    period_from: UtcDatetime
    period_to: UtcDatetime
    count: int
    total_duration_s: float
    LAeq: float | None
    LCeq: float | None
    LZeq: float | None
    LAeq_1s_max: float | None
    LAeq_1s_min: float | None
    bucket_s: int
    timeline: list[TimelinePoint]
    measurements: list[MeasurementOut]


# ---------- Калибровка ----------

class CalibrationMeta(BaseModel):
    """Данни за протокола по EN ISO/IEC 17025: еталон, условия на средата, неопределеност."""

    calibrator_brand: str | None = Field(default=None, max_length=100)
    calibrator_model: str | None = Field(default=None, max_length=100)
    calibrator_serial: str | None = Field(default=None, max_length=100)
    calibrator_certificate: str | None = Field(default=None, max_length=100)
    temperature_c: float | None = Field(default=None, ge=-20, le=60)
    humidity_pct: float | None = Field(default=None, ge=0, le=100)
    pressure_kpa: float | None = Field(default=None, ge=50, le=120)
    uncertainty_db: float | None = Field(default=None, ge=0, le=5)
    notes: str | None = Field(default=None, max_length=1000)


class AutoCalibrationIn(CalibrationMeta):
    reference_level_db: float = Field(default=94.0, ge=70, le=140)
    reference_freq_hz: float = Field(default=1000.0, ge=100, le=10000)
    duration_s: float = Field(default=5.0, ge=2, le=30)


class ManualCalibrationIn(CalibrationMeta):
    """Ръчна калибровка: или директна корекция (offset_db), или показание на уреда
    при поставен калибратор (measured_level_db) и еталонната стойност."""

    offset_db: float | None = Field(default=None, ge=-30, le=30)
    reference_level_db: float | None = Field(default=None, ge=70, le=140)
    reference_freq_hz: float | None = Field(default=None, ge=100, le=10000)
    measured_level_db: float | None = Field(default=None, ge=0, le=160)

    @model_validator(mode="after")
    def check_mode(self):
        by_reading = self.reference_level_db is not None and self.measured_level_db is not None
        if (self.offset_db is None) == (not by_reading):
            raise ValueError(
                "Въведете или корекция, или еталонна стойност и показание на уреда"
            )
        return self


class CalibrationOut(CalibrationMeta):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: int
    created_at: UtcDatetime
    applied_at: UtcDatetime | None
    method: str
    status: str
    reference_level_db: float | None
    reference_freq_hz: float | None
    measured_level_db: float | None
    measured_freq_hz: float | None
    stability_db: float | None
    offset_before_db: float | None
    offset_db: float
    drift_db: float | None


# ---------- Отчети и сертификати ----------

class MeasurementUpdate(BaseModel):
    """Място, източник и норми на измерването. Ако е избрана зона от Наредба 6
    и нормите не са подадени, те се попълват от таблицата."""

    name: str | None = Field(default=None, max_length=200)
    location: str | None = Field(default=None, max_length=200)
    source: str | None = Field(default=None, max_length=200)
    zone_code: str | None = Field(default=None, max_length=20)
    norm_day: float | None = Field(default=None, ge=20, le=120)
    norm_evening: float | None = Field(default=None, ge=20, le=120)
    norm_night: float | None = Field(default=None, ge=20, le=120)


class ZoneOut(BaseModel):
    code: str
    name: str
    day: float
    evening: float
    night: float


class OrganizationSettings(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    org_name: str | None = Field(default=None, max_length=300)
    org_address: str | None = Field(default=None, max_length=300)
    org_accreditation: str | None = Field(default=None, max_length=2000)


DEFAULT_METHODS = ["БДС ISO 1996-1:2016", "БДС ISO 1996-2:2018"]


class CertificateIn(BaseModel):
    measurement_ids: list[int] = Field(min_length=1, max_length=50)
    title: str | None = Field(default=None, max_length=300)
    methods: list[Annotated[str, Field(max_length=300)]] = Field(default_factory=lambda: list(DEFAULT_METHODS))
    # Празно = автоматично от зоните на измерванията.
    normative: list[Annotated[str, Field(max_length=300)]] | None = None
    remarks: str | None = Field(default=None, max_length=3000)
    # Празно = текущият потребител.
    performed_by: list[Annotated[str, Field(max_length=100)]] | None = None


class CertificateOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    number: str
    issued_at: UtcDatetime
    data: dict
