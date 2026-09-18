from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
from typing import Any

from fastapi import HTTPException, Request, status

_AGENT_SECRET = os.getenv("AGENT_SECRET", "dev-agent-secret-change-me")
_NONCES: set[str] = set()


def _canonical_payload(data: bytes) -> bytes:
    return data if data else b"{}"


def sign_payload(payload: bytes, timestamp: str, nonce: str, secret: str = _AGENT_SECRET) -> str:
    message = payload + b"|" + timestamp.encode("utf-8") + b"|" + nonce.encode("utf-8")
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def _is_valid_nonce(nonce: str) -> bool:
    if not nonce or len(nonce) < 8:
        return False
    if nonce in _NONCES:
        return False
    _NONCES.add(nonce)
    return True


async def verify_signed_request(request: Request) -> dict[str, Any]:
    body = await request.body()
    signature = request.headers.get("x-signature")
    timestamp = request.headers.get("x-timestamp")
    nonce = request.headers.get("x-nonce")

    if not signature or not timestamp or not nonce:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing signed request headers")

    try:
        timestamp_value = int(timestamp)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid timestamp") from exc

    if abs(time.time() - timestamp_value) > 300:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Signed request expired")

    if not _is_valid_nonce(nonce):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Replay detected or invalid nonce")

    expected = sign_payload(_canonical_payload(body), timestamp, nonce, _AGENT_SECRET)
    if not hmac.compare_digest(signature, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature")

    try:
        return json.loads(body.decode("utf-8")) if body else {}
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Request body must be valid JSON") from exc
