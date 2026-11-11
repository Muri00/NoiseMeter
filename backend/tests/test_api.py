from sqlalchemy import select

from app.database import SessionLocal
from app.models import User

DEVICE = {
    "brand": "miniDSP", "model": "UMIK-1", "serial_number": "2182175",
    "sensitivity_dbfs": -18.0, "freq_min_hz": 20, "freq_max_hz": 20000,
}


def test_password_is_stored_hashed(client):
    r = client.post("/api/auth/register", json={
        "username": "ivan", "email": "Ivan@Example.com", "password": "Tajna1234",
    })
    assert r.status_code == 201
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == "ivan"))
    assert user.password_hash != "Tajna1234"
    assert user.password_hash.startswith("$2b$")
    assert user.email == "ivan@example.com"


def test_register_rejects_duplicates_and_weak_passwords(client):
    body = {"username": "maria", "email": "maria@example.com", "password": "Parola123"}
    assert client.post("/api/auth/register", json=body).status_code == 201
    assert client.post("/api/auth/register", json=body).status_code == 409
    weak = {"username": "petar", "email": "p@example.com", "password": "abcdefgh"}
    assert client.post("/api/auth/register", json=weak).status_code == 422


def test_login(client):
    client.post("/api/auth/register", json={
        "username": "georgi", "email": "georgi@example.com", "password": "Parola123",
    })
    ok = client.post("/api/auth/login", json={"login": "georgi@example.com", "password": "Parola123"})
    assert ok.status_code == 200
    headers = {"Authorization": f"Bearer {ok.json()['access_token']}"}
    assert client.get("/api/auth/me", headers=headers).json()["username"] == "georgi"

    bad = client.post("/api/auth/login", json={"login": "georgi", "password": "Greshna123"})
    assert bad.status_code == 401
    assert client.get("/api/auth/me").status_code == 401


def test_device_crud_and_isolation(client, auth_headers):
    headers, _ = auth_headers
    r = client.post("/api/devices", json=DEVICE, headers=headers)
    assert r.status_code == 201
    device_id = r.json()["id"]

    assert client.post("/api/devices", json=DEVICE, headers=headers).status_code == 409
    bad_range = DEVICE | {"serial_number": "x", "freq_min_hz": 2}
    assert client.post("/api/devices", json=bad_range, headers=headers).status_code == 422

    r = client.put(f"/api/devices/{device_id}", json=DEVICE | {"model": "UMIK-2"}, headers=headers)
    assert r.json()["model"] == "UMIK-2"

    # Друг потребител не вижда устройството.
    other = client.post("/api/auth/register", json={
        "username": "other", "email": "other@example.com", "password": "Parola123",
    }).json()["access_token"]
    other_headers = {"Authorization": f"Bearer {other}"}
    assert client.get(f"/api/devices/{device_id}", headers=other_headers).status_code == 404
    assert client.get("/api/devices", headers=other_headers).json() == []

    assert client.delete(f"/api/devices/{device_id}", headers=headers).status_code == 204


def test_settings(client, auth_headers):
    headers, _ = auth_headers
    s = client.get("/api/settings", headers=headers).json()
    assert len(s["indicators"]) >= 5

    new = {"indicators": ["LAF", "LAS", "LAeq", "LCF", "LZSmax", "LAImin"],
           "f_min_hz": 31.5, "f_max_hz": 8000, "band_mode": "1/1"}
    assert client.put("/api/settings", json=new, headers=headers).json() == new

    too_few = new | {"indicators": ["LAF", "LAS"]}
    assert client.put("/api/settings", json=too_few, headers=headers).status_code == 422
    invalid = new | {"indicators": ["LAF", "LAS", "LAeq", "LCF", "LXX"]}
    assert client.put("/api/settings", json=invalid, headers=headers).status_code == 422


def test_websocket_measurement(client, auth_headers):
    headers, token = auth_headers
    device_id = client.post("/api/devices", json=DEVICE, headers=headers).json()["id"]

    with client.websocket_connect("/ws/measure") as ws:
        ws.send_json({"action": "auth", "token": token})
        assert ws.receive_json()["type"] == "auth_ok"

        # Интервал извън работната лента на устройството се допуска, но се отбелязва като ненадежден.
        ws.send_json({"action": "start", "device_id": device_id, "f_min": 10, "f_max": 20000})
        started = ws.receive_json()
        assert started["type"] == "started" and started["out_of_band"] is True
        assert started["device_band"] == [20, 20000] and "61672" in started["standard"]
        ws.send_json({"action": "stop"})
        msg = ws.receive_json()
        while msg["type"] == "frame":
            msg = ws.receive_json()
        assert msg["type"] == "stopped"

        # Извън абсолютните граници 3 Hz - 80 kHz е грешка.
        ws.send_json({"action": "start", "device_id": device_id, "f_min": 1, "f_max": 20000})
        assert ws.receive_json()["type"] == "error"

        ws.send_json({"action": "start", "device_id": device_id, "band_mode": "1/1"})
        assert ws.receive_json()["type"] == "started"
        frames = [ws.receive_json() for _ in range(12)]
        assert all(f["type"] == "frame" for f in frames)
        assert {"LAF", "LZSmax", "LCeq"} <= frames[-1]["levels"].keys()
        assert 40 < frames[-1]["levels"]["LZeq"] < 90
        assert "bands" in frames[-1]

        ws.send_json({"action": "stop"})
        msg = ws.receive_json()
        while msg["type"] == "frame":
            msg = ws.receive_json()
        assert msg["type"] == "stopped"
        assert msg["duration"] > 1.0


def test_websocket_rejects_bad_token(client):
    import pytest
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect) as e:
        with client.websocket_connect("/ws/measure") as ws:
            ws.send_json({"action": "auth", "token": "bad"})
            ws.receive_json()
    assert e.value.code == 4401
