# AuraMind — Agentic AI Wellbeing Companion

[![CI](https://github.com/franc13e/AuraMind/actions/workflows/ci.yml/badge.svg)](https://github.com/franc13e/AuraMind/actions/workflows/ci.yml)

AuraMind watches the environment you're in (temperature, humidity, noise and light) and uses an AI agent to decide when to step in with a gentle alert, a small reset, or a coping technique for when you can't change your surroundings.

It started as my Final Year Project: a module inside a larger mental-health platform, investigating whether **agentic AI environmental monitoring** positively influences user adoption in mental-health care. This repository is the standalone version.

**Live demo:** https://auramind-ashy.vercel.app  
_Allow location and microphone access when prompted. Audio and camera frames are processed in your browser and never uploaded; only summary readings such as noise level and temperature are saved._

**Tech Stack:** Flutter Web · Dart · FastAPI · SQLAlchemy (async) · PostgreSQL / SQLite · Groq LLM API (tool calling) · Vercel

---

## Features

- **Live environment sensing**
  - **Temperature & humidity** from local weather (Open-Meteo) based on your location
  - **Noise level** from the browser microphone (RMS → approximate dB)
  - **Light level** via the Ambient Light Sensor API, with a camera-brightness fallback
- **Mood estimation**: a rule-based engine scores how supportive your current conditions are, with a confidence level and an hourly mood map
- **Agentic AI interventions**: each snapshot goes to an LLM agent that chooses tools (`send_alert`, `suggest_activity`, `log_observation`, `stand_by`), using recent history and your past feedback
- **Action plan**: ranked, time-estimated steps that close the gap between current conditions and your comfort profile
- **AI coping techniques**: when you can't change the space, AuraMind generates three specific under-3-minute regulation exercises
- **Alerts with feedback loop**: rate interventions as helpful or not, and the agent takes this into account next time
- **Trends & weekly report**: mood trend charts, mood distribution and intervention history
- **Personal comfort profile & places**: set your own thresholds; detect Home / Campus / custom places with geofencing
- **Demo scenarios**: scripted sequences (e.g. study-session decline, clinical escalation) for presentations
- **Adoption survey**: built-in TAM/UTAUT questionnaire (usefulness, ease of use, trust, privacy, intention to adopt)

## How It Works

```
 Browser sensors ──┐
 (mic, light, GPS) │      ┌──────────────── FastAPI backend ─────────────────┐
                   ▼      │                                                  │
 Flutter Web app ──POST /snapshot──▶ store reading ─▶ Groq agent (tool calls)│
   mood engine     │      │                              │                   │
   action plan  ◀──┴──────┤◀──── alerts / suggestions ◀──┘ dedup + cooldown  │
   trends/report ◀── GET /history, /report ◀── PostgreSQL / SQLite           │
                          └──────────────────────────────────────────────────┘
```

A rule-based guardrail guarantees an alert whenever a safety threshold is crossed, even if the LLM skips or malforms its tool call. Alerts are de-duplicated by severity signature, and suggestions have a 30-minute cooldown so the agent doesn't nag.

## Project Structure

```
├── lib/                  # Flutter web app
│   ├── main.dart         # App entry & bottom navigation
│   ├── config.dart       # API base URL (dev / prod)
│   ├── screens/          # Home, Trends, Alerts, Plan, Report, Settings, Survey
│   ├── services/         # Sensors, mood engine, agent client, coping service
│   └── models/
├── backend/              # FastAPI app
│   ├── main.py           # App, CORS, health check
│   ├── routes.py         # AuraMind endpoints + Groq agent
│   └── db.py             # Async SQLAlchemy engine & tables
├── api/index.py          # Vercel serverless entry point
├── test/                 # Flutter unit tests
├── tests/                # Backend API tests
└── vercel.json           # Builds Flutter + serves API on the same domain
```

## API

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/v1/auramind/snapshot` | Submit a sensor reading; returns mood + agent actions |
| `POST` | `/api/v1/auramind/feedback` | Rate an alert or suggestion |
| `POST` | `/api/v1/auramind/coping` | Generate coping techniques for given conditions |
| `GET` | `/api/v1/auramind/history` | Readings for the last N hours |
| `GET` | `/api/v1/auramind/report` | Aggregated report for the last N days |
| `GET/POST` | `/api/v1/auramind/location` | Get / set the user's current place |
| `POST` | `/api/v1/auramind/reset/{id}` | Clear a user's data |
| `GET` | `/api/health` | Health check |

## Running Locally

**Backend** (Python 3.12+)

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env        # add your GROQ_API_KEY
uvicorn backend.main:app --reload --port 8001
```

**Frontend** (Flutter 3.44+)

```bash
flutter pub get
flutter run -d chrome       # debug builds talk to http://localhost:8001
```

**Tests**

```bash
pytest          # backend API tests
flutter test    # mood engine unit tests
```

Both suites, plus `flutter analyze` and a web build, run on every push via GitHub Actions.

> Without a `GROQ_API_KEY` the app still works: threshold alerts come from a rule-based guardrail and coping tips fall back to built-in techniques.

## Deployment (Vercel)

The repo deploys as a single Vercel project: `scripts/vercel_build.sh` installs Flutter and builds the web app, and `api/index.py` runs the FastAPI backend as a serverless function on the same domain.

Environment variables:

| Variable | Required | Notes |
|---|---|---|
| `GROQ_API_KEY` | Yes | From [console.groq.com](https://console.groq.com/keys) |
| `DATABASE_URL` | Recommended | Postgres URL (e.g. Neon via Vercel Storage). Without it, data is kept in temporary SQLite and resets on cold starts. |
| `GROQ_MODEL` | No | Defaults to `openai/gpt-oss-20b` |

## Notes

Sensor readings are approximations from consumer hardware (the microphone level is not a calibrated dB meter, and camera-based lux is an estimate). AuraMind offers wellbeing suggestions, not medical advice.
