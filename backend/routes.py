"""
AuraMind API routes.

Provides sensor snapshot ingestion, AI-driven alerts/suggestions (via Groq),
reading history, aggregated reports, location persistence, and feedback.
Data is stored via async SQLAlchemy (PostgreSQL in production, SQLite locally).
"""

from __future__ import annotations

import json
import os
import uuid
from collections import deque
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import Column, String, Float, Integer, Text, DateTime, select, delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from .db import Base, get_session

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")

router = APIRouter(prefix="/auramind", tags=["auramind"])


# ── SQLAlchemy models ─────────────────────────────────────────────────────

class AuramindReading(Base):
    __tablename__ = "auramind_readings"
    id = Column(Integer, primary_key=True, autoincrement=True)
    patient_id = Column(String, nullable=False, index=True)
    ts = Column(DateTime(timezone=True), nullable=False, index=True)
    place = Column(String)
    minutes_at_place = Column(Integer)
    time_of_day = Column(String)
    sound_db = Column(Float)
    temperature_c = Column(Float)
    humidity_pct = Column(Float)
    light_lux = Column(Float)
    mood_level = Column(String)
    mood_score = Column(Float)


class AuramindIntervention(Base):
    __tablename__ = "auramind_interventions"
    id = Column(String, primary_key=True)
    patient_id = Column(String, nullable=False, index=True)
    ts = Column(DateTime(timezone=True), nullable=False)
    tool = Column(String, nullable=False)
    severity = Column(String)
    message = Column(Text)
    feedback = Column(String)


class AuramindLocation(Base):
    __tablename__ = "auramind_locations"
    patient_id = Column(String, primary_key=True)
    place = Column(String, nullable=False, default="Home")


# ── Mood estimation ──────────────────────────────────────────────────────

def estimate_mood(temp: float, humidity: float, sound: float = 0) -> tuple[str, float]:
    score = 75.0
    if temp > 30 or temp < 17:
        score -= 18
    elif temp > 28 or temp < 19:
        score -= 8
    if humidity > 80:
        score -= 15
    elif humidity > 70:
        score -= 7
    if sound and sound > 75:
        score -= 12
    score = max(10.0, min(98.0, score))
    if score >= 80:
        level = "excellent"
    elif score >= 65:
        level = "good"
    elif score >= 50:
        level = "neutral"
    elif score >= 35:
        level = "low"
    else:
        level = "veryLow"
    return level, score


# ── Alert dedup helpers ──────────────────────────────────────────────────

def _alert_signature(temp: float, humidity: float) -> tuple:
    parts = []
    if temp >= 33:
        parts.append(("temp", "danger"))
    elif temp >= 30:
        parts.append(("temp", "warning"))
    if humidity >= 85:
        parts.append(("humidity", "danger"))
    return tuple(sorted(parts))


def _severity_rank(sig: tuple) -> int:
    order = {"warning": 1, "danger": 2}
    return max([order.get(sev, 0) for _, sev in sig], default=0)


# ── In-memory session state (per patient) ────────────────────────────────

MEMORY_SIZE = 5
FEEDBACK_MEMORY = 8
SUGGESTION_COOLDOWN_MIN = 30
SESSIONS: dict[str, dict] = {}


def _get_session(patient_id: str) -> dict:
    if patient_id not in SESSIONS:
        SESSIONS[patient_id] = {
            "history": deque(maxlen=MEMORY_SIZE),
            "actions": deque(maxlen=3),
            "feedback": deque(maxlen=FEEDBACK_MEMORY),
            "open_actions": {},
            "last_alert_sig": (),
            "last_suggestion_at": None,
        }
    return SESSIONS[patient_id]


# ── Groq agent ───────────────────────────────────────────────────────────

