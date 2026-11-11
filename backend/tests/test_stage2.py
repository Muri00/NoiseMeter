"""Етап 2: запис, история и калибровка."""

from datetime import UTC, datetime, timedelta
from pathlib import Path

import numpy as np
import pytest
from scipy.io import wavfile

from app.audio import calibration as cal_analysis
from app.audio.wavfile import WavWriter
from app.config import settings

FS = 48000
DEVICE = {
    "brand": "miniDSP", "model": "UMIK-1", "serial_number": "2182175",
    "sensitivity_dbfs": -18.0, "freq_min_hz": 20, "freq_max_hz": 20000,
}


def _device(client, headers) -> int:
    return client.post("/api/devices", json=DEVICE, headers=headers).json()["id"]


def _record(client, token, device_id, seconds=2.5, **options) -> dict:
    with client.websocket_connect("/ws/measure") as ws:
        ws.send_json({"action": "auth", "token": token})
        assert ws.receive_json()["type"] == "auth_ok"
        ws.send_json({"action": "start", "device_id": device_id, "band_mode": "1/3", **options})
        started = ws.receive_json()
        assert started["type"] == "started"
        while ws.receive_json()["t"] < seconds:
            pass
        ws.send_json({"action": "stop"})
        msg = ws.receive_json()
        while msg["type"] == "frame":
            msg = ws.receive_json()
        assert msg["type"] == "stopped"
        assert msg["measurement_id"] == started["measurement_id"]
        return msg


# ---------- WAV и анализ ----------

def test_wav_writer_roundtrip(tmp_path):
    path = tmp_path / "x.wav"
    x = (0.5 * np.sin(np.arange(FS) / 10)).astype(np.float32)
    w = WavWriter(path, FS, {"ICMT": "Устройство: miniDSP UMIK-1; S/N 2182175"})
    w.write(x[:1000])
    w.write(x[1000:])
    w.close()
    fs, data = wavfile.read(path)
    assert fs == FS and data.dtype == np.float32
    assert np.array_equal(data, x)
    assert "S/N 2182175".encode() in path.read_bytes()


def test_calibration_analysis():
    t = np.arange(5 * FS) / FS
    tone = np.sqrt(2) * 10 ** (-18 / 20) * np.sin(2 * np.pi * 1000 * t)
    r = cal_analysis.analyze(tone, FS, 1000, 94 + 18)
    assert r.level_db == pytest.approx(94.0, abs=0.05)
    assert r.freq_hz == pytest.approx(1000, abs=1)

    with pytest.raises(cal_analysis.CalibrationSignalError, match="тон"):
        cal_analysis.analyze(np.random.default_rng(1).standard_normal(5 * FS) * 0.01, FS, 1000, 112)
    with pytest.raises(cal_analysis.CalibrationSignalError, match="шум"):
        noise = np.random.default_rng(2).standard_normal(5 * FS) * 0.2
        cal_analysis.analyze(tone + noise, FS, 1000, 112)


# ---------- Запис и история ----------

