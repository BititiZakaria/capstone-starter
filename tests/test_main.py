from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_predict():
    # Exercice 1 TP3 : Echec volontaire pour declencher un run rouge dans la CI
    assert client.get("/predict?x=1").json()["label"] == "wrong_label_error"
