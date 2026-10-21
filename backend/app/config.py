from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Конфигурация на сървъра. Стойностите се четат от променливи на средата или от .env файл."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "mysql+pymysql://noisemeter:CHANGE_ME@localhost:3306/NoiseMeterDB?charset=utf8mb4"

    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 720

    audio_source: Literal["device", "simulator"] = "device"
    # Сигнал на симулатора: "noise" (шум + тон) или "calibrator" (чист тон 1 kHz, 94 dB SPL
    # при чувствителност -18 dBFS) - за проба на автоматичната калибровка без калибратор.
    simulator_signal: Literal["noise", "calibrator"] = "noise"
    audio_device: str = ""
    sample_rate: int = 48000
    # Дължина на един блок за обработка (и на един кадър към клиента), в секунди.
    block_duration: float = 0.1

    # Папка за WAV записите (относително спрямо папката, от която се стартира сървърът).
    recordings_dir: str = "recordings"
    # През колко секунди се записва ред с нивата в базата.
    record_interval: float = 1.0
    # Справките от историята са за максимум толкова дни назад (изискване 5: 3 месеца).
    history_max_days: int = 92
    # Местно време за периодите ден/вечер/нощ в отчетите (в базата времената са UTC).
    timezone: str = "Europe/Sofia"


settings = Settings()
