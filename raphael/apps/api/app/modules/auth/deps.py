"""Dépendances FastAPI : connexion base de données et session authentifiée."""
from collections.abc import AsyncIterator

import asyncpg
from fastapi import Depends, HTTPException, Request, status

from app.core.db import get_pool
from app.modules.auth import service

SESSION_COOKIE = "raphael_session"
DEVICE_COOKIE = "raphael_device"


async def get_conn() -> AsyncIterator[asyncpg.Connection]:
    pool = get_pool()
    if pool is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Base de données indisponible.")
    async with pool.acquire() as conn:
        yield conn


async def require_session(request: Request,
                          conn: asyncpg.Connection = Depends(get_conn)) -> service.AuthContext:
    token = request.cookies.get(SESSION_COOKIE)
    ctx = await service.session_from_token(conn, token) if token else None
    if ctx is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Authentification requise.")
    return ctx
