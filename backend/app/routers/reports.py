"""Отчети: Excel експорт (изискване 7) и сертификати от измерване (изискване 8)."""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import extract, func, select

from app.deps import AdminUser, CurrentUser, DbSession
from app.models import Calibration, Certificate, Measurement, MeasurementFrame, Standard, Zone
from app.reports import certificate as cert_pdf
from app.reports import excel, norms
from app.routers.measurements import _get_own, resolve_period, visible_measurements
from app.routers.user_settings import get_or_create_settings
from app.schemas import (
    CertificateIn, CertificateOut, MeasurementOut, MeasurementUpdate, OrganizationSettings,
)

router = APIRouter(tags=["Отчети"])

XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _attachment(content: bytes, media_type: str, filename: str) -> Response:
    return Response(content, media_type=media_type,
                    headers={"Content-Disposition": f'attachment; filename="{filename}"'})


def _frames(db, measurement_id: int):
    return db.scalars(
        select(MeasurementFrame).where(MeasurementFrame.measurement_id == measurement_id).order_by(MeasurementFrame.t)
    ).all()


# ---------- Място и норми (само администратор) ----------

@router.patch("/api/measurements/{measurement_id}", response_model=MeasurementOut)
def update_measurement(measurement_id: int, data: MeasurementUpdate, admin: AdminUser, db: DbSession):
    """Промяна на мястото, зоната и периода на записано измерване. Нормите се вземат от
    зоната; администраторът може да ги промени и поотделно."""
    m = _get_own(db, admin, measurement_id)
    values = data.model_dump(exclude_unset=True)
    if "zone_code" in values:
        norms.apply_zone(db, m, values.pop("zone_code"))
    for key, value in values.items():
        setattr(m, key, (value.strip() or None) if isinstance(value, str) else value)
    db.commit()
    return m


# ---------- Excel ----------

@router.get("/api/measurements/{measurement_id}/xlsx")
def measurement_xlsx(measurement_id: int, user: CurrentUser, db: DbSession):
    m = _get_own(db, user, measurement_id)
    content = excel.build_workbook([(m, _frames(db, m.id))], m.indicators, f"Измерване № {m.id} - {m.name or ''}")
    return _attachment(content, XLSX, f"measurement_{m.id}.xlsx")


@router.get("/api/history/xlsx")
def history_xlsx(
    user: CurrentUser,
    db: DbSession,
    period_from: Annotated[datetime | None, Query(alias="from")] = None,
    period_to: Annotated[datetime | None, Query(alias="to")] = None,
):
    frm, to = resolve_period(period_from, period_to)
    measurements = db.scalars(
        select(Measurement)
        .where(visible_measurements(user), Measurement.started_at < to)
        .where(func.coalesce(Measurement.ended_at, Measurement.started_at) >= frm)
        .order_by(Measurement.started_at)
    ).all()
    items = [(m, [f for f in _frames(db, m.id) if frm <= f.ts < to]) for m in measurements]
    settings = get_or_create_settings(db, user)
    title = (f"Измервания за периода {norms.to_local(frm):%d.%m.%Y %H:%M} - "
             f"{norms.to_local(to):%d.%m.%Y %H:%M}")
    content = excel.build_workbook(items, settings.indicators, title)
    return _attachment(content, XLSX, f"measurements_{norms.to_local(frm):%Y%m%d}_{norms.to_local(to):%Y%m%d}.xlsx")


# ---------- Организация ----------

@router.get("/api/settings/organization", response_model=OrganizationSettings)
def get_organization(user: CurrentUser, db: DbSession):
    return get_or_create_settings(db, user)


@router.put("/api/settings/organization", response_model=OrganizationSettings)
def update_organization(data: OrganizationSettings, user: CurrentUser, db: DbSession):
    s = get_or_create_settings(db, user)
    for key, value in data.model_dump().items():
        setattr(s, key, (value or "").strip() or None)
    db.commit()
    return s


# ---------- Сертификати ----------

def _equipment(db, measurements) -> list[str]:
    """Технически средства: шумомерите и калибраторите от последната им калибровка."""
    lines, seen_devices, seen_cals = [], set(), set()
    for m in measurements:
        d = m.device_info
        key = (d["brand"], d["model"], d["serial_number"])
        if key not in seen_devices:
            seen_devices.add(key)
            cal = d.get("calibration_offset_db")
            date = d.get("calibration_date")
            text = (f"Шумомер (измервателен микрофон): {d['brand']} {d['model']}, сериен № {d['serial_number']}; "
                    f"чувствителност {d['sensitivity_dbfs']:g} dBFS при 94 dB SPL; работна лента "
                    f"{d['freq_min_hz']:g}-{d['freq_max_hz']:g} Hz")
            if cal is not None:
                text += f"; калибровъчна корекция {cal:+.2f} dB"
            if date:
                cal_dt = datetime.fromisoformat(date.rstrip("Z"))
                text += f", калибриран на {norms.to_local(cal_dt):%d.%m.%Y}"
            lines.append(text)
        cal_id = d.get("calibration_id")
        if cal_id and cal_id not in seen_cals:
            seen_cals.add(cal_id)
            c = db.get(Calibration, cal_id)
            if c and (c.calibrator_brand or c.calibrator_model):
                text = f"Звуков калибратор: {' '.join(x for x in (c.calibrator_brand, c.calibrator_model) if x)}"
                if c.calibrator_serial:
                    text += f", сериен № {c.calibrator_serial}"
                if c.calibrator_certificate:
                    text += f", сертификат за калибриране № {c.calibrator_certificate}"
                if c.reference_level_db:
                    text += f"; {c.reference_level_db:g} dB"
                    if c.reference_freq_hz:
                        text += f" при {c.reference_freq_hz:g} Hz"
                lines.append(text)
    # Стандартът на шумомера - същият, по който са изчислени измерванията.
    used = _measurement_standards(db, measurements)
    lines.append(f"Софтуер: METRAVA - честотни филтри A, C, Z и времеви F, S, I по {', '.join(used)}")
    return lines


