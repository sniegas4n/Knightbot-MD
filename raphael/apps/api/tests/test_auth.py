"""Authentification : compte propriétaire, sessions, appareils, limitation, CSRF."""
import hashlib

import asyncpg
import pytest

OWNER = {
    "email": "Owner@Example.com",
    "display_name": "Alex",
    "password": "correct horse battery",
    "device_name": "iPhone d'Alex",
    "platform": "ios",
}
LOGIN = {"email": "owner@example.com", "password": OWNER["password"]}


async def setup_owner(client):
    r = await client.post("/v1/auth/setup", json=OWNER)
    assert r.status_code == 201, r.text
    return r


async def test_setup_is_single_use(clean_db, make_client):
    c = make_client()
    assert (await c.get("/v1/auth/status")).json() == {
        "setup_required": True, "setup_token_required": False}

    body = (await setup_owner(c)).json()
    assert body["user"]["email"] == "owner@example.com"
    assert body["user"]["display_name"] == "Alex"
    assert body["device"]["name"] == "iPhone d'Alex"
    assert body["device"]["platform"] == "ios"

    assert (await c.get("/v1/auth/status")).json()["setup_required"] is False
    r = await make_client().post("/v1/auth/setup", json={**OWNER, "email": "intrus@example.com"})
    assert r.status_code == 409


async def test_single_owner_is_enforced_by_database(clean_db, make_client):
    await setup_owner(make_client())
    conn = await asyncpg.connect(clean_db)
    try:
        with pytest.raises(asyncpg.UniqueViolationError):
            await conn.execute("INSERT INTO users(email, display_name, password_hash) "
                               "VALUES ('b@example.com','B','x')")
    finally:
        await conn.close()


async def test_setup_validates_password(clean_db, make_client):
    r = await make_client().post("/v1/auth/setup", json={**OWNER, "password": "court"})
    assert r.status_code == 422


