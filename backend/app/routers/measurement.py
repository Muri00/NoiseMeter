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
from pydantic import BaseModel, Field, ValidationError, model_validator

from app.audio import indicators as indicator_codes
from app.audio.meter import LevelMeter, MeterConfig
from app.audio.source import AudioSourceError, audio_blocks, microphone_lock
from app.config import settings
from app.database import SessionLocal
from app.deps import user_from_token
from app.models import Device, UserSettings
from app.recording import Recorder
from app.schemas import ABS_F_MAX_HZ, ABS_F_MIN_HZ, BandMode

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

    @model_validator(mode="after")
    def check_range(self):
        if not (ABS_F_MIN_HZ <= self.f_min < self.f_max <= ABS_F_MAX_HZ):
            raise ValueError(
                f"Интервалът трябва да е в границите {ABS_F_MIN_HZ:g} - {ABS_F_MAX_HZ:g} Hz "
                "и минималната честота да е по-малка от максималната"
            )
        return self


async def _send_error(ws: WebSocket, message: str) -> None:
    await ws.send_json({"type": "error", "message": message})


@router.websocket("/ws/measure")
async def measure(ws: WebSocket):
    await ws.accept()
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
    with SessionLocal() as db:
        user = user_from_token(db, msg.get("token"))
        return user.id if user else None


async def _run_session(ws: WebSocket, user_id: int, msg: dict) -> None:
    try:
        req = StartRequest.model_validate(msg)
    except ValidationError as e:
        await _send_error(ws, "; ".join(err["msg"] for err in e.errors()))
        return

    with SessionLocal() as db:
        device = db.get(Device, req.device_id)
        if device is None or device.user_id != user_id:
            await _send_error(ws, "Устройството не е намерено")
            return
        dev_min, dev_max, offset_db = device.freq_min_hz, device.freq_max_hz, device.level_offset_db
        user_settings = db.get(UserSettings, user_id)
        indicators = user_settings.indicators if user_settings else indicator_codes.DEFAULT_INDICATORS

    # Изискване 3: стойностите не могат да излизат от работната честотна лента на устройството.
    if req.f_min < dev_min or req.f_max > dev_max:
        await _send_error(
            ws,
            f"Измервателният интервал трябва да е в работната лента на устройството "
            f"({dev_min:g} - {dev_max:g} Hz)",
        )
        return

    if microphone_lock.locked():
        await _send_error(ws, "Микрофонът в момента се използва от друго измерване или калибровка")
        return

    async with microphone_lock:
        fs = settings.sample_rate
        # Над честотата на Найкуист не може да се измерва, независимо от избрания интервал.
        f_max = min(req.f_max, fs / 2)
        meter = LevelMeter(MeterConfig(fs, offset_db, req.f_min, f_max, req.band_mode))
        recorder = None
        if req.record:
            recorder = Recorder(
                user_id=user_id, device_id=req.device_id, meter=meter,
                indicators=indicators, name=req.name, save_wav=req.save_wav,
            )
        measurement_id = recorder.measurement_id if recorder else None

        await ws.send_json({
            "type": "started", "sample_rate": fs, "f_min": req.f_min, "f_max": f_max,
            "band_mode": req.band_mode, "measurement_id": measurement_id,
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