TOOLS = [
    {"type": "function", "function": {"name": "stand_by",
        "description": "Use when nothing warrants reaching out.",
        "parameters": {"type": "object", "properties": {"reason": {"type": "string"}},
                       "required": ["reason"]}}},
    {"type": "function", "function": {"name": "send_alert",
        "description": "Send a safety alert.",
        "parameters": {"type": "object", "properties": {
            "message": {"type": "string"},
            "severity": {"type": "string", "enum": ["info", "warning", "danger"]}},
            "required": ["message", "severity"]}}},
    {"type": "function", "function": {"name": "suggest_activity",
        "description": "Gently suggest a change or activity.",
        "parameters": {"type": "object", "properties": {"message": {"type": "string"}},
                       "required": ["message"]}}},
    {"type": "function", "function": {"name": "log_observation",
        "description": "Record a note for trend tracking.",
        "parameters": {"type": "object", "properties": {"note": {"type": "string"}},
                       "required": ["note"]}}},
]

SYSTEM_PROMPT = """\
You are AuraMind, a calm wellbeing companion that watches a patient's environment.

Respond to each snapshot with tool calls in ONE turn:
- log_observation once (note reflecting history patterns, not just the latest).
- send_alert once if: temperature_c >= 33 OR humidity_pct >= 85 (danger);
  temperature_c >= 30 (warning).
- suggest_activity once if conditions are not dangerous but sustained discomfort.
- stand_by if everything is fine.

Style: warm, brief, English only. No medical claims. Tailor wording to the
patient's declared place (Home → comfort cues; Campus → break cues).
"""


def _run_agent(patient_id: str, history, recent_actions, feedback) -> list[dict]:
    try:
        from groq import Groq
    except ImportError:
        return [{"tool": "stand_by", "args": {"reason": "Groq SDK not installed"}}]

    api_key = GROQ_API_KEY
    if not api_key:
        return [{"tool": "stand_by", "args": {"reason": "No GROQ_API_KEY configured"}}]

    client = Groq(api_key=api_key)
    model = GROQ_MODEL
    actions_taken = []

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content":
            f"Recent history:\n{json.dumps(list(history), indent=2)}\n\n"
            f"Your recent interventions:\n{json.dumps(list(recent_actions), indent=2) if recent_actions else '(none)'}\n\n"
            f"Patient feedback:\n{json.dumps(list(feedback), indent=2) if feedback else '(none)'}\n\n"
            f"Decide what to do based on the latest snapshot."},
    ]

    for _ in range(2):
        try:
            response = client.chat.completions.create(
                model=model, messages=messages, tools=TOOLS, tool_choice="auto")
        except Exception as e:
            actions_taken.append({"tool": "error", "args": {"message": str(e)[:100]}})
            break
        msg = response.choices[0].message
        messages.append(msg)
        if not msg.tool_calls:
            break
        for call in msg.tool_calls:
            try:
                args = json.loads(call.function.arguments)
            except json.JSONDecodeError:
                args = {}
            actions_taken.append({"tool": call.function.name, "args": args})
            messages.append({"role": "tool", "tool_call_id": call.id, "content": "done"})

    return actions_taken


# ── Request / Response schemas ────────────────────────────────────────────

class SnapshotRequest(BaseModel):
    patient_id: str
    place: str
    minutes_at_place: int
    time_of_day: str
    sound_db: float = 0.0
    temperature_c: float
    humidity_pct: float
    light_lux: float = -1.0


class FeedbackRequest(BaseModel):
    patient_id: str
    action_id: str
    response: str


class LocationRequest(BaseModel):
    patient_id: str
    place: str


# ── Endpoints ────────────────────────────────────────────────────────────

