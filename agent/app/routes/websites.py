from __future__ import annotations

import os
import re
from typing import Any

from fastapi import APIRouter, HTTPException, Request, status

from app.schemas import (
    CreateWebsiteRequest,
    DeleteWebsiteRequest,
    NginxReloadRequest,
    PhpReloadRequest,
    SSLIssueRequest,
)
from app.security import verify_signed_request

router = APIRouter(prefix="/agent", tags=["agent"])


class HostService:
    @staticmethod
    def validate_allowed_root(root_path: str) -> str:
        allowed_root = os.getenv("ALLOWED_FILE_ROOT", "/var/www")
        if not root_path.startswith(allowed_root):
            raise ValueError(f"root_path must start with {allowed_root}")
        return root_path

    @staticmethod
    def validate_domain(domain: str) -> str:
        if not re.match(r"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$", domain.lower()):
            raise ValueError(f"invalid domain: {domain}")
        return domain.lower()

    @staticmethod
    def make_task_id(prefix: str) -> str:
        import uuid
        return f"{prefix}-{uuid.uuid4().hex[:12]}"


@router.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "service": "rabby-host-agent"}


@router.post("/websites/create")
async def create_website(request: Request) -> dict[str, Any]:
    payload = await verify_signed_request(request)
    data = CreateWebsiteRequest(**payload)
    try:
        validated_root = HostService.validate_allowed_root(data.root_path)
        validated_domain = HostService.validate_domain(data.domain)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return {
        "status": "accepted",
        "task_id": HostService.make_task_id("site-create"),
        "message": "website creation accepted for review",
        "site": {
            "site_name": data.site_name,
            "domain": validated_domain,
            "root_path": validated_root,
            "php_version": data.php_version,
            "owner": data.owner,
        },
    }


@router.post("/websites/delete")
async def delete_website(request: Request) -> dict[str, Any]:
    payload = await verify_signed_request(request)
    data = DeleteWebsiteRequest(**payload)
    if not data.confirm:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="confirm must be true")

    return {
        "status": "accepted",
        "task_id": HostService.make_task_id("site-delete"),
        "message": "website deletion accepted",
        "site_name": data.site_name,
    }


@router.post("/nginx/reload")
async def nginx_reload(request: Request) -> dict[str, Any]:
    payload = await verify_signed_request(request)
    data = NginxReloadRequest(**payload)
    return {
        "status": "accepted",
        "task_id": HostService.make_task_id("nginx-reload"),
        "message": "nginx reload scheduled",
        "reason": data.reason,
    }


@router.post("/php/reload")
async def php_reload(request: Request) -> dict[str, Any]:
    payload = await verify_signed_request(request)
    data = PhpReloadRequest(**payload)
    return {
        "status": "accepted",
        "task_id": HostService.make_task_id("php-reload"),
        "message": "php-fpm reload scheduled",
        "php_version": data.php_version,
    }


@router.post("/ssl/issue")
async def ssl_issue(request: Request) -> dict[str, Any]:
    payload = await verify_signed_request(request)
    data = SSLIssueRequest(**payload)
    try:
        HostService.validate_domain(data.domain)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return {
        "status": "accepted",
        "task_id": HostService.make_task_id("ssl-issue"),
        "message": "certificate issuance queued",
        "domain": data.domain,
        "email": data.email,
    }
