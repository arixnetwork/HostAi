from __future__ import annotations

import json
from typing import Any

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from app.routes.websites import router as sites_router

app = FastAPI(
    title="Rabby Host Agent",
    version="0.1.0",
    description="Privileged localhost-only management agent for hosting operations.",
)


@app.get("/health")
async def health() -> JSONResponse:
    return JSONResponse({
        "status": "ok",
        "service": "rabby-host-agent",
        "version": "0.1.0",
    })


app.include_router(sites_router)
