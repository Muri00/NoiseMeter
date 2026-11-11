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


def test_place_and_norms(client, auth_headers, admin_headers):
    headers, token = auth_headers
    device_id = _device(client, headers)
    # Мястото, зоната и периодът се задават при самото измерване.
    mid = _record(client, token, device_id, 1.2, record=True, location="т. 3", source="Автомобилен трафик",
                  zone_code="3", period="night")["measurement_id"]
    m = client.get(f"/api/measurements/{mid}", headers=headers).json()
    assert (m["norm_day"], m["norm_evening"], m["norm_night"], m["period"]) == (60, 55, 50, "night")
    assert m["location"] == "т. 3" and m["standard_code"] == "IEC61672-1:2013" and m["out_of_band"] is False

    # Обикновеният потребител не може да ги променя след това, администраторът - може.
    assert client.patch(f"/api/measurements/{mid}", json={"zone_code": "1"}, headers=headers).status_code == 403
    r = client.patch(f"/api/measurements/{mid}", json={"zone_code": "1", "period": "day"}, headers=admin_headers).json()
    assert (r["norm_day"], r["norm_night"], r["period"]) == (55, 45, "day")
    r = client.patch(f"/api/measurements/{mid}", json={"norm_night": 47}, headers=admin_headers).json()
    assert r["norm_night"] == 47 and r["norm_day"] == 55 and r["location"] == "т. 3"
    assert len(client.get("/api/norms/zones", headers=headers).json()) >= 8


def test_zone_admin(client, auth_headers, admin_headers):
    headers, _ = auth_headers
    zone = {"code": "П9", "name": "Тестово помещение", "category": "indoor", "day": 35, "evening": 35, "night": 30}
    assert client.post("/api/admin/zones", json=zone, headers=headers).status_code == 403
    r = client.post("/api/admin/zones", json=zone, headers=admin_headers)
    assert r.status_code == 201
    zid = r.json()["id"]
    assert client.post("/api/admin/zones", json=zone, headers=admin_headers).status_code == 409
    r = client.put(f"/api/admin/zones/{zid}", json=zone | {"night": 25}, headers=admin_headers)
    assert r.json()["night"] == 25
    assert client.delete(f"/api/admin/zones/{zid}", headers=admin_headers).status_code == 204


def test_standards(client, auth_headers, admin_headers):
    headers, token = auth_headers
    standards = client.get("/api/standards", headers=headers).json()
    codes = [s["code"] for s in standards]
    assert "IEC61672-1:2013" in codes and "ANSI-S1.4-1983" in codes
    assert sum(s["is_default"] for s in standards) == 1

    ansi = next(s for s in standards if s["code"] == "ANSI-S1.4-1983")
    assert client.put(f"/api/admin/standards/{ansi['id']}", json=ansi, headers=headers).status_code == 403
    bad = ansi | {"params": ansi["params"] | {"poles": [12200, 737.9, 107.7, 20.6]}}
    assert client.put(f"/api/admin/standards/{ansi['id']}", json=bad, headers=admin_headers).status_code == 422

    device_id = _device(client, headers)
    mid = _record(client, token, device_id, 1.2, record=True, standard_code="ANSI-S1.4-1983")["measurement_id"]
    m = client.get(f"/api/measurements/{mid}", headers=headers).json()
    assert m["standard_name"].startswith("ANSI") and "Lpmax" in m["summary"] and "Lp" in m["summary"]


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
    r = client.post("/api/certificates", json={"measurement_ids": [mid], "title": "Обект", "remarks": "Тест"}, headers=headers)
    assert r.status_code == 201, r.text
    cert = r.json()
    assert cert["number"].endswith("-0001")
    row = cert["data"]["rows"][0]
    assert row["values"]["day"]["ok"] is True and row["values"]["evening"]["ok"] is False
    assert "превишение" in cert["data"]["conclusion"]
    assert "т. 3" in cert["data"]["normative"][0]
    assert any("2182175" in e for e in cert["data"]["equipment"])
    # Методите по подразбиране са стандартите за метода (ISO 1996), а стандартът на шумомера,
    # по който е изчислено измерването, е в техническите средства (стар запис - по подразбиране).
    assert cert["data"]["methods"] == ["БДС ISO 1996-1:2016", "БДС ISO 1996-2:2018"]
    assert any("БДС EN IEC 61672-1:2013" in e for e in cert["data"]["equipment"])

    pdf = client.get(f"/api/certificates/{cert['id']}/pdf", headers=headers)
    assert pdf.status_code == 200 and pdf.content[:4] == b"%PDF"

    # Въведените методи се използват както са въведени.
    second = client.post("/api/certificates", json={
        "measurement_ids": [mid], "title": "Обект", "methods": ["БДС EN ISO 16032:2005"],
    }, headers=headers).json()
    assert second["data"]["methods"] == ["БДС EN ISO 16032:2005"]
    assert second["number"].endswith("-0002")
    assert [c["number"] for c in client.get("/api/certificates", headers=headers).json()] == [
        second["number"], cert["number"]]


