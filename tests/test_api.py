"""API smoke tests. Run with: pytest  (no Groq key needed — AI calls fall back)."""

import os
import sys

os.environ["GROQ_API_KEY"] = ""
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_auramind.db"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

from backend.main import app  # noqa: E402
from backend.routes import estimate_mood  # noqa: E402

BASE = "/api/v1/auramind"
SNAPSHOT = dict(patient_id="t", place="Home", minutes_at_place=10, time_of_day="morning",
                sound_db=50, temperature_c=24, humidity_pct=50, light_lux=300)


def test_estimate_mood():
    assert estimate_mood(24, 50) == ("good", 75.0)
    assert estimate_mood(34, 90, 80)[0] == "veryLow"


def test_snapshot_history_report_reset():
    with TestClient(app) as c:
        r = c.post(f"{BASE}/snapshot", json=SNAPSHOT)
        assert r.status_code == 200
        assert r.json()["mood"]["level"] == "good"

        readings = c.get(f"{BASE}/history", params={"patient_id": "t"}).json()["readings"]
        assert len(readings) >= 1

        report = c.get(f"{BASE}/report", params={"patient_id": "t"}).json()
        assert report["reading_count"] >= 1

        assert c.post(f"{BASE}/reset/t").json()["status"] == "reset"
        assert c.get(f"{BASE}/history", params={"patient_id": "t"}).json()["readings"] == []


def test_location_roundtrip():
    with TestClient(app) as c:
        c.post(f"{BASE}/location", json={"patient_id": "t", "place": "Campus"})
        assert c.get(f"{BASE}/location/t").json() == {"place": "Campus"}


def test_coping_falls_back_without_ai():
    with TestClient(app) as c:
        steps = c.post(f"{BASE}/coping", json={"conditions": ["too hot (34°C)"]}).json()["steps"]
        assert len(steps) == 3


def test_feedback_rejects_invalid_response():
    with TestClient(app) as c:
        r = c.post(f"{BASE}/feedback", json={"patient_id": "t", "action_id": "x", "response": "meh"})
        assert r.status_code == 400