async def test_setup_token_required_when_configured(clean_db, make_client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setenv("RAPHAEL_SETUP_TOKEN", "s3cret-token")
    get_settings.cache_clear()  # le réglage est lu à chaque requête via get_settings()
    c = make_client()
    assert (await c.get("/v1/auth/status")).json()["setup_token_required"] is True
    assert (await c.post("/v1/auth/setup", json=OWNER)).status_code == 403
    assert (await c.post("/v1/auth/setup", json={**OWNER, "setup_token": "faux"})).status_code == 403
    r = await c.post("/v1/auth/setup", json={**OWNER, "setup_token": "s3cret-token"})
    assert r.status_code == 201


async def test_password_and_session_token_are_never_stored_in_clear(clean_db, make_client):
    c = make_client()
    await setup_owner(c)
    token = c.cookies["raphael_session"]
    conn = await asyncpg.connect(clean_db)
    try:
        pw_hash = await conn.fetchval("SELECT password_hash FROM users")
        stored = await conn.fetchval("SELECT token_hash FROM sessions")
    finally:
        await conn.close()
    assert pw_hash.startswith("$argon2id$")
    assert OWNER["password"] not in pw_hash
    assert bytes(stored) == hashlib.sha256(token.encode()).digest()


async def test_session_cookie_flags(clean_db, make_client):
    r = await setup_owner(make_client())
    cookies = r.headers.get_list("set-cookie")
    session = next(h for h in cookies if h.startswith("raphael_session="))
    assert "HttpOnly" in session
    assert "SameSite=strict" in session
    # HTTPS derrière le mandataire → cookie Secure.
    c = make_client()
    await c.post("/v1/auth/logout")  # sans session : 401, sans effet
    r = await c.post("/v1/auth/login", json=LOGIN, headers={"x-forwarded-proto": "https"})
    assert "Secure" in next(h for h in r.headers.get_list("set-cookie")
                            if h.startswith("raphael_session="))


async def test_me_requires_valid_session(clean_db, make_client):
    c = make_client()
    assert (await c.get("/v1/auth/me")).status_code == 401
    await setup_owner(c)
    assert (await c.get("/v1/auth/me")).status_code == 200
    c.cookies.set("raphael_session", "jeton-invente")
    assert (await c.get("/v1/auth/me")).status_code == 401


async def test_login_logout(clean_db, make_client):
    await setup_owner(make_client())
    c = make_client()
    r = await c.post("/v1/auth/login", json={**LOGIN, "password": "mauvais mot de passe"})
    assert r.status_code == 401
    assert r.json()["detail"] == "Identifiants incorrects."
    r = await c.post("/v1/auth/login", json={**LOGIN, "email": "inconnu@example.com"})
    assert r.status_code == 401
    assert r.json()["detail"] == "Identifiants incorrects."  # ne révèle pas l'existence du compte

    r = await c.post("/v1/auth/login", json={**LOGIN, "device_name": "PC bureau", "platform": "windows"})
    assert r.status_code == 200
    assert r.json()["device"]["platform"] == "windows"
    assert (await c.get("/v1/auth/me")).status_code == 200

    assert (await c.post("/v1/auth/logout")).status_code == 204
    assert (await c.get("/v1/auth/me")).status_code == 401


async def test_login_rate_limited_after_repeated_failures(clean_db, make_client):
    await setup_owner(make_client())
    c = make_client()
    for _ in range(5):
        r = await c.post("/v1/auth/login", json={**LOGIN, "password": "mauvais mot de passe"})
        assert r.status_code == 401
    r = await c.post("/v1/auth/login", json=LOGIN)  # même le bon mot de passe est bloqué
    assert r.status_code == 429
    assert int(r.headers["retry-after"]) > 0

    conn = await asyncpg.connect(clean_db)
    try:
        failures = await conn.fetchval(
            "SELECT count(*) FROM audit_log WHERE action = 'auth.login_failed'")
    finally:
        await conn.close()
    assert failures == 5


async def test_devices_are_remembered_and_sessions_listed(clean_db, make_client):
    phone = make_client()
    await setup_owner(phone)
    phone_device = (await phone.get("/v1/auth/me")).json()["device"]["id"]

    # Reconnexion depuis le même navigateur : même appareil, nouvelle session.
    await phone.post("/v1/auth/logout")
    r = await phone.post("/v1/auth/login", json={**LOGIN, "device_name": "autre nom", "platform": "ios"})
    assert r.json()["device"]["id"] == phone_device

    laptop = make_client()
    r = await laptop.post("/v1/auth/login", json={**LOGIN, "device_name": "MacBook", "platform": "macos"})
    assert r.json()["device"]["id"] != phone_device

    sessions = (await laptop.get("/v1/auth/sessions")).json()
    assert len(sessions) == 2
    assert sessions[0]["current"] is True
    assert sessions[0]["device"]["name"] == "MacBook"
    assert {s["device"]["name"] for s in sessions} == {"MacBook", "iPhone d'Alex"}
    assert sessions[0]["ip"] == "127.0.0.1"


async def test_revoke_other_device(clean_db, make_client):
    phone = make_client()
    await setup_owner(phone)
    laptop = make_client()
    await laptop.post("/v1/auth/login", json=LOGIN)

    phone_session = (await phone.get("/v1/auth/me")).json()["session_id"]
    assert (await laptop.delete(f"/v1/auth/sessions/{phone_session}")).status_code == 204
    assert (await phone.get("/v1/auth/me")).status_code == 401
    assert (await laptop.get("/v1/auth/me")).status_code == 200
    assert (await laptop.delete(f"/v1/auth/sessions/{phone_session}")).status_code == 404


async def test_revoke_all_other_sessions(clean_db, make_client):
    main = make_client()
    await setup_owner(main)
    others = [make_client() for _ in range(3)]
    for o in others:
        await o.post("/v1/auth/login", json=LOGIN)
    r = await main.post("/v1/auth/sessions/revoke-others")
    assert r.json() == {"revoked": 3}
    for o in others:
        assert (await o.get("/v1/auth/me")).status_code == 401
    assert (await main.get("/v1/auth/me")).status_code == 200


async def test_revoke_unknown_session_is_404(clean_db, make_client):
    c = make_client()
    await setup_owner(c)
    r = await c.delete("/v1/auth/sessions/00000000-0000-0000-0000-000000000000")
    assert r.status_code == 404


async def test_rename_device(clean_db, make_client):
    c = make_client()
    body = (await setup_owner(c)).json()
    r = await c.patch(f"/v1/auth/devices/{body['device']['id']}", json={"name": "  iPhone   perso "})
    assert r.status_code == 200
    assert r.json()["name"] == "iPhone perso"
    r = await c.patch(f"/v1/auth/devices/{body['device']['id']}", json={"name": "   "})
    assert r.status_code == 422


async def test_cross_origin_writes_are_refused(clean_db, make_client):
    c = make_client()
    r = await c.post("/v1/auth/setup", json=OWNER, headers={"origin": "https://evil.example"})
    assert r.status_code == 403
    # Origine identique à l'hôte public transmis par le mandataire (Next.js) : autorisée.
    r = await c.post("/v1/auth/setup", json=OWNER, headers={
        "origin": "https://mon-codespace-3000.app.github.dev",
        "x-forwarded-host": "mon-codespace-3000.app.github.dev"})
    assert r.status_code == 201
    # Origine configurée (CORS) : autorisée.
    r = await c.post("/v1/auth/logout", headers={"origin": "http://localhost:3000"})
    assert r.status_code == 204


async def test_database_unavailable_returns_503(make_client, monkeypatch):
    from app.core import db

    monkeypatch.setattr(db, "_pool", None)
    r = await make_client().get("/v1/auth/status")
    assert r.status_code == 503
