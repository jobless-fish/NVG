"""Authenticated compatibility forwarding; only fixed v2 routes, never an open proxy."""
import os
import secrets
import urllib.request
import urllib.error
from urllib.parse import urlsplit
from uuid import UUID
from fastapi import APIRouter, Header, HTTPException, Request
from fastapi.responses import Response
from fastapi.concurrency import run_in_threadpool

router = APIRouter()
LIMIT = 16 * 1024

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

def authenticate(value):
    expected = os.getenv("INGEST_KEY", "")
    if not expected or not secrets.compare_digest(value.encode(), expected.encode()):
        raise HTTPException(401, "Invalid ingestion key")

def forward(path, data=None, authenticated=True):
    origin = os.getenv("V2_COLLECTOR_URL", "").rstrip("/")
    u = urlsplit(origin)
    if u.scheme not in ("http", "https") or not u.hostname or u.username or u.password or u.path or u.query or u.fragment:
        raise HTTPException(503, "v2 collector is not configured")
    headers = {"Content-Type": "application/json"}
    if authenticated:
        key = os.getenv("V2_INGEST_KEY", "")
        if not key:
            raise HTTPException(503, "v2 upstream authentication is not configured")
        headers["X-API-Key"] = key
    req = urllib.request.Request(origin + path, data=data, headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=18) as response:
            return Response(response.read(), status_code=response.status, media_type="application/json")
    except urllib.error.HTTPError as e:
        return Response(e.read(), status_code=e.code, media_type="application/json")
    except (OSError, TimeoutError):
        raise HTTPException(503, "v2 unavailable; retry identical event_id and body")

@router.post("/v2/events", status_code=202)
async def events(request: Request, x_api_key: str = Header(default="")):
    authenticate(x_api_key)
    body = bytearray()
    async for part in request.stream():
        body.extend(part)
        if len(body) > LIMIT:
            raise HTTPException(413, "Body exceeds 16KiB")
    return await run_in_threadpool(forward, "/v2/events", bytes(body))

@router.get("/v2/events/{event_id}")
def delivery(event_id: UUID, x_api_key: str = Header(default="")):
    authenticate(x_api_key)
    return forward("/v2/events/" + str(event_id))

@router.get("/health/v2")
def readiness():
    return forward("/health/ready", authenticated=False)
