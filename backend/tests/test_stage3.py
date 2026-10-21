"""Етап 3: Excel експорт и сертификати."""

import io
from datetime import UTC, datetime, timedelta

import pytest
from openpyxl import load_workbook

from app.database import SessionLocal
from app.models import Measurement, MeasurementFrame
from app.reports import norms
from tests.test_stage2 import DEVICE, _device, _record


def test_period_classification():
    # 10.07 е лятно време (UTC+3): 04:30 UTC = 07:30 местно -> ден.
    assert norms.period_of(datetime(2026, 7, 10, 4, 30)) == "day"
    assert norms.period_of(datetime(2026, 7, 10, 16, 30)) == "evening"  # 19:30
    assert norms.period_of(datetime(2026, 7, 10, 21, 0)) == "night"  # 00:00
    assert norms.period_of(datetime(2026, 1, 10, 4, 30)) == "night"  # 06:30 зимно време


def _fake_measurement(db, user_id, device_id, start_utc, levels_by_minute):
    """Измерване с готови 1-секундни нива (без микрофон), за да се тестват периодите."""
    m = Measurement(
        user_id=user_id, device_id=device_id, started_at=start_utc, sample_rate=48000,
        f_min_hz=20, f_max_hz=20000, band_mode="off", indicators=["LAF", "LAS", "LAeq", "LCF", "LZSmax"],
        device_info=DEVICE | {"calibration_offset_db": None, "calibration_id": None, "calibration_date": None},
        summary={"LAeq": 50.0, "LAF": 50.0}, location="т. 1", source="Автомобилен трафик",
        zone_code="3", norm_day=60, norm_evening=55, norm_night=50,
    )
    db.add(m)
    db.flush()
    t = 0
    for level in levels_by_minute:
        for _ in range(60):
            db.add(MeasurementFrame(
                measurement_id=m.id, ts=start_utc + timedelta(seconds=t), t=t + 1,
                leq_a=level, leq_c=level, leq_z=level, levels={"LAeq": level, "LAF": level},
            ))
            t += 1
    m.duration_s = t
    m.ended_at = start_utc + timedelta(seconds=t)
    db.commit()
    return m.id


def _user_id(client, headers):
    return client.get("/api/auth/me", headers=headers).json()["id"]


def test_update_measurement_zone(client, auth_headers):
    headers, token = auth_headers
    device_id = _device(client, headers)
    mid = _record(client, token, device_id, 1.2, record=True)["measurement_id"]
    r = client.patch(f"/api/measurements/{mid}", json={"location": "т. 3", "source": "Автомобилен трафик",
                                                        "zone_code": "3"}, headers=headers).json()
    assert (r["norm_day"], r["norm_evening"], r["norm_night"]) == (60, 55, 50)
    r = client.patch(f"/api/measurements/{mid}", json={"zone_code": "custom", "norm_night": 47}, headers=headers).json()
    assert r["norm_night"] == 47 and r["norm_day"] == 60 and r["location"] == "т. 3"
    assert len(client.get("/api/norms/zones").json()) >= 6


def test_excel_and_certificate(client, auth_headers):
    headers, _ = auth_headers
    device_id = _device(client, headers)
    uid = _user_id(client, headers)
    now = datetime.now(UTC).replace(tzinfo=None, microsecond=0)
    # Намираме началото на днешния местен 18:58 в UTC - измерването минава от ден във вечер.
    local_now = norms.to_local(now)
    start_local = local_now.replace(hour=18, minute=58, second=0)
    if start_local > local_now:
        start_local -= timedelta(days=1)
    start_utc = start_local.astimezone(norms.ZoneInfo("UTC")).replace(tzinfo=None)
    with SessionLocal() as db:
        # 2 мин. ден (58 dB) + 2 мин. вечер (57 dB > норма 55)
        mid = _fake_measurement(db, uid, device_id, start_utc, [58, 58, 57, 57])

    # Excel за едно измерване
    r = client.get(f"/api/measurements/{mid}/xlsx", headers=headers)
    assert r.status_code == 200
    wb = load_workbook(io.BytesIO(r.content))
    rows = list(wb["Измервания"].iter_rows(min_row=4, values_only=True))
    assert len(rows) == 2
    by_period = {row[6]: row for row in rows}
    assert by_period["Ден"][7] == pytest.approx(58.0) and by_period["Ден"][8] == 60 and by_period["Ден"][9] == "Да"
    assert by_period["Вечер"][7] == pytest.approx(57.0) and by_period["Вечер"][8] == 55 and by_period["Вечер"][9] == "Не"
    assert "2182175" in by_period["Ден"][5]
    data = list(wb["Данни по секунди"].iter_rows(min_row=2, values_only=True))
    assert len(data) == 240 and data[0][-1] == "Да" and data[-1][-1] == "Не"
    assert wb["Устройства"]["D2"].value == "2182175"

    # Excel за период
    r = client.get("/api/history/xlsx", headers=headers)
    assert r.status_code == 200 and r.content[:2] == b"PK"

    # Сертификат
    client.put("/api/settings/organization", json={
        "org_name": "Лаборатория за акустика", "org_address": "гр. София", "org_accreditation": "Рег. № 1",
    }, headers=headers)
    r = client.post("/api/certificates", json={"measurement_ids": [mid], "remarks": "Тест"}, headers=headers)
    assert r.status_code == 201, r.text
    cert = r.json()
    assert cert["number"].endswith("-0001")
    row = cert["data"]["rows"][0]
    assert row["values"]["day"]["ok"] is True and row["values"]["evening"]["ok"] is False
    assert "превишение" in cert["data"]["conclusion"]
    assert "т. 3" in cert["data"]["normative"][0]
    assert any("2182175" in e for e in cert["data"]["equipment"])

    pdf = client.get(f"/api/certificates/{cert['id']}/pdf", headers=headers)
    assert pdf.status_code == 200 and pdf.content[:4] == b"%PDF"

    second = client.post("/api/certificates", json={"measurement_ids": [mid]}, headers=headers).json()
    assert second["number"].endswith("-0002")
    assert [c["number"] for c in client.get("/api/certificates", headers=headers).json()] == [
        second["number"], cert["number"]]
