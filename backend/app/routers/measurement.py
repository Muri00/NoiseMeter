"""Измерване в реално време през WebSocket (изискване 3) и запис (изискване 4).

Протокол (JSON съобщения). Токенът се изпраща в първото съобщение, а не в адреса,
за да не попада в логовете на сървъра:
  клиент -> {"action": "auth", "token": "<JWT>"}
  сървър -> {"type": "auth_ok"}            (или затваря връзката с код 4401)
  клиент -> {"action": "start", "device_id": 1, "f_min": 20, "f_max": 20000, "band_mode": "1/3",
             "record": true, "save_wav": true, "name": "Офис 2"}
  сървър -> {"type": "started", "sample_rate": 48000, "f_min": 20, "f_max": 20000, "band_mode": "1/3",
             "measurement_id": 15}       (measurement_id е null, ако не се записва)
  сървър -> {"type": "frame", "t": 0.1, "levels": {"LAF": 54.2, ...}, "bands": {...}}  (на всеки 100 ms)
  клиент -> {"action": "stop"}
  сървър -> {"type": "stopped", "duration": 12.3, "levels": {...}, "measurement_id": 15}
  сървър -> {"type": "error", "message": "..."}
"""

import asyncio
import contextlib

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from pydantic import BaseModel, Field, ValidationError, model_validator

from app.audio import indicators as indicator_codes
from app.audio.meter import LevelMeter, MeterConfig
from app.audio.source import AudioSourceError, audio_blocks, microphone_lock
from app.config import settings
from app.database import SessionLocal
from app.deps import user_from_token
from app.i18n import translate
from app.models import Device, Standard, UserSettings
from app.recording import Recorder
from app.schemas import ABS_F_MAX_HZ, ABS_F_MIN_HZ, BandMode, Period, PlaceType

router = APIRouter(tags=["Измерване"])


class StartRequest(BaseModel):
    action: str
    device_id: int
    f_min: float = 20.0
    f_max: float = 20000.0
    band_mode: BandMode = "1/3"
    record: bool = False
    save_wav: bool = False
    name: str | None = Field(default=None, max_length=200)
    # Място и норми, задавани при самото измерване.
    location: str | None = Field(default=None, max_length=200)
    place_type: PlaceType | None = None
    # Точка от серия в едно помещение (броят на точките се избира на място).
    point_no: int | None = Field(default=None, ge=1, le=100)
    point_count: int | None = Field(default=None, ge=1, le=100)
    series_id: str | None = Field(default=None, max_length=40)
    source: str | None = Field(default=None, max_length=200)
    zone_code: str | None = Field(default=None, max_length=20)
    period: Period | None = None  # None - по часа
    # Стандарт, от който се вземат коефициентите на филтрите (None - стандартът по подразбиране).
    standard_code: str | None = Field(default=None, max_length=40)

    @model_validator(mode="after")
    def check_range(self):
        if not (ABS_F_MIN_HZ <= self.f_min < self.f_max <= ABS_F_MAX_HZ):
            raise ValueError(
                f"Интервалът трябва да е в границите {ABS_F_MIN_HZ:g} - {ABS_F_MAX_HZ:g} Hz "
                "и минималната честота да е по-малка от максималната"
            )
        if self.point_no and self.point_count and self.point_no > self.point_count:
            raise ValueError("Номерът на точката не може да е по-голям от броя на точките")
        return self


async def _send_error(ws: WebSocket, message: str) -> None:
    await ws.send_json({"type": "error", "message": translate(message, ws.state.lang)})


@router.websocket("/ws/measure")
async def measure(ws: WebSocket):
    await ws.accept()
    ws.state.lang = None
    try:
        user_id = await _authenticate(ws)
        if user_id is None:
            await ws.close(code=4401, reason="Unauthorized")
            return
        await ws.send_json({"type": "auth_ok"})

        while True:
            msg = await ws.receive_json()
            if msg.get("action") == "start":
                await _run_session(ws, user_id, msg)
    except WebSocketDisconnect:
        pass


