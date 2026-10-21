from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import models  # noqa: F401  (регистрира таблиците в Base.metadata)
from app.config import settings
from app.database import Base, add_missing_columns, engine
from app.routers import auth, calibration, devices, measurement, measurements, reports, user_settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Създава липсващите таблици при стартиране.
    Base.metadata.create_all(bind=engine)
    add_missing_columns()
    yield


app = FastAPI(title="Шумомер API", version="2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

app.include_router(auth.router)
app.include_router(devices.router)
app.include_router(user_settings.router)
app.include_router(measurement.router)
app.include_router(measurements.router)
app.include_router(calibration.router)
app.include_router(reports.router)


@app.get("/api/health", tags=["Служебни"])
def health():
    """Проверка на връзката от приложението (екран "Адрес на сървъра")."""
    return {"status": "ok", "version": app.version, "audio_source": settings.audio_source}