def _measurement_standards(db, measurements) -> list[str]:
    """Стандартите, по които са изчислени измерванията (в реда на първата поява).
    За стари записи без стандарт се използва стандартът по подразбиране."""
    default = db.scalar(select(Standard.name).where(Standard.is_default.is_(True))) or "IEC 61672-1"
    return list(dict.fromkeys(m.standard_name or default for m in measurements))


def _next_number(db, user_id: int, year: int) -> str:
    count = db.scalar(
        select(func.count(Certificate.id))
        .where(Certificate.user_id == user_id, extract("year", Certificate.issued_at) == year)
    )
    return f"{year}-{count + 1:04d}"


@router.post("/api/certificates", response_model=CertificateOut, status_code=status.HTTP_201_CREATED)
def create_certificate(data: CertificateIn, user: CurrentUser, db: DbSession):
    measurements = [_get_own(db, user, mid) for mid in dict.fromkeys(data.measurement_ids)]
    if any(m.ended_at is None for m in measurements):
        raise HTTPException(status.HTTP_409_CONFLICT, "Някое от измерванията още не е приключило")
    measurements.sort(key=lambda m: m.started_at)

    rows = []
    for i, m in enumerate(measurements, 1):
        per_period = norms.period_levels(_frames(db, m.id), m.period)
        values = {}
        for period, p in per_period.items():
            norm = norms.norm_for(m, period)
            values[period] = {"value": p["laeq"], "norm": norm, "ok": norms.within_limit(p["laeq"], norm)}
        start = norms.to_local(m.started_at)
        end = norms.to_local(m.ended_at)
        time = f"{start:%d.%m.%Y %H:%M}-{end:%H:%M}" if start.date() == end.date() \
            else f"{start:%d.%m.%Y %H:%M} - {end:%d.%m.%Y %H:%M}"
        rows.append({
            "no": i, "measurement_id": m.id, "point": norms.place_label(m) or f"т. {i}",
            "source": m.source, "time": time, "values": values,
        })

    normative = data.normative
    if not normative:
        zones = db.scalars(select(Zone).where(Zone.code.in_({m.zone_code for m in measurements if m.zone_code}))).all()
        outdoor = sorted((z.code for z in zones if z.category == "outdoor"), key=lambda c: (len(c), c))
        normative = ["Наредба № 6/2006 за показателите за шум в околната среда (ДВ бр. 58/2006), Приложение 2"
                     + (f", табл. 2, т. {', '.join(outdoor)}" if outdoor else "")]
        normative += [f"Наредба № 6/2006 - {z.name}" for z in zones if z.category == "indoor"]

    # Автоматични забележки за измервания извън работната лента на микрофона.
    out_of_band = [r["point"] for r, m in zip(rows, measurements) if m.out_of_band]
    remarks = data.remarks or ""
    if out_of_band:
        note = ("Измервателният интервал в " + ", ".join(out_of_band)
                + " излиза извън работната лента на микрофона - резултатите са ориентировъчни.")
        remarks = f"{remarks}\n{note}".strip()

    org = get_or_create_settings(db, user)
    now = datetime.now(norms.local_tz())
    number = _next_number(db, user.id, now.year)
    snapshot = {
        "number": number,
        "issued_date": f"{now:%d.%m.%Y}",
        "title": data.title,
        "organization": {"name": org.org_name, "address": org.org_address, "accreditation": org.org_accreditation},
        "methods": data.methods,
        "normative": normative,
        "rows": rows,
        "conclusion": cert_pdf.conclusion(rows),
        "remarks": remarks or None,
        "equipment": _equipment(db, measurements),
        "performed_by": data.performed_by or [
            " ".join(x for x in (user.first_name, user.last_name) if x) or user.username
        ],
    }
    cert = Certificate(user_id=user.id, number=number, data=snapshot)
    db.add(cert)
    db.commit()
    return cert


@router.get("/api/certificates", response_model=list[CertificateOut])
def list_certificates(user: CurrentUser, db: DbSession):
    query = select(Certificate).order_by(Certificate.issued_at.desc())
    if not user.is_admin:
        query = query.where(Certificate.user_id == user.id)
    return db.scalars(query).all()


@router.get("/api/certificates/{certificate_id}/pdf")
def certificate_pdf(certificate_id: int, user: CurrentUser, db: DbSession):
    cert = db.get(Certificate, certificate_id)
    if cert is None or (cert.user_id != user.id and not user.is_admin):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Сертификатът не е намерен")
    return _attachment(cert_pdf.render_pdf(cert.data), "application/pdf", f"certificate_{cert.number}.pdf")