def test_selected_period(client, auth_headers):
    """При избран период цялото измерване се отнася към него, независимо от часа."""
    headers, _ = auth_headers
    device_id = _device(client, headers)
    uid = _user_id(client, headers)
    start = datetime.now(UTC).replace(tzinfo=None, microsecond=0) - timedelta(hours=1)
    with SessionLocal() as db:
        mid = _fake_measurement(db, uid, device_id, start, [52, 52])
        m = db.get(Measurement, mid)
        m.period = "night"
        m.out_of_band = True
        db.commit()
    wb = load_workbook(io.BytesIO(client.get(f"/api/measurements/{mid}/xlsx", headers=headers).content))
    rows = [r for r in wb["Измервания"].iter_rows(min_row=4, values_only=True) if r[0]]
    assert len(rows) == 1 and rows[0][6] == "Нощ" and rows[0][8] == 50 and rows[0][9] == "Не"
    cert = client.post("/api/certificates", json={"measurement_ids": [mid], "title": "Обект"}, headers=headers).json()
    assert list(cert["data"]["rows"][0]["values"]) == ["night"]
    assert "извън работната лента" in cert["data"]["remarks"]


def test_indoor_zones_seeded(client, auth_headers):
    headers, _ = auth_headers
    zones = {z["code"]: z for z in client.get("/api/norms/zones", headers=headers).json()}
    # Наредба № 6, Приложение 2, табл. 1: жилищни стаи 35 / 35 / 30 dB(A).
    assert zones["П2"]["category"] == "indoor"
    assert (zones["П2"]["day"], zones["П2"]["evening"], zones["П2"]["night"]) == (35, 35, 30)


def test_points_in_room(client, auth_headers):
    """Серия от точки в едно закрито помещение: броят на точките се избира на място."""
    headers, token = auth_headers
    device_id = _device(client, headers)
    place = {"record": True, "location": "Зала 2", "place_type": "indoor", "zone_code": "П4",
             "point_count": 3, "series_id": "test-series-1"}
    ids = [_record(client, token, device_id, 1.2, point_no=k, **place)["measurement_id"] for k in (1, 2, 3)]

    m = client.get(f"/api/measurements/{ids[1]}", headers=headers).json()
    assert (m["place_type"], m["point_no"], m["point_count"]) == ("indoor", 2, 3)
    assert [p["point_no"] for p in m["series_points"]] == [1, 2, 3]
    laeqs = [p["laeq"] for p in m["series_points"]]
    assert m["series_laeq"] == norms.energy_mean(laeqs)

    with SessionLocal() as db:
        assert norms.place_label(db.get(Measurement, ids[2])) == "Зала 2, т. 3"

    # Точка с номер, по-голям от броя на точките, се отказва.
    with client.websocket_connect("/ws/measure") as ws:
        ws.send_json({"action": "auth", "token": token})
        ws.receive_json()
        ws.send_json({"action": "start", "device_id": device_id, **place, "point_no": 4})
        assert ws.receive_json()["type"] == "error"
