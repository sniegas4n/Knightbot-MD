"""Logique d'authentification : compte propriétaire, sessions opaques, appareils.

- Mots de passe : Argon2id (paramètres par défaut d'argon2-cffi, re-hachage automatique
  si ces paramètres évoluent).
- Sessions : jeton aléatoire de 256 bits remis au navigateur dans un cookie httpOnly ; la base
  ne stocke que son SHA-256. Une fuite de la base ne permet donc pas d'usurper une session.
"""
import hashlib
import json
import secrets
from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID

import asyncpg
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

_hasher = PasswordHasher()
# Haché factice : vérifié quand l'e-mail n'existe pas, pour que la durée de réponse ne révèle
# pas si le compte existe.
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))

# Mise à jour de last_seen_at au plus toutes les 5 minutes (évite une écriture par requête).
TOUCH_INTERVAL = timedelta(minutes=5)


class SetupClosed(Exception):
    """Le compte propriétaire existe déjà."""


@dataclass(frozen=True)
class AuthContext:
    user_id: UUID
    session_id: UUID
    device_id: UUID | None


def hash_token(token: str) -> bytes:
    return hashlib.sha256(token.encode()).digest()


def new_token() -> str:
    return secrets.token_urlsafe(32)


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(stored_hash: str, password: str) -> bool:
    try:
        return _hasher.verify(stored_hash, password)
    except (VerificationError, InvalidHashError):
        return False


async def audit(conn: asyncpg.Connection, user_id: UUID | None, action: str, *,
                target: str | None = None, details: dict | None = None,
                ip: str | None = None) -> None:
    await conn.execute(
        "INSERT INTO audit_log(user_id, actor, action, target, details, ip) "
        "VALUES ($1, 'user', $2, $3, $4::jsonb, $5::inet)",
        user_id, action, target, json.dumps(details or {}), ip,
    )


async def owner_exists(conn: asyncpg.Connection) -> bool:
    return bool(await conn.fetchval("SELECT EXISTS (SELECT 1 FROM users)"))


async def create_owner(conn: asyncpg.Connection, *, email: str, display_name: str,
                       password: str) -> UUID:
    try:
        return await conn.fetchval(
            "INSERT INTO users(email, display_name, password_hash) VALUES ($1, $2, $3) RETURNING id",
            email.lower(), display_name.strip(), hash_password(password),
        )
    except asyncpg.UniqueViolationError as exc:  # index users_single_owner
        raise SetupClosed from exc


async def authenticate(conn: asyncpg.Connection, email: str, password: str) -> UUID | None:
    row = await conn.fetchrow("SELECT id, password_hash FROM users WHERE email = $1", email.lower())
    if row is None:
        verify_password(_DUMMY_HASH, password)
        return None
    if not verify_password(row["password_hash"], password):
        return None
    if _hasher.check_needs_rehash(row["password_hash"]):
        await conn.execute("UPDATE users SET password_hash = $1 WHERE id = $2",
                           hash_password(password), row["id"])
    return row["id"]


async def resolve_device(conn: asyncpg.Connection, user_id: UUID, known_device: UUID | None,
                         name: str, platform: str) -> UUID:
    """Réutilise l'appareil déjà connu (cookie d'appareil) ou en enregistre un nouveau."""
    if known_device is not None:
        found = await conn.fetchval(
            "UPDATE devices SET last_seen_at = now(), platform = $3 "
            "WHERE id = $1 AND user_id = $2 RETURNING id",
            known_device, user_id, platform,
        )
        if found:
            return found
    return await conn.fetchval(
        "INSERT INTO devices(user_id, name, platform) VALUES ($1, $2, $3) RETURNING id",
        user_id, name, platform,
    )


async def open_session(conn: asyncpg.Connection, *, user_id: UUID, device_id: UUID,
                       ttl_days: int, ip: str | None, user_agent: str | None) -> tuple[str, UUID]:
    token = new_token()
    session_id = await conn.fetchval(
        "INSERT INTO sessions(user_id, device_id, token_hash, ip, user_agent, expires_at) "
        "VALUES ($1, $2, $3, $4::inet, $5, now() + make_interval(days => $6)) RETURNING id",
        user_id, device_id, hash_token(token), ip, (user_agent or "")[:300] or None, ttl_days,
    )
    return token, session_id


async def session_from_token(conn: asyncpg.Connection, token: str) -> AuthContext | None:
    row = await conn.fetchrow(
        "SELECT id, user_id, device_id, last_seen_at < now() - $2::interval AS stale "
        "FROM sessions WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()",
        hash_token(token), TOUCH_INTERVAL,
    )
    if row is None:
        return None
    if row["stale"]:
        await conn.execute("UPDATE sessions SET last_seen_at = now() WHERE id = $1", row["id"])
        if row["device_id"]:
            await conn.execute("UPDATE devices SET last_seen_at = now() WHERE id = $1", row["device_id"])
    return AuthContext(row["user_id"], row["id"], row["device_id"])


async def revoke_session(conn: asyncpg.Connection, user_id: UUID, session_id: UUID) -> bool:
    status = await conn.execute(
        "UPDATE sessions SET revoked_at = now() "
        "WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL",
        session_id, user_id,
    )
    return status.endswith(" 1")


async def revoke_other_sessions(conn: asyncpg.Connection, user_id: UUID, keep: UUID) -> int:
    status = await conn.execute(
        "UPDATE sessions SET revoked_at = now() "
        "WHERE user_id = $1 AND id <> $2 AND revoked_at IS NULL AND expires_at > now()",
        user_id, keep,
    )
    return int(status.split()[-1])


async def get_me(conn: asyncpg.Connection, ctx: AuthContext) -> dict:
    user = await conn.fetchrow(
        "SELECT id, email, display_name, locale, timezone FROM users WHERE id = $1", ctx.user_id
    )
    device = None
    if ctx.device_id:
        device = await conn.fetchrow(
            "SELECT id, name, platform FROM devices WHERE id = $1", ctx.device_id
        )
    return {"user": dict(user), "session_id": ctx.session_id,
            "device": dict(device) if device else None}


async def list_sessions(conn: asyncpg.Connection, ctx: AuthContext) -> list[dict]:
    rows = await conn.fetch(
        "SELECT s.id, host(s.ip) AS ip, s.user_agent, s.created_at, s.last_seen_at, s.expires_at, "
        "       d.id AS device_id, d.name AS device_name, d.platform "
        "FROM sessions s LEFT JOIN devices d ON d.id = s.device_id "
        "WHERE s.user_id = $1 AND s.revoked_at IS NULL AND s.expires_at > now() "
        "ORDER BY s.id = $2 DESC, s.last_seen_at DESC",
        ctx.user_id, ctx.session_id,
    )
    return [
        {
            "id": r["id"], "ip": r["ip"], "user_agent": r["user_agent"],
            "created_at": r["created_at"], "last_seen_at": r["last_seen_at"],
            "expires_at": r["expires_at"], "current": r["id"] == ctx.session_id,
            "device": ({"id": r["device_id"], "name": r["device_name"], "platform": r["platform"]}
                       if r["device_id"] else None),
        }
        for r in rows
    ]


async def rename_device(conn: asyncpg.Connection, user_id: UUID, device_id: UUID,
                        name: str) -> dict | None:
    row = await conn.fetchrow(
        "UPDATE devices SET name = $3 WHERE id = $1 AND user_id = $2 RETURNING id, name, platform",
        device_id, user_id, " ".join(name.split()),
    )
    return dict(row) if row else None
