from __future__ import annotations

import json
from typing import Any

from app.schemas import CreateWebsiteRequest, DeleteWebsiteRequest, NginxReloadRequest, PhpReloadRequest, SSLIssueRequest
from app.services.host_service import HostService

__all__ = ["CreateWebsiteRequest", "DeleteWebsiteRequest", "NginxReloadRequest", "PhpReloadRequest", "SSLIssueRequest", "HostService"]


app = {
    "title": "Rabby Host Agent",
    "version": "0.1.0",
}