def test_recording_and_history(client, auth_headers, admin_headers):
    headers, token = auth_headers
    device_id = _device(client, headers)

    # Без запис нищо не се пази.
    assert _record(client, token, device_id, 0.5)["measurement_id"] is None
    assert client.get("/api/history", headers=headers).json()["count"] == 0

    stopped = _record(client, token, device_id, record=True, save_wav=True, name="Офис")
    mid = stopped["measurement_id"]

    h = client.get("/api/history", headers=headers).json()
    assert h["count"] == 1 and h["measurements"][0]["name"] == "Офис"
    assert h["measurements"][0]["started_at"].endswith("Z")
    assert h["LAeq"] is not None and len(h["timeline"]) >= 1

    d = client.get(f"/api/measurements/{mid}", headers=headers).json()
    assert d["frame_count"] >= 2
    assert d["device_info"]["serial_number"] == "2182175"
    assert d["summary"]["LAeq"] == pytest.approx(stopped["levels"]["LAeq"], abs=0.01)
    assert d["average_bands"]["centers"][0] == 20
    assert d["has_wav"]

    s = client.get(f"/api/measurements/{mid}/series?codes=LAF&codes=LAFmax", headers=headers).json()
    assert len(s["t"]) == d["frame_count"] and set(s["series"]) == {"LAF", "LAFmax"}

    csv_text = client.get(f"/api/measurements/{mid}/csv", headers=headers).text
    assert "2182175" in csv_text and "LA,F,max" in csv_text and "1/3 окт. 1000 Hz" in csv_text

    wav = client.get(f"/api/measurements/{mid}/wav", headers=headers)
    assert wav.status_code == 200 and wav.content[:4] == b"RIFF"
    assert b"2182175" in wav.content[:2000]
    # Версия за слушане: 16-битов PCM (формат 1), с поддръжка на превъртане (Range).
    audio = client.get(f"/api/measurements/{mid}/audio", headers=headers)
    assert audio.status_code == 200 and audio.content[20:22] == b"\x01\x00" and audio.content[34:36] == b"\x10\x00"
    part = client.get(f"/api/measurements/{mid}/audio", headers=headers | {"Range": "bytes=0-99"})
    assert part.status_code == 206 and len(part.content) == 100
    wav_files = [p for p in Path(settings.recordings_dir).glob(f"measurement_{mid}_*.wav") if not p.stem.endswith("_play")]
    assert len(wav_files) == 1

    other = client.post("/api/auth/register", json={
        "username": "stranger", "email": "stranger@example.com", "password": "Parola123",
    }).json()["access_token"]
    assert client.get(f"/api/measurements/{mid}", headers={"Authorization": f"Bearer {other}"}).status_code == 404

    # Само администраторът трие от историята; той вижда и чуждите записи.
    assert client.delete(f"/api/measurements/{mid}", headers=headers).status_code == 403
    assert any(m["id"] == mid for m in client.get("/api/history", headers=admin_headers).json()["measurements"])
    assert client.delete(f"/api/measurements/{mid}", headers=admin_headers).status_code == 204
    assert client.get(f"/api/measurements/{mid}", headers=headers).status_code == 404
    assert not wav_files[0].exists()


def test_history_period_limits(client, auth_headers):
    headers, _ = auth_headers
    now = datetime.now(UTC)
    ok = {"from": (now - timedelta(days=90)).isoformat(), "to": now.isoformat()}
    assert client.get("/api/history", params=ok, headers=headers).status_code == 200
    too_old = {"from": (now - timedelta(days=100)).isoformat()}
    assert client.get("/api/history", params=too_old, headers=headers).status_code == 422
    reversed_ = {"from": now.isoformat(), "to": (now - timedelta(hours=1)).isoformat()}
    assert client.get("/api/history", params=reversed_, headers=headers).status_code == 422


# ---------- Калибровка ----------

def test_auto_calibration(client, auth_headers, monkeypatch):
    headers, _ = auth_headers
    device_id = _device(client, headers)
    base = f"/api/devices/{device_id}/calibrations"

    # Без калибратор (шум) калибровката се отказва.
    r = client.post(f"{base}/auto", json={"duration_s": 2}, headers=headers)
    assert r.status_code == 422

    monkeypatch.setattr(settings, "simulator_signal", "calibrator")
    r = client.post(f"{base}/auto", json={
        "duration_s": 2, "reference_level_db": 94, "calibrator_model": "CA114",
        "temperature_c": 22.5, "humidity_pct": 45, "pressure_kpa": 101.3, "uncertainty_db": 0.2,
    }, headers=headers)
    assert r.status_code == 201, r.text
    cal = r.json()
    # Симулаторът е с 0.4 dB по-чувствителен от номинала.
    assert cal["status"] == "pending"
    assert cal["measured_level_db"] == pytest.approx(94.4, abs=0.05)
    assert cal["offset_db"] == pytest.approx(-0.4, abs=0.05)

    # Докато не е приложена, устройството не се променя.
    assert client.get(f"/api/devices/{device_id}", headers=headers).json()["calibration_offset_db"] is None
    applied = client.post(f"{base}/{cal['id']}/apply", headers=headers).json()
    assert applied["status"] == "applied" and applied["applied_at"]
    assert client.get(f"/api/devices/{device_id}", headers=headers).json()["calibration_offset_db"] == cal["offset_db"]
    assert client.post(f"{base}/{cal['id']}/apply", headers=headers).status_code == 409


