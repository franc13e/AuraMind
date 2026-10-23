"""AuraMind FastAPI application.

Run locally:  uvicorn backend.main:app --reload --port 8001
On Vercel this app is served from api/index.py under /api.
"""

import os

from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402

from .routes import router  # noqa: E402

app = FastAPI(title="AuraMind API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router, prefix="/api/v1")


@app.get("/api/health")
async def health():
    return {"status": "ok", "ai": bool(os.getenv("GROQ_API_KEY"))}
