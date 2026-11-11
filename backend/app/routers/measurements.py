"""История на измерванията (изискване 5) и изтегляне на записаните данни (изискване 4)."""

import csv
import io
import math
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Annotated

import numpy as np
from scipy.io import wavfile
from fastapi import APIRouter, HTTPException, Query, Response, status
from fastapi.responses import FileResponse
from sqlalchemy import func, select, true

from app.audio import indicators as indicator_codes
from app.config import settings
from app.deps import AdminUser, CurrentUser, DbSession
from app.models import Measurement, MeasurementFrame, utcnow
from app.reports import norms
from app.schemas import (
    BandsOut, HistoryOut, MeasurementDetailOut, MeasurementOut, SeriesOut, SeriesPointOut, TimelinePoint,
)

router = APIRouter(tags=["История"])


# ---------- Помощни функции ----------

def _energy_mean_db(levels) -> float | None:
    """Енергийно средно на нива в dB: 10·log10(средно(10^(L/10)))."""
    arr = np.asarray(levels, dtype=float)
    if arr.size == 0:
        return None
    return round(float(10 * np.log10(np.mean(10 ** (arr / 10)))), 2)


def _to_naive_utc(d: datetime) -> datetime:
    return d.astimezone(UTC).replace(tzinfo=None) if d.tzinfo else d


def resolve_period(period_from: datetime | None, period_to: datetime | None) -> tuple[datetime, datetime]:
    """Проверява периода на справката. По подразбиране - последните 24 часа."""
    now = utcnow()
    to = _to_naive_utc(period_to) if period_to else now
    frm = _to_naive_utc(period_from) if period_from else to - timedelta(hours=24)
    if frm >= to:
        raise HTTPException(422, "Началото на периода трябва да е преди края му")
    # Малък толеранс, за да мине "точно преди 3 месеца", изпратено от приложението.
    oldest = now - timedelta(days=settings.history_max_days, minutes=5)
    if frm < oldest:
        raise HTTPException(
            422,
            f"Справките са за максимум {settings.history_max_days} дни назад",
        )
    return frm, to


def _bucket_seconds(span: timedelta) -> int:
    """Стъпка на графиката според дължината на периода (до ~300-700 точки)."""
    hours = span.total_seconds() / 3600
    if hours <= 1:
        return 10
    if hours <= 24:
        return 120
    if hours <= 24 * 7:
        return 900
    if hours <= 24 * 31:
        return 3600
    return 3 * 3600


def _get_own(db, user, measurement_id: int) -> Measurement:
    """Измерването, ако потребителят има достъп до него: собственикът или администратор."""
    m = db.get(Measurement, measurement_id)
    if m is None or (m.user_id != user.id and not user.is_admin):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Измерването не е намерено")
    return m


def visible_measurements(user):
    """Условие за измерванията, които потребителят вижда: администраторът - всички."""
    return true() if user.is_admin else (Measurement.user_id == user.id)


# ---------- Справка за период ----------

