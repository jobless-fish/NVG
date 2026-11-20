"""NODEVERSE ingestion API (P1, P4-2).

POST /v2/events  single event, header X-API-Key, 202 = persisted in Kafka.
  - learning (8 types)  -> nv.learning.v2  key session_id
  - update   (9 types)  -> nv.update.v1    key player_id
  - runtime  (run_*/exit_*, launcher format) -> nv.runtime.v1 key run_id
  - anything that fails validation -> 422 and one record in nv.dlq.v1
POST /v1/events  kept for the existing launcher: runtime events only (same routing).
"""
from __future__ import annotations

import json
import os
import secrets
import threading
from datetime import datetime, timezone
from uuid import UUID

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from pydantic import ValidationError

import contract

MAX_BODY_BYTES = 16 * 1024
DLQ_RAW_BYTES = 4096

app = FastAPI(title="NODEVERSE ingestion API")
_producer = None
_lock = threading.Lock()


def producer():
    global _producer
    with _lock:
        if _producer is None:
            from confluent_kafka import Producer
            _producer = Producer({
                "bootstrap.servers": os.getenv("KAFKA_BOOTSTRAP", "kafka-1:9092,kafka-2:9092,kafka-3:9092"),
                "enable.idempotence": True, "acks": "all",
                "delivery.timeout.ms": 10000, "linger.ms": 5,
            })
            # one poller serves delivery callbacks for all concurrent requests
            threading.Thread(target=_poll_forever, args=(_producer,), daemon=True).start()
        return _producer


def _poll_forever(p):
    while True:
        p.poll(0.05)


def send(topic: str, key: str | None, value: dict, timeout: float = 12.0) -> None:
    """Produce one record and block until the broker acknowledges it (acks=all). Raises on failure."""
    p = producer()
    done = threading.Event()
    result: list = []

    def on_delivery(err, msg):
        result.append(err)
        done.set()

    p.produce(topic, key=key, value=json.dumps(value, separators=(",", ":")), on_delivery=on_delivery)
    if not done.wait(timeout) or result[0] is not None:
        raise RuntimeError(f"Kafka delivery failed: {result[0] if result else 'timeout'}")


def send_dlq(raw: bytes, reason: str, errors: list, endpoint: str, key: str | None) -> bool:
    record = {
        "reason": reason,
        "errors": errors[:20],
        "endpoint": endpoint,
        "received_at": now_iso(),
        "raw_truncated": len(raw) > DLQ_RAW_BYTES,
        "raw": raw[:DLQ_RAW_BYTES].decode("utf-8", errors="replace"),
    }
    try:
        send(contract.TOPIC_DLQ, key, record, timeout=5.0)
        return True
    except Exception:
        return False


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def check_key(x_api_key: str) -> None:
    expected = os.getenv("INGEST_KEY", "")
    if len(expected) < 24 or not secrets.compare_digest(x_api_key.encode(), expected.encode()):
        raise HTTPException(401, "Invalid ingestion key")


def _short_errors(exc: ValidationError) -> list:
    return [{"loc": ".".join(str(p) for p in e["loc"]), "msg": e["msg"]} for e in exc.errors()]


async def reject(raw: bytes, reason: str, errors: list, endpoint: str, key: str | None):
    stored = await run_in_threadpool(send_dlq, raw, reason, errors, endpoint, key)
    return JSONResponse(status_code=422, content={"detail": errors, "reason": reason, "dlq": stored})


async def _ingest(request: Request, endpoint: str, allowed_types: tuple | None):
    raw = await request.body()
    if len(raw) > MAX_BODY_BYTES:
        raise HTTPException(413, "Body exceeds 16KiB")
    try:
        body = json.loads(raw)
    except (ValueError, UnicodeDecodeError) as exc:
        return await reject(raw, "invalid_json", [{"loc": "", "msg": str(exc)[:200]}], endpoint, None)
    if not isinstance(body, dict):
        return await reject(raw, "invalid_json", [{"loc": "", "msg": "body must be a JSON object"}], endpoint, None)

    dlq_key = str(body.get("event_id")) if body.get("event_id") is not None else None
    event_type = body.get("event_type")
    routed = contract.route(event_type)
    if routed is None or (allowed_types is not None and event_type not in allowed_types):
        return await reject(raw, "unknown_event_type", [{"loc": "event_type", "msg": f"unsupported: {event_type!r}"}],
                      endpoint, dlq_key)
    model_cls, topic, key_field = routed
    try:
        event = model_cls.model_validate(body)
    except ValidationError as exc:
        return await reject(raw, "schema_error", _short_errors(exc), endpoint, dlq_key)

    now = datetime.now(timezone.utc)
    if contract.is_too_old(event.occurred_at, now):
        return await reject(raw, "too_old", [{"loc": "occurred_at",
                                              "msg": "occurred_at is more than 6 days old; do not resend"}],
                            endpoint, dlq_key)
    record = contract.to_record(event, now)
    try:
        await run_in_threadpool(send, topic, str(record[key_field]), record)
    except Exception:
        raise HTTPException(503, "Kafka unavailable; retry the same event_id and body")
    return JSONResponse(status_code=202, content={"event_id": record["event_id"], "status": "accepted", "topic": topic})


@app.get("/health/live")
def live():
    return {"status": "ok"}


@app.get("/health/ready")
def ready():
    try:
        producer().list_topics(timeout=3)
    except Exception:
        raise HTTPException(503, "Kafka unavailable")
    return {"status": "ready"}


@app.post("/v2/events", status_code=202)
async def ingest_v2(request: Request, x_api_key: str = Header(default="")):
    check_key(x_api_key)
    return await _ingest(request, "/v2/events", None)


@app.post("/v1/events", status_code=202)
async def ingest_v1(request: Request, x_api_key: str = Header(default="")):
    """Kept until the transition ends: existing launcher runtime events only."""
    check_key(x_api_key)
    return await _ingest(request, "/v1/events", contract.RUNTIME_TYPES)


@app.get("/v2/events/{event_id}")
def remote_delivery(event_id: UUID, x_api_key: str = Header(default="")):
    check_key(x_api_key)
    from remote.outbox import local_db
    row = local_db().remote_event_outbox.find_one({"_id": str(event_id)}, {
        "state": 1, "reason": 1, "attempts": 1, "updated_at": 1, "archive_stored": 1, "result": 1})
    if not row:
        return {"event_id": str(event_id), "state": "not_staged", "meaning": "awaiting Silver/export; not a delivery confirmation"}
    row["event_id"] = row.pop("_id")
    return row
