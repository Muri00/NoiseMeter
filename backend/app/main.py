from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exception_handlers import http_exception_handler, request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware

from app import models  # noqa: F401  (регистрира таблиците в Base.metadata)
from app.config import settings
from app.database import Base, add_missing_columns, engine
from app.i18n import translate
from app.routers import admin, auth, calibration, devices, measurement, measurements, reports, user_settings
from app.seed import seed


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Създава липсващите таблици при стартиране.
    Base.metadata.create_all(bind=engine)
    add_missing_columns()
    seed()
    yield


app = FastAPI(title="METRAVA API", version="3.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

# Съобщенията за грешки се превеждат според езика на приложението (Accept-Language).
@app.exception_handler(HTTPException)
async def localized_http_exception(request: Request, exc: HTTPException):
    if isinstance(exc.detail, str):
        exc.detail = translate(exc.detail, request.headers.get("accept-language"))
    return await http_exception_handler(request, exc)


@app.exception_handler(RequestValidationError)
async def localized_validation_error(request: Request, exc: RequestValidationError):
    lang = request.headers.get("accept-language")
    errors = [{**err, "msg": translate(err.get("msg", ""), lang)} for err in exc.errors()]
    return await request_validation_exception_handler(request, RequestValidationError(errors, body=exc.body))


app.include_router(auth.router)
app.include_router(devices.router)
app.include_router(user_settings.router)
app.include_router(measurement.router)
app.include_router(measurements.router)
app.include_router(calibration.router)
app.include_router(reports.router)
app.include_router(admin.router)


@app.get("/api/health", tags=["Служебни"])
def health():
    """Проверка на връзката от приложението (екран "Адрес на сървъра")."""
    return {"status": "ok", "version": app.version, "audio_source": settings.audio_source}
