"""Configuration centralisée. Toutes les valeurs sensibles viennent de l'environnement
(fichier .env en développement) et ne sont jamais exposées au client."""
from functools import lru_cache

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="RAPHAEL_", extra="ignore")

    env: str = Field(default="development", pattern="^(development|test|production)$")
    database_url: str = "postgresql://raphael:raphael@localhost:5432/raphael"
    # Origine(s) du frontend autorisées par CORS (séparées par des virgules).
    cors_origins: str = "http://localhost:3000"
    # Dimension des embeddings : doit correspondre à la migration (vector(1024)).
    embedding_dim: int = 1024

    # ─── Authentification ───────────────────────────────────────────────
    # Durée de vie d'une session (jours). Révocable à tout moment depuis Paramètres.
    session_ttl_days: int = Field(default=30, ge=1, le=365)
    # Si défini, la création du compte propriétaire exige ce jeton : à utiliser dès que
    # l'instance est accessible publiquement avant la première configuration.
    setup_token: SecretStr | None = None
    # Mandataires de confiance (le serveur Next.js en local) dont on lit X-Forwarded-For.
    trusted_proxies: str = "127.0.0.1,::1"
    # Limitation de débit de la connexion : N échecs par fenêtre (secondes).
    login_max_failures: int = 5
    login_window_seconds: int = 900

    # Clés des fournisseurs IA — utilisées à partir des phases 3 à 5.
    llm_api_key: SecretStr | None = None
    embedding_api_key: SecretStr | None = None
    voice_api_key: SecretStr | None = None

    @field_validator("setup_token", "llm_api_key", "embedding_api_key", "voice_api_key", mode="before")
    @classmethod
    def _empty_is_none(cls, v: object) -> object:
        # « RAPHAEL_SETUP_TOKEN= » (vide) dans .env signifie « non défini ».
        return None if isinstance(v, str) and not v.strip() else v

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def trusted_proxy_list(self) -> set[str]:
        return {p.strip() for p in self.trusted_proxies.split(",") if p.strip()}

    @property
    def is_production(self) -> bool:
        return self.env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