@router.post("/snapshot")
async def snapshot(snap: SnapshotRequest, db: AsyncSession = Depends(get_session)):
    session = _get_session(snap.patient_id)
    reading = snap.model_dump()
    reading.pop("patient_id")
    session["history"].append(reading)

    import asyncio
    actions = await asyncio.get_event_loop().run_in_executor(
        None, _run_agent, snap.patient_id, session["history"], session["actions"], session["feedback"]
    )
    
    now = datetime.now(timezone.utc)
    level, score = estimate_mood(snap.temperature_c, snap.humidity_pct, snap.sound_db)
    cur_sig = _alert_signature(snap.temperature_c, snap.humidity_pct)

    # Dedup alerts and suggestions
    filtered = []
    for a in actions:
        tool = a["tool"]
        if tool == "send_alert":
            last_sig = session["last_alert_sig"]
            if cur_sig and (cur_sig != last_sig or _severity_rank(cur_sig) > _severity_rank(last_sig)):
                session["last_alert_sig"] = cur_sig
                filtered.append(a)
        elif tool == "suggest_activity":
            last_at = session["last_suggestion_at"]
            if last_at is None or (now - last_at) > timedelta(minutes=SUGGESTION_COOLDOWN_MIN):
                session["last_suggestion_at"] = now
                filtered.append(a)
        else:
            filtered.append(a)

    if not cur_sig:
        session["last_alert_sig"] = ()

    # Persist reading
    db.add(AuramindReading(
        patient_id=snap.patient_id, ts=now, place=snap.place,
        minutes_at_place=snap.minutes_at_place, time_of_day=snap.time_of_day,
        sound_db=snap.sound_db, temperature_c=snap.temperature_c,
        humidity_pct=snap.humidity_pct, light_lux=snap.light_lux,
        mood_level=level, mood_score=score,
    ))

    response_actions = []
    for a in filtered:
        if a["tool"] in ("send_alert", "suggest_activity"):
            action_id = uuid.uuid4().hex[:12]
            session["actions"].append(a)
            session["open_actions"][action_id] = a
            db.add(AuramindIntervention(
                id=action_id, patient_id=snap.patient_id, ts=now,
                tool=a["tool"], severity=a["args"].get("severity"),
                message=a["args"].get("message"), feedback=None,
            ))
            response_actions.append({"id": action_id, **a})
        else:
            response_actions.append(a)

    await db.commit()
    return {"actions": response_actions, "mood": {"level": level, "score": score}}


@router.post("/feedback")
async def feedback(fb: FeedbackRequest, db: AsyncSession = Depends(get_session)):
    valid = {"okay", "not_okay", "not_relevant", "done", "not_now",
             "done_helpful", "done_not_helpful", "not_helpful"}
    if fb.response not in valid:
        raise HTTPException(400, f"Invalid response: {fb.response}")

    session = SESSIONS.get(fb.patient_id)
    action = session["open_actions"].pop(fb.action_id, None) if session else None
    if session is not None:
        session["feedback"].appendleft({
            "intervention": {"tool": action["tool"], "args": action["args"]} if action else {},
            "response": fb.response,
        })

    result = await db.execute(
        select(AuramindIntervention).where(AuramindIntervention.id == fb.action_id)
    )
    row = result.scalar_one_or_none()
    if row:
        row.feedback = fb.response
        await db.commit()

    return {"status": "ok"}


@router.get("/history")
async def history(patient_id: str, hours: int = 24, db: AsyncSession = Depends(get_session)):
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    result = await db.execute(
        select(AuramindReading)
        .where(AuramindReading.patient_id == patient_id, AuramindReading.ts >= since)
        .order_by(AuramindReading.ts)
    )
    rows = result.scalars().all()
    return {"readings": [{
        "ts": r.ts.isoformat(), "mood_level": r.mood_level, "mood_score": r.mood_score,
        "temperature_c": r.temperature_c, "humidity_pct": r.humidity_pct,
        "sound_db": r.sound_db or 0,
    } for r in rows]}