async def _authenticate(ws: WebSocket) -> int | None:
    try:
        msg = await asyncio.wait_for(ws.receive_json(), timeout=10)
    except (TimeoutError, ValueError):
        return None
    if not isinstance(msg, dict) or msg.get("action") != "auth":
        return None
    # Езикът на съобщенията за грешки ("bg" или "en").
    ws.state.lang = msg.get("lang")
    with SessionLocal() as db:
        user = user_from_token(db, msg.get("token"))
        return user.id if user else None


async def _run_session(ws: WebSocket, user_id: int, msg: dict) -> None:
    try:
        req = StartRequest.model_validate(msg)
    except ValidationError as e:
        await _send_error(ws, "; ".join(translate(err["msg"], ws.state.lang) for err in e.errors()))
        return

    with SessionLocal() as db:
        device = db.get(Device, req.device_id)
        if device is None or device.user_id != user_id:
            await _send_error(ws, "Устройството не е намерено")
            return
        dev_min, dev_max, offset_db = device.freq_min_hz, device.freq_max_hz, device.level_offset_db
        user_settings = db.get(UserSettings, user_id)
        indicators = user_settings.indicators if user_settings else indicator_codes.DEFAULT_INDICATORS
        query = select(Standard)
        query = query.where(Standard.code == req.standard_code) if req.standard_code \
            else query.order_by(Standard.is_default.desc(), Standard.sort_order)
        standard = db.scalars(query).first()
        if standard is None:
            await _send_error(ws, "Стандартът не е намерен")
            return
        standard_code, standard_name, params = standard.code, standard.name, dict(standard.params)

    # Интервал извън работната лента на микрофона се допуска, но резултатът е ненадежден -
    # отбелязва се в записа и клиентът показва предупреждение.
    out_of_band = req.f_min < dev_min or req.f_max > dev_max

    if microphone_lock.locked():
        await _send_error(ws, "Микрофонът в момента се използва от друго измерване или калибровка")
        return

    async with microphone_lock:
        fs = settings.sample_rate
        # Над честотата на Найкуист не може да се измерва, независимо от избрания интервал.
        f_max = min(req.f_max, fs / 2)
        meter = LevelMeter(MeterConfig(
            fs, offset_db, req.f_min, f_max, req.band_mode,
            poles=tuple(params["poles"]),
            taus={k: params[k] for k in ("fast", "slow", "impulse_rise", "impulse_decay")},
        ))
        recorder = None
        if req.record:
            recorder = Recorder(
                user_id=user_id, device_id=req.device_id, meter=meter,
                indicators=indicators, name=req.name, save_wav=req.save_wav,
                place={"location": req.location, "source": req.source, "zone_code": req.zone_code,
                       "period": req.period, "place_type": req.place_type, "point_no": req.point_no,
                       "point_count": req.point_count, "series_id": req.series_id},
                standard=(standard_code, standard_name), out_of_band=out_of_band,
            )
        measurement_id = recorder.measurement_id if recorder else None

        await ws.send_json({
            "type": "started", "sample_rate": fs, "f_min": req.f_min, "f_max": f_max,
            "band_mode": req.band_mode, "measurement_id": measurement_id,
            "standard": standard_name, "out_of_band": out_of_band,
            "device_band": [dev_min, dev_max],
        })

        async def pump():
            blocks = audio_blocks(fs, int(fs * settings.block_duration))
            try:
                async for block in blocks:
                    frame = meter.process(block)
                    if recorder:
                        recorder.add_block(block)
                    await ws.send_json({"type": "frame", **frame})
            finally:
                await blocks.aclose()

        pump_task = asyncio.create_task(pump())
        try:
            while True:
                recv_task = asyncio.create_task(ws.receive_json())
                done, _ = await asyncio.wait({pump_task, recv_task}, return_when=asyncio.FIRST_COMPLETED)

                if pump_task in done:
                    recv_task.cancel()
                    exc = pump_task.exception()
                    if isinstance(exc, AudioSourceError):
                        await _send_error(ws, str(exc))
                    elif exc is not None:
                        raise exc
                    return

                if recv_task.result().get("action") == "stop":
                    break
        finally:
            pump_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await pump_task
            # Записът се приключва и когато връзката прекъсне.
            if recorder:
                recorder.finish(meter.summary())

        await ws.send_json({
            "type": "stopped", "duration": round(meter.elapsed, 2),
            "levels": meter.summary(), "measurement_id": measurement_id,
        })
