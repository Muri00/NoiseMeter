import os
import tempfile

from dotenv import dotenv_values

# Тестовете използват TEST_DATABASE_URL (MariaDB), ако е зададен в средата или в .env,
# иначе временна SQLite база. Звукът идва от симулатора.
_test_db = os.environ.get("TEST_DATABASE_URL") or dotenv_values(".env").get("TEST_DATABASE_URL")
if not _test_db:
    _test_db = "sqlite:///" + os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["DATABASE_URL"] = _test_db
os.environ["AUDIO_SOURCE"] = "simulator"
os.environ["RECORDINGS_DIR"] = tempfile.mkdtemp()
os.environ["JWT_SECRET"] = "test-secret-key-with-enough-length-1234"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402

# Чиста база при всяко пускане на тестовете.
Base.metadata.drop_all(bind=engine)


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture
def auth_headers(client):
    import uuid

    name = "u" + uuid.uuid4().hex[:10]
    r = client.post("/api/auth/register", json={
        "username": name, "email": f"{name}@example.com", "password": "Parola123",
    })
    assert r.status_code == 201, r.text
    token = r.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}, token