@router.get("/report")
async def report(patient_id: str, days: int = 7, db: AsyncSession = Depends(get_session)):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    result = await db.execute(
        select(AuramindReading)
        .where(AuramindReading.patient_id == patient_id, AuramindReading.ts >= since)
    )
    rows = result.scalars().all()
    scores = [r.mood_score for r in rows if r.mood_score]
    dist: dict[str, int] = {}
    for r in rows:
        if r.mood_level:
            dist[r.mood_level] = dist.get(r.mood_level, 0) + 1
    avg = sum(scores) / len(scores) if scores else 0

    interv_result = await db.execute(
        select(AuramindIntervention)
        .where(AuramindIntervention.patient_id == patient_id, AuramindIntervention.ts >= since)
        .order_by(AuramindIntervention.ts.desc())
    )
    interventions = [{"tool": i.tool, "severity": i.severity,
                      "message": i.message, "feedback": i.feedback}
                     for i in interv_result.scalars().all()]

    return {"days": days, "reading_count": len(rows), "avg_score": round(avg, 1),
            "distribution": dist, "interventions": interventions}


@router.get("/location/{patient_id}")
async def get_location(patient_id: str, db: AsyncSession = Depends(get_session)):
    result = await db.execute(
        select(AuramindLocation).where(AuramindLocation.patient_id == patient_id)
    )
    row = result.scalar_one_or_none()
    return {"place": row.place if row else "Home"}


@router.post("/location")
async def set_location(loc: LocationRequest, db: AsyncSession = Depends(get_session)):
    result = await db.execute(
        select(AuramindLocation).where(AuramindLocation.patient_id == loc.patient_id)
    )
    row = result.scalar_one_or_none()
    if row:
        row.place = loc.place
    else:
        db.add(AuramindLocation(patient_id=loc.patient_id, place=loc.place))
    await db.commit()
    return {"status": "ok", "place": loc.place}


@router.post("/reset/{patient_id}")
async def reset(patient_id: str, db: AsyncSession = Depends(get_session)):
    SESSIONS.pop(patient_id, None)
    await db.execute(delete(AuramindReading).where(AuramindReading.patient_id == patient_id))
    await db.execute(delete(AuramindIntervention).where(AuramindIntervention.patient_id == patient_id))
    await db.commit()
    return {"status": "reset", "patient_id": patient_id}


# ── AI coping suggestions ─────────────────────────────────────────────────────

class CopingRequest(BaseModel):
    conditions: list[str]


@router.post("/coping")
async def coping_suggestions(req: CopingRequest):
    if not req.conditions:
        return {"steps": []}

    prompt = (
        "The user cannot change their environment right now.\n"
        f"Current conditions outside their comfort zone: {', '.join(req.conditions)}.\n\n"
        "Generate exactly 3 practical coping strategies they can do RIGHT NOW "
        "without leaving their seat or needing any equipment. Each under 3 minutes. "
        "Be specific to the conditions listed — no generic advice.\n\n"
        "Respond ONLY with a valid JSON array, no markdown, no explanation:\n"
        "[\n"
        "  {\"title\": \"Short action title\", \"description\": \"One or two sentence specific instruction.\", \"minutes\": 2},\n"
        "  {\"title\": \"...\", \"description\": \"...\", \"minutes\": 1},\n"
        "  {\"title\": \"...\", \"description\": \"...\", \"minutes\": 3}\n"
        "]"
    )

    try:
        from groq import Groq
        import json as _json
        client = Groq(api_key=GROQ_API_KEY)
        completion = client.chat.completions.create(
            model=GROQ_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
            max_tokens=500,
        )
        raw = completion.choices[0].message.content.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        steps = _json.loads(raw)
        return {"steps": steps}
    except Exception as e:
        print(f"Coping generation error: {e}")
        return {"steps": [
            {"title": "Slow your breathing", "description": "Breathe in 4 counts, hold 2, out 6. Repeat 5 times.", "minutes": 2},
            {"title": "Cool your wrists", "description": "Press something cool to your wrists for 20 seconds.", "minutes": 1},
            {"title": "Focus anchor", "description": "Pick one nearby object and describe it mentally in full detail for 60 seconds.", "minutes": 1},
        ]}
