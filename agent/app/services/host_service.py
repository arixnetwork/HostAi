from __future__ import annotations

import os
import re
from typing import Any


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
