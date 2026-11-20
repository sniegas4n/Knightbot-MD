from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

Platform = Literal["ios", "ipados", "android", "windows", "macos", "linux", "web"]


class DeviceInfo(BaseModel):
    """Description de l'appareil envoyée par le client à la connexion."""

    device_name: str = Field(default="Navigateur", min_length=1, max_length=60)
    platform: Platform = "web"

    @field_validator("device_name")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("Nom d'appareil vide.")
        return v


class SetupRequest(DeviceInfo):
    email: EmailStr
    display_name: str = Field(min_length=1, max_length=60)
    password: str = Field(min_length=12, max_length=256)
    setup_token: str | None = Field(default=None, max_length=256)


class LoginRequest(DeviceInfo):
    email: EmailStr
    password: str = Field(min_length=1, max_length=256)


class AuthStatus(BaseModel):
    setup_required: bool
    setup_token_required: bool


class UserOut(BaseModel):
    id: UUID
    email: str
    display_name: str
    locale: str
    timezone: str


class DeviceOut(BaseModel):
    id: UUID
    name: str
    platform: Platform


class MeResponse(BaseModel):
    user: UserOut
    session_id: UUID
    device: DeviceOut | None


class SessionOut(BaseModel):
    id: UUID
    device: DeviceOut | None
    ip: str | None
    user_agent: str | None
    created_at: datetime
    last_seen_at: datetime
    expires_at: datetime
    current: bool


class RenameDevice(BaseModel):
    name: str = Field(min_length=1, max_length=60)

    @field_validator("name")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("Nom d'appareil vide.")
        return v


class RevokedCount(BaseModel):
    revoked: int
