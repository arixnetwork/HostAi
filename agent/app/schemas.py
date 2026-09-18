from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator


class WebsiteActionResult(BaseModel):
    status: Literal["accepted", "error"] = "accepted"
    message: str
    task_id: str | None = None


class CreateWebsiteRequest(BaseModel):
    site_name: str = Field(..., min_length=3, max_length=63)
    domain: str = Field(..., min_length=3, max_length=253)
    root_path: str = Field(..., min_length=1, max_length=255)
    php_version: str = Field(default="8.2")
    owner: str = Field(default="default")

    @field_validator("site_name")
    @classmethod
    def validate_site_name(cls, value: str) -> str:
        cleaned = value.strip().lower()
        if not cleaned.replace("-", "").replace("_", "").isalnum():
            raise ValueError("site_name may only contain letters, numbers, hyphen, and underscore")
        return cleaned

    @field_validator("domain")
    @classmethod
    def validate_domain(cls, value: str) -> str:
        cleaned = value.strip().lower()
        if not cleaned or cleaned.startswith("."):
            raise ValueError("domain is invalid")
        return cleaned

    @field_validator("root_path")
    @classmethod
    def validate_root_path(cls, value: str) -> str:
        cleaned = value.strip()
        if cleaned.startswith("/"):
            return cleaned
        raise ValueError("root_path must be an absolute filesystem path")


class DeleteWebsiteRequest(BaseModel):
    site_name: str = Field(..., min_length=3, max_length=63)
    confirm: bool = False


class NginxReloadRequest(BaseModel):
    reason: str = Field(default="manual")


class PhpReloadRequest(BaseModel):
    php_version: str = Field(default="8.2")


class SSLIssueRequest(BaseModel):
    domain: str = Field(..., min_length=3, max_length=253)
    email: str = Field(..., min_length=5, max_length=255)


class ServiceEnvelope(BaseModel):
    status: Literal["accepted"] = "accepted"
    task_id: str
    message: str
