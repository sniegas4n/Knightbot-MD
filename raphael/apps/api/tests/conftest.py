import os

import asyncpg
import pytest
from httpx import ASGITransport, AsyncClient

from app.core import db
from app.core.config import get_settings

# Base de test dédiée ; si elle est absente, les tests base de données sont ignorés.
TEST_DSN = os.environ.get("RAPHAEL_TEST_DATABASE_URL")


@pytest.fixture
def test_dsn() -> str:
    if not TEST_DSN:
        pytest.skip("RAPHAEL_TEST_DATABASE_URL non défini")
    return TEST_DSN


@pytest.fixture
async def clean_db(test_dsn):
    """Base migrée et vidée (aucun compte), pool de l'application connecté dessus."""
    from scripts.migrate import migrate

    await migrate(test_dsn)
    conn = await asyncpg.connect(test_dsn)
    try:
        await conn.execute("TRUNCATE users, audit_log CASCADE")
    finally:
        await conn.close()
    await db.connect(test_dsn)
    yield test_dsn
    await db.disconnect()


@pytest.fixture
async def make_client():
    """Fabrique de clients HTTP : chaque client = un navigateur distinct (ses propres cookies)."""
    from app.main import create_app

    get_settings.cache_clear()
    app = create_app()
    clients: list[AsyncClient] = []

    def _make() -> AsyncClient:
        c = AsyncClient(transport=ASGITransport(app=app), base_url="http://t")
        clients.append(c)
        return c

    yield _make
    for c in clients:
        await c.aclose()
    get_settings.cache_clear()
