"""Informations fiables sur la requête : IP du client et vérification d'origine (CSRF).

Le navigateur parle à Next.js, qui relaie /v1/* vers l'API sur 127.0.0.1. L'adresse vue par
l'API est donc celle du mandataire : on lit X-Forwarded-For / X-Forwarded-Host uniquement
quand la connexion vient d'un mandataire de confiance (configuration `trusted_proxies`).
"""
from ipaddress import ip_address
from urllib.parse import urlsplit

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.config import get_settings

UNSAFE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def _from_trusted_proxy(request: Request) -> bool:
    peer = request.client.host if request.client else None
    return peer is not None and peer in get_settings().trusted_proxy_list


def client_ip(request: Request) -> str | None:
    """IP réelle du client, ou None si elle n'est pas une adresse valide."""
    candidate = request.client.host if request.client else None
    if _from_trusted_proxy(request):
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            # Le dernier saut ajouté par le mandataire de confiance est le plus fiable.
            candidate = forwarded.split(",")[-1].strip()
    try:
        return str(ip_address(candidate)) if candidate else None
    except ValueError:
        return None


def _public_host(request: Request) -> str | None:
    if _from_trusted_proxy(request):
        fwd = request.headers.get("x-forwarded-host")
        if fwd:
            return fwd.split(",")[0].strip().lower()
    host = request.headers.get("host")
    return host.lower() if host else None


def origin_allowed(request: Request) -> bool:
    origin = request.headers.get("origin")
    if origin is None:
        # Pas d'Origin : client non-navigateur (curl, tests). Les navigateurs modernes
        # envoient toujours Origin sur les requêtes modifiantes ; le cookie SameSite=Strict
        # couvre les autres cas.
        return True
    if origin in get_settings().cors_origin_list:
        return True
    parts = urlsplit(origin)
    return bool(parts.netloc) and parts.netloc.lower() == _public_host(request)


class OriginCheckMiddleware(BaseHTTPMiddleware):
    """Refuse les requêtes modifiantes venant d'une autre origine (protection CSRF)."""

    async def dispatch(self, request: Request, call_next) -> Response:
        if request.method in UNSAFE_METHODS and not origin_allowed(request):
            return JSONResponse({"detail": "Origine non autorisée."}, status_code=403)
        return await call_next(request)