@router.get("/api/history", response_model=HistoryOut)
def history(
    user: CurrentUser,
    db: DbSession,
    period_from: Annotated[datetime | None, Query(alias="from")] = None,
    period_to: Annotated[datetime | None, Query(alias="to")] = None,
):
    """Справка за период: всички измервания, общо LAeq и графика във времето."""
    frm, to = resolve_period(period_from, period_to)

    measurements = db.scalars(
        select(Measurement)
        .where(visible_measurements(user), Measurement.started_at < to)
        .where(func.coalesce(Measurement.ended_at, Measurement.started_at) >= frm)
        .order_by(Measurement.started_at.desc())
    ).all()

    rows = db.execute(
        select(MeasurementFrame.ts, MeasurementFrame.leq_a, MeasurementFrame.leq_c, MeasurementFrame.leq_z)
        .join(Measurement)
        .where(visible_measurements(user), MeasurementFrame.ts >= frm, MeasurementFrame.ts < to)
        .order_by(MeasurementFrame.ts)
        .execution_options(yield_per=5000)
    )

    bucket_s = _bucket_seconds(to - frm)
    buckets: dict[int, list[tuple[float, float, float]]] = {}
    all_a, all_c, all_z = [], [], []
    epoch = datetime(1970, 1, 1)
    for ts, a, c, z in rows:
        key = int((ts - epoch).total_seconds() // bucket_s)
        buckets.setdefault(key, []).append((a, c, z))
        all_a.append(a)
        all_c.append(c)
        all_z.append(z)

    timeline = []
    for key, values in sorted(buckets.items()):
        a, c, z = zip(*values)
        timeline.append(TimelinePoint(
            ts=epoch + timedelta(seconds=key * bucket_s),
            LAeq=_energy_mean_db(a), LCeq=_energy_mean_db(c), LZeq=_energy_mean_db(z),
            LAeq_max=max(a),
        ))

    return HistoryOut(
        period_from=frm,
        period_to=to,
        count=len(measurements),
        total_duration_s=round(sum(m.duration_s for m in measurements), 1),
        LAeq=_energy_mean_db(all_a),
        LCeq=_energy_mean_db(all_c),
        LZeq=_energy_mean_db(all_z),
        LAeq_1s_max=max(all_a) if all_a else None,
        LAeq_1s_min=min(all_a) if all_a else None,
        bucket_s=bucket_s,
        timeline=timeline,
        measurements=[MeasurementOut.model_validate(m) for m in measurements],
    )


# ---------- Едно измерване ----------

@router.get("/api/measurements/{measurement_id}", response_model=MeasurementDetailOut)
def get_measurement(measurement_id: int, user: CurrentUser, db: DbSession):
    m = _get_own(db, user, measurement_id)
    frames = db.execute(
        select(MeasurementFrame.bands).where(MeasurementFrame.measurement_id == m.id)
    ).scalars().all()

    # Средният спектър за цялото измерване (енергийно осредняване по секундите).
    average_bands = None
    band_frames = [b for b in frames if b]
    if band_frames:
        levels = np.array([b["levels"] for b in band_frames])
        average_bands = BandsOut(
            mode=m.band_mode,
            centers=band_frames[0]["centers"],
            levels=[round(float(v), 2) for v in 10 * np.log10(np.mean(10 ** (levels / 10), axis=0))],
        )

    # Точките от същата серия (едно помещение) и енергийното средно LAeq от тях.
    series_points, series_laeq = [], None
    if m.series_id:
        siblings = db.scalars(
            select(Measurement)
            .where(Measurement.series_id == m.series_id, Measurement.user_id == m.user_id)
            .order_by(Measurement.point_no, Measurement.started_at)
        ).all()
        series_points = [
            SeriesPointOut(id=s.id, point_no=s.point_no, laeq=(s.summary or {}).get("LAeq")) for s in siblings
        ]
        series_laeq = norms.energy_mean(p.laeq for p in series_points if p.laeq is not None)

    base = MeasurementOut.model_validate(m).model_dump()
    return MeasurementDetailOut(**base, frame_count=len(frames), average_bands=average_bands,
                                series_points=series_points, series_laeq=series_laeq)


@router.get("/api/measurements/{measurement_id}/series", response_model=SeriesOut)
def get_series(
    measurement_id: int,
    user: CurrentUser,
    db: DbSession,
    codes: Annotated[list[str], Query()] = ["LAeq"],
    max_points: Annotated[int, Query(ge=10, le=5000)] = 1500,
):
    """Стойностите на избрани показатели по секунди. При дълъг запис точките се
    обединяват на групи: max за max, min за min и енергийно средно за останалите."""
    m = _get_own(db, user, measurement_id)
    bad = [c for c in codes if not indicator_codes.is_valid(c)]
    if bad:
        raise HTTPException(422, f"Невалидни показатели: {', '.join(bad)}")

    rows = db.execute(
        select(MeasurementFrame.t, MeasurementFrame.levels)
        .where(MeasurementFrame.measurement_id == m.id)
        .order_by(MeasurementFrame.t)
    ).all()

    group = max(1, math.ceil(len(rows) / max_points))
    t_out: list[float] = []
    series: dict[str, list[float]] = {c: [] for c in codes}
    for i in range(0, len(rows), group):
        chunk = rows[i:i + group]
        t_out.append(chunk[-1][0])
        for c in codes:
            vals = [r[1].get(c, float("nan")) for r in chunk]
            if c.endswith("max"):
                v = max(vals)
            elif c.endswith("min"):
                v = min(vals)
            else:
                v = _energy_mean_db(vals)
            series[c].append(v)
    return SeriesOut(t=t_out, series=series)


@router.get("/api/measurements/{measurement_id}/csv")
def download_csv(measurement_id: int, user: CurrentUser, db: DbSession):
    """Записаните данни като CSV, с данните за входното устройство в началото на файла."""
    m = _get_own(db, user, measurement_id)
    frames = db.scalars(
        select(MeasurementFrame).where(MeasurementFrame.measurement_id == m.id).order_by(MeasurementFrame.t)
    ).all()

    d = m.device_info
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    for row in [
        ["# Измерване", m.id],
        ["# Наименование", m.name or ""],
        ["# Начало (UTC)", f"{m.started_at:%Y-%m-%d %H:%M:%S}"],
        ["# Продължителност (s)", m.duration_s],
        ["# Устройство", f"{d['brand']} {d['model']}"],
        ["# Сериен номер", d["serial_number"]],
        ["# Чувствителност (dBFS при 94 dB SPL)", d["sensitivity_dbfs"]],
        ["# Работна лента (Hz)", f"{d['freq_min_hz']:g}-{d['freq_max_hz']:g}"],
        ["# Калибровъчна корекция (dB)", d.get("calibration_offset_db") or 0],
        ["# Дата на калибровка", d.get("calibration_date") or "няма"],
        ["# Измервателен интервал (Hz)", f"{m.f_min_hz:g}-{m.f_max_hz:g}"],
        ["# Честота на дискретизация (Hz)", m.sample_rate],
        ["# Октавни ленти", m.band_mode],
    ]:
        w.writerow(row)
    w.writerow([])

    codes = indicator_codes.all_indicators()
    centers = next((f.bands["centers"] for f in frames if f.bands), [])
    w.writerow(
        ["Време (UTC)", "t (s)"]
        + [indicator_codes.display_name(c) for c in codes]
        + [f"{m.band_mode} окт. {c:g} Hz" for c in centers]
    )
    for f in frames:
        band_levels = f.bands["levels"] if f.bands else [""] * len(centers)
        w.writerow(
            [f"{f.ts:%Y-%m-%d %H:%M:%S.%f}"[:-3], f.t]
            + [f.levels.get(c, "") for c in codes]
            + band_levels
        )

    filename = f"measurement_{m.id}_{m.started_at:%Y%m%d_%H%M%S}.csv"
    # BOM, за да разпознае Excel кирилицата.
    return Response(
        content="﻿" + out.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/api/measurements/{measurement_id}/wav")
def download_wav(measurement_id: int, user: CurrentUser, db: DbSession):
    m = _get_own(db, user, measurement_id)
    if not m.wav_path or not Path(m.wav_path).exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Няма WAV запис за това измерване")
    return FileResponse(m.wav_path, media_type="audio/wav", filename=Path(m.wav_path).name)


@router.get("/api/measurements/{measurement_id}/audio")
def play_audio(measurement_id: int, user: CurrentUser, db: DbSession):
    """Записът за слушане в приложението: 16-битов PCM WAV (оригиналът е 32-битов float,
    който не всички телефони възпроизвеждат). Копието се прави веднъж и се пази до оригинала."""
    m = _get_own(db, user, measurement_id)
    if not m.wav_path or not Path(m.wav_path).exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Няма WAV запис за това измерване")
    original = Path(m.wav_path)
    playable = original.with_name(original.stem + "_play.wav")
    if not playable.exists() or playable.stat().st_mtime < original.stat().st_mtime:
        fs, data = wavfile.read(original)
        pcm = (np.clip(np.asarray(data, dtype=np.float64), -1.0, 1.0) * 32767).astype(np.int16)
        tmp = playable.with_suffix(".tmp")
        wavfile.write(tmp, fs, pcm)
        tmp.replace(playable)
    return FileResponse(playable, media_type="audio/wav", filename=playable.name)


@router.delete("/api/measurements/{measurement_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_measurement(measurement_id: int, user: AdminUser, db: DbSession):
    """Само администраторът може да трие записи от историята."""
    m = _get_own(db, user, measurement_id)
    wav = Path(m.wav_path) if m.wav_path else None
    db.delete(m)
    db.commit()
    if wav:
        wav.unlink(missing_ok=True)
        wav.with_name(wav.stem + "_play.wav").unlink(missing_ok=True)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
