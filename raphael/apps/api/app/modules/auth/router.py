"""API d'authentification : /v1/auth/*"""
import secrets
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.core.config import get_settings
from app.core.request_meta import client_ip
from app.modules.auth import service
from app.modules.auth.deps import DEVICE_COOKIE, SESSION_COOKIE, get_conn, require_session
from app.modules.auth.ratelimit import FailureLimiter
from app.modules.auth.schemas import (
    AuthStatus,
    DeviceOut,
    LoginRequest,
    MeResponse,
    RenameDevice,
    RevokedCount,
    SessionOut,
    SetupRequest,
)

router = APIRouter(prefix="/auth", tags=["auth"])

DEVICE_COOKIE_MAX_AGE = 400 * 24 * 3600  # plafond accepté par les navigateurs


def _limiter(request: Request) -> FailureLimiter:
    return request.app.state.login_limiter


def _secure(request: Request) -> bool:
    proto = request.headers.get("x-forwarded-proto", request.url.scheme)
    return get_settings().is_production or proto.split(",")[0].strip() == "https"


def _set_cookies(request: Request, response: Response, token: str, device_id: UUID) -> None:
    secure = _secure(request)
    response.set_cookie(SESSION_COOKIE, token, max_age=get_settings().session_ttl_days * 86400,
                        httponly=True, secure=secure, samesite="strict", path="/")
    response.set_cookie(DEVICE_COOKIE, str(device_id), max_age=DEVICE_COOKIE_MAX_AGE,
                        httponly=True, secure=secure, samesite="strict", path="/")


def _clear_session_cookie(request: Request, response: Response) -> None:
    response.delete_cookie(SESSION_COOKIE, path="/", httponly=True, secure=_secure(request),
                           samesite="strict")


def _known_device(request: Request) -> UUID | None:
    raw = request.cookies.get(DEVICE_COOKIE)
    try:
        return UUID(raw) if raw else None
    except ValueError:
        return None


@router.get("/status", response_model=AuthStatus)
async def auth_status(conn: asyncpg.Connection = Depends(get_conn)) -> AuthStatus:
    return AuthStatus(setup_required=not await service.owner_exists(conn),
                      setup_token_required=get_settings().setup_token is not None)


@router.post("/setup", response_model=MeResponse, status_code=status.HTTP_201_CREATED)
async def setup(body: SetupRequest, request: Request, response: Response,
                conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    """Crée le compte propriétaire unique. Fermé définitivement dès qu'il existe."""
    expected = get_settings().setup_token
    if expected is not None and not secrets.compare_digest(
        (body.setup_token or "").encode(), expected.get_secret_value().encode()
    ):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Jeton de configuration invalide.")
    ip = client_ip(request)
    try:
        async with conn.transaction():
            user_id = await service.create_owner(conn, email=body.email,
                                                 display_name=body.display_name,
                                                 password=body.password)
            device_id = await service.resolve_device(conn, user_id, None, body.device_name,
                                                     body.platform)
            token, session_id = await service.open_session(
                conn, user_id=user_id, device_id=device_id,
                ttl_days=get_settings().session_ttl_days, ip=ip,
                user_agent=request.headers.get("user-agent"))
            await service.audit(conn, user_id, "auth.setup", ip=ip,
                                details={"device": body.device_name})
    except service.SetupClosed:
        raise HTTPException(status.HTTP_409_CONFLICT, "Le compte propriétaire existe déjà.") from None
    _set_cookies(request, response, token, device_id)
    return await service.get_me(conn, service.AuthContext(user_id, session_id, device_id))


@router.post("/login", response_model=MeResponse)
async def login(body: LoginRequest, request: Request, response: Response,
                conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    ip = client_ip(request)
    keys = (f"ip:{ip}", f"email:{body.email.lower()}")
    limiter = _limiter(request)
    if wait := limiter.retry_after(*keys):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS,
                            "Trop de tentatives. Réessayez plus tard.",
                            headers={"Retry-After": str(wait)})

    user_id = await service.authenticate(conn, body.email, body.password)
    if user_id is None:
        limiter.record_failure(*keys)
        await service.audit(conn, None, "auth.login_failed", ip=ip,
                            details={"email": body.email.lower()})
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Identifiants incorrects.")

    limiter.reset(keys[0])
    async with conn.transaction():
        device_id = await service.resolve_device(conn, user_id, _known_device(request),
                                                 body.device_name, body.platform)
        token, session_id = await service.open_session(
            conn, user_id=user_id, device_id=device_id,
            ttl_days=get_settings().session_ttl_days, ip=ip,
            user_agent=request.headers.get("user-agent"))
        await service.audit(conn, user_id, "auth.login", target=str(session_id), ip=ip)
    _set_cookies(request, response, token, device_id)
    return await service.get_me(conn, service.AuthContext(user_id, session_id, device_id))


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request, response: Response,
                 ctx: service.AuthContext = Depends(require_session),
                 conn: asyncpg.Connection = Depends(get_conn)) -> None:
    await service.revoke_session(conn, ctx.user_id, ctx.session_id)
    await service.audit(conn, ctx.user_id, "auth.logout", target=str(ctx.session_id),
                        ip=client_ip(request))
    _clear_session_cookie(request, response)


@router.get("/me", response_model=MeResponse)
async def me(ctx: service.AuthContext = Depends(require_session),
             conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    return await service.get_me(conn, ctx)


@router.get("/sessions", response_model=list[SessionOut])
async def sessions(ctx: service.AuthContext = Depends(require_session),
                   conn: asyncpg.Connection = Depends(get_conn)) -> list[dict]:
    return await service.list_sessions(conn, ctx)


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke(session_id: UUID, request: Request, response: Response,
                 ctx: service.AuthContext = Depends(require_session),
                 conn: asyncpg.Connection = Depends(get_conn)) -> None:
    if not await service.revoke_session(conn, ctx.user_id, session_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Session introuvable.")
    await service.audit(conn, ctx.user_id, "auth.session_revoked", target=str(session_id),
                        ip=client_ip(request))
    if session_id == ctx.session_id:
        _clear_session_cookie(request, response)


@router.post("/sessions/revoke-others", response_model=RevokedCount)
async def revoke_others(request: Request, ctx: service.AuthContext = Depends(require_session),
                        conn: asyncpg.Connection = Depends(get_conn)) -> RevokedCount:
    count = await service.revoke_other_sessions(conn, ctx.user_id, ctx.session_id)
    await service.audit(conn, ctx.user_id, "auth.sessions_revoked_others",
                        details={"count": count}, ip=client_ip(request))
    return RevokedCount(revoked=count)


@router.patch("/devices/{device_id}", response_model=DeviceOut)
async def rename(device_id: UUID, body: RenameDevice,
                 ctx: service.AuthContext = Depends(require_session),
                 conn: asyncpg.Connection = Depends(get_conn)) -> dict:
    device = await service.rename_device(conn, ctx.user_id, device_id, body.name)
    if device is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Appareil introuvable.")
    return device