def test_manual_calibration(client, auth_headers):
    headers, _ = auth_headers
    device_id = _device(client, headers)
    base = f"/api/devices/{device_id}/calibrations"

    r = client.post(f"{base}/manual", json={"offset_db": -0.4}, headers=headers)
    assert r.status_code == 201 and r.json()["status"] == "applied"

    # По показание: уредът показва 94.5 при калибратор 94 -> корекцията намалява с 0.5.
    r = client.post(f"{base}/manual", json={"reference_level_db": 94, "measured_level_db": 94.5}, headers=headers)
    assert r.json()["offset_db"] == pytest.approx(-0.9)
    assert r.json()["drift_db"] == pytest.approx(-0.5)

    assert client.post(f"{base}/manual", json={}, headers=headers).status_code == 422
    history = client.get(base, headers=headers).json()
    assert [c["offset_db"] for c in history] == [-0.9, -0.4]

    # Смяна на чувствителността обезсилва калибровката.
    client.put(f"/api/devices/{device_id}", json=DEVICE | {"sensitivity_dbfs": -20}, headers=headers)
    assert client.get(f"/api/devices/{device_id}", headers=headers).json()["calibration_offset_db"] is None


def test_recording_contains_calibration(client, auth_headers):
    headers, token = auth_headers
    device_id = _device(client, headers)
    client.post(f"/api/devices/{device_id}/calibrations/manual", json={"offset_db": 1.5}, headers=headers)
    mid = _record(client, token, device_id, 1.2, record=True)["measurement_id"]
    info = client.get(f"/api/measurements/{mid}", headers=headers).json()["device_info"]
    assert info["calibration_offset_db"] == 1.5 and info["calibration_id"] is not None
    assert info["level_offset_db"] == pytest.approx(94 + 18 + 1.5)


def test_calibration_due_date(client, auth_headers):
    from datetime import datetime

    from app.models import add_months

    assert add_months(datetime(2026, 1, 31), 1) == datetime(2026, 2, 28)
    assert add_months(datetime(2026, 11, 15), 3) == datetime(2027, 2, 15)

    headers, _ = auth_headers
    device_id = _device(client, headers)
    d = client.get(f"/api/devices/{device_id}", headers=headers).json()
    assert d["calibration_status"] == "none" and d["calibration_interval_months"] == 12
    assert d["next_calibration_due"] is None

    client.post(f"/api/devices/{device_id}/calibrations/manual", json={"offset_db": 0.3}, headers=headers)
    d = client.get(f"/api/devices/{device_id}", headers=headers).json()
    assert d["calibration_status"] == "valid"
    last = datetime.fromisoformat(d["last_calibration_at"].rstrip("Z"))
    due = datetime.fromisoformat(d["next_calibration_due"].rstrip("Z"))
    assert due == add_months(last, 12)

    # Интервал от 0 месеца не е позволен, без интервал - няма срок.
    assert client.put(f"/api/devices/{device_id}", json=DEVICE | {"calibration_interval_months": 0},
                      headers=headers).status_code == 422
    d = client.put(f"/api/devices/{device_id}", json=DEVICE | {"calibration_interval_months": None},
                   headers=headers).json()
    assert d["next_calibration_due"] is None and d["calibration_status"] == "valid"
