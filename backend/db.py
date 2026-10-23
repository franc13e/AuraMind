"""Database setup: async SQLAlchemy engine, session dependency and table creation."""

from __future__ import annotations

import os
from collections.abc import AsyncGenerator
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import declarative_base
from sqlalchemy.pool import NullPool

Base = declarative_base()


def _database_url() -> tuple[str, dict]:
    """Resolve DATABASE_URL into an async driver URL plus connect args.

    Accepts plain ``postgres://`` / ``postgresql://`` URLs (as given by Neon,
    Supabase or Vercel Postgres) and rewrites them for asyncpg. Without
    DATABASE_URL, falls back to a local SQLite file (``/tmp`` on Vercel,
    where it does not persist between cold starts).
    """
    url = os.getenv("DATABASE_URL", "")
    if not url:
        path = "/tmp/auramind.db" if os.getenv("VERCEL") else "./auramind.db"
        return f"sqlite+aiosqlite:///{path}", {}

    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+asyncpg://" + url[len("postgresql://"):]

    connect_args: dict = {}
    if url.startswith("postgresql+asyncpg://"):
        # asyncpg does not understand libpq query params such as sslmode.
        parts = urlsplit(url)
        query = dict(parse_qsl(parts.query))
        sslmode = query.pop("sslmode", None)
        query.pop("channel_binding", None)
        if sslmode and sslmode != "disable":
            connect_args["ssl"] = "require"
        url = urlunsplit(parts._replace(query=urlencode(query)))
    return url, connect_args


_url, _connect_args = _database_url()

# NullPool: serverless functions should not hold connections between invocations.
engine = create_async_engine(_url, poolclass=NullPool, connect_args=_connect_args)
async_session_factory = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)

_tables_ready = False


async def init_db() -> None:
    global _tables_ready
    if _tables_ready:
        return
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    _tables_ready = True


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    await init_db()
    async with async_session_factory() as session:
        yield session
