"""Durable, idempotent export staging after Silver validation."""
from datetime import datetime, timezone, date
from pymongo import MongoClient
import os

_client = None

def local_db():
    global _client
    if _client is None:
        _client = MongoClient(os.getenv("MONGO_URI", "mongodb://mongo:27017"), serverSelectionTimeoutMS=5000)
    return _client[os.getenv("MONGO_DB", "nodeverse_logs")]

def plain(value):
    if isinstance(value, datetime):
        return value.replace(tzinfo=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: plain(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [plain(v) for v in value]
    return value

def stage(records, db=None):
    db = db if db is not None else local_db()
    for record in records:
        body = plain(record)
        ident = body["event_id"]
        payload_hash = body["payload_hash"]
        old = db.remote_event_outbox.find_one({"_id": ident}, {"payload_hash": 1})
        if old and old.get("payload_hash") != payload_hash:
            db.remote_export_conflicts.update_one({"_id": ident + ":" + payload_hash}, {"$setOnInsert": {
                "event_id": ident, "reason": "event_id_conflict", "detected_at": datetime.now(timezone.utc)}}, upsert=True)
            continue
        now = datetime.now(timezone.utc)
        db.remote_event_outbox.update_one({"_id": ident}, {"$setOnInsert": {
            "payload_hash": payload_hash, "event": body, "state": "pending", "attempts": 0,
            "queued_at": now, "next_attempt_at": now, "sequence": body.get("sequence", 0),
            "source_session_id": body.get("session_id"), "occurred_at": body["occurred_at"]}}, upsert=True)
