"""Профил: редакция на данните, смяна на паролата, изтриване на акаунта."""

from pathlib import Path

from app.config import settings
from tests.test_stage2 import _device, _record


def _register(client, name):
    r = client.post("/api/auth/register", json={
        "username": name, "email": f"{name}@example.com", "password": "Parola123",
    })
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_update_profile(client):
    h = _register(client, "profile1")
    _register(client, "profile2")
    r = client.put("/api/auth/me", json={"email": "New@Example.com", "first_name": " Иван ", "last_name": ""}, headers=h)
    assert r.status_code == 200
    assert r.json() | {"id": 0} == {"id": 0, "username": "profile1", "email": "new@example.com",
                                      "first_name": "Иван", "last_name": None}
    taken = client.put("/api/auth/me", json={"email": "profile2@example.com"}, headers=h)
    assert taken.status_code == 409


def test_change_password_invalidates_old_tokens(client):
    old = _register(client, "pwuser")
    bad = client.post("/api/auth/change-password", json={"current_password": "Greshna1", "new_password": "Nova12345"}, headers=old)
    assert bad.status_code == 400
    weak = client.post("/api/auth/change-password", json={"current_password": "Parola123", "new_password": "abcdefgh"}, headers=old)
    assert weak.status_code == 422

    r = client.post("/api/auth/change-password", json={"current_password": "Parola123", "new_password": "Nova12345"}, headers=old)
    assert r.status_code == 200
    new = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get("/api/auth/me", headers=new).status_code == 200

    # Старият токен е издаден в същата секунда - симулираме по-ранен токен.
    import jwt
    from datetime import UTC, datetime, timedelta
    user_id = r.json()["user"]["id"]
    earlier = jwt.encode({"sub": str(user_id), "iat": datetime.now(UTC) - timedelta(minutes=5),
                          "exp": datetime.now(UTC) + timedelta(hours=1)}, settings.jwt_secret, algorithm="HS256")
    assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {earlier}"}).status_code == 401

    assert client.post("/api/auth/login", json={"login": "pwuser", "password": "Parola123"}).status_code == 401
    assert client.post("/api/auth/login", json={"login": "pwuser", "password": "Nova12345"}).status_code == 200


def test_delete_account(client):
    h = _register(client, "leaver")
    token = h["Authorization"].split()[1]
    device_id = _device(client, h)
    mid = _record(client, token, device_id, 1.2, record=True, save_wav=True)["measurement_id"]
    wav = next(Path(settings.recordings_dir).glob(f"measurement_{mid}_*.wav"))

    assert client.post("/api/auth/delete-account", json={"password": "Greshna1"}, headers=h).status_code == 400
    assert client.post("/api/auth/delete-account", json={"password": "Parola123"}, headers=h).status_code == 204
    assert client.get("/api/auth/me", headers=h).status_code == 401
    assert client.post("/api/auth/login", json={"login": "leaver", "password": "Parola123"}).status_code == 401
    assert not wav.exists()
