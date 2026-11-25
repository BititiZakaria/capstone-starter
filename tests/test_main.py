from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready():
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["ready"] is True


def test_config():
    r = client.get("/config")
    assert r.status_code == 200
    assert "environment" in r.json()
    assert "log_level" in r.json()


def test_predict():
    assert client.get("/predict?x=1").json()["label"] == "positive"
