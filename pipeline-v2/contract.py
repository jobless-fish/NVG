"""NODEVERSE common contract (pipeline side): event models, catalog and topic routing.

Source of truth: 'NODEVERSE 파이프라인 파트 구현 지시서' (2026-11-16), 공통 계약.
Any change here must also be made in the game and server instruction documents.
"""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from typing import Literal, Optional
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator, model_validator

from topics import (RETENTION_MS, TOPIC_BUNDLE, TOPIC_DLQ, TOPIC_LEARNING, TOPIC_RUNTIME,  # noqa: F401
                    TOPIC_UPDATE, TOPICS)

# ---------------------------------------------------------------- catalog
# scripts/learning_catalog.gd (game repo) : run ID -> category. 24 entries.
MINIGAME_CATEGORY = {
    "ST01": "DS", "ST02": "DS", "ST03": "DS", "ST04": "DS", "ST05": "DS",
    "DS09": "DS", "ST07": "DS", "ST08": "DS", "DS10": "DS", "ST10": "DS",
    "ALG02": "ALGO", "ALG01": "ALGO", "ALG03": "ALGO", "ST06": "ALGO", "ST09": "ALGO", "ALG04": "ALGO",
    "SQL01": "SQL", "SQL02": "SQL", "SQL03": "SQL", "SQL04": "SQL",
    "DATA02": "DATA", "DATA01": "DATA", "DATA03": "DATA", "DATA04": "DATA",
}
MinigameId = Literal[
    "ST01", "ST02", "ST03", "ST04", "ST05", "DS09", "ST07", "ST08", "DS10", "ST10",
    "ALG02", "ALG01", "ALG03", "ST06", "ST09", "ALG04",
    "SQL01", "SQL02", "SQL03", "SQL04", "DATA02", "DATA01", "DATA03", "DATA04",
]
Category = Literal["DS", "ALGO", "SQL", "DATA"]

LEARNING_TYPES = (
    "problem_started", "attempt_started", "operation_succeeded", "operation_failed",
    "hint_used", "attempt_succeeded", "attempt_failed", "problem_completed",
)
UPDATE_TYPES = (
    "update_checked", "update_prompted", "update_accepted", "update_dismissed",
    "pack_download_started", "pack_download_succeeded", "pack_download_failed",
    "pack_mounted", "build_changed",
)
RUNTIME_TYPES = (
    "run_started", "run_heartbeat", "exit_normal", "exit_crash_confirmed", "exit_forced_confirmed",
    "exit_unexpected_unknown", "exit_hang_suspected", "exit_connection_lost_suspected",
)

DETAILS_MAX_BYTES = 2048
FUTURE_TOLERANCE = timedelta(minutes=5)
# events older than this are refused with reason too_old (D20): it stays below the 7-day Kafka retention and
# Silver dedup state TTL, so every accepted resend is still remembered by the state store
MAX_EVENT_AGE = timedelta(days=6)


def is_too_old(ts: datetime, now: datetime) -> bool:
    return ts < now - MAX_EVENT_AGE
# UTC ISO-8601 with milliseconds: 2026-11-18T03:40:12.345Z (+00:00 also accepted)
_UTC_MS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(Z|\+00:00)$")
_SEMVER = r"^\d+\.\d+\.\d+$"

Short = Field(min_length=1, max_length=64)


def _check_utc_ms(value):
    if isinstance(value, str) and not _UTC_MS.match(value):
        raise ValueError("occurred_at must be UTC ISO-8601 with milliseconds, e.g. 2026-11-18T03:40:12.345Z")
    return value


def _check_details_size(details: BaseModel):
    raw = json.dumps(details.model_dump(mode="json", exclude_none=True), separators=(",", ":"))
    if len(raw.encode()) > DETAILS_MAX_BYTES:
        raise ValueError("details exceeds 2KB")


def _check_not_future(ts: datetime):
    if ts > datetime.now(timezone.utc) + FUTURE_TOLERANCE:
        raise ValueError("occurred_at is more than 5 minutes in the future")


# ---------------------------------------------------------------- learning v2
class LearningDetails(BaseModel):
    """Flat object, allowed keys only."""
    model_config = ConfigDict(extra="forbid")
    operation: Optional[str] = Field(default=None, max_length=64)
    failure_reason: Optional[str] = Field(default=None, max_length=64)
    level: Optional[int] = Field(default=None, ge=0, le=1000)
    moves: Optional[int] = Field(default=None, ge=0, le=1_000_000)
    mistakes: Optional[int] = Field(default=None, ge=0, le=1_000_000)
    stars: Optional[int] = Field(default=None, ge=0, le=3)
    hint_id: Optional[str] = Field(default=None, max_length=64)
    state_before: Optional[str] = Field(default=None, max_length=512)
    state_after: Optional[str] = Field(default=None, max_length=512)


class LearningEventV2(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal[2]
    event_id: UUID
    player_id: str = Field(min_length=1, max_length=128)
    session_id: UUID
    run_id: UUID
    attempt_id: Optional[UUID] = None  # D9: problem_started/problem_completed may have no attempt
    minigame_id: MinigameId
    category: Category
    build_version: str = Field(pattern=_SEMVER, max_length=32)
    content_version: str = Short
    event_type: Literal[LEARNING_TYPES]  # type: ignore[valid-type]
    occurred_at: AwareDatetime
    sequence: int = Field(ge=1)
    details: LearningDetails = Field(default_factory=LearningDetails)

    _utc = field_validator("occurred_at", mode="before")(_check_utc_ms)

    @model_validator(mode="after")
    def _rules(self):
        if MINIGAME_CATEGORY[self.minigame_id] != self.category:
            raise ValueError(f"category for {self.minigame_id} must be {MINIGAME_CATEGORY[self.minigame_id]}")
        _check_details_size(self.details)
        _check_not_future(self.occurred_at)
        return self


# ---------------------------------------------------------------- update v2
class UpdateDetails(BaseModel):
    model_config = ConfigDict(extra="forbid")
    target_version: Optional[str] = Field(default=None, max_length=64)
    result: Optional[Literal["up_to_date", "optional", "required", "offline"]] = None
    kind: Optional[Literal["required", "optional"]] = None
    failure_reason: Optional[Literal["network", "http_error", "hash_mismatch", "disk"]] = None
    bytes: Optional[int] = Field(default=None, ge=0)
    duration_ms: Optional[int] = Field(default=None, ge=0, le=86_400_000)
    from_version: Optional[str] = Field(default=None, max_length=64)


class UpdateEventV2(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal[2]
    event_id: UUID
    player_id: str = Field(min_length=1, max_length=128)
    run_id: UUID
    build_version: str = Field(pattern=_SEMVER, max_length=32)
    content_version: str = Short
    event_type: Literal[UPDATE_TYPES]  # type: ignore[valid-type]
    occurred_at: AwareDatetime
    details: UpdateDetails = Field(default_factory=UpdateDetails)

    _utc = field_validator("occurred_at", mode="before")(_check_utc_ms)

    @model_validator(mode="after")
    def _rules(self):
        d, t = self.details, self.event_type
        if t == "update_checked" and d.result is None:
            raise ValueError("update_checked requires details.result")
        if t == "update_prompted" and d.kind is None:
            raise ValueError("update_prompted requires details.kind")
        if t == "pack_download_failed" and d.failure_reason is None:
            raise ValueError("pack_download_failed requires details.failure_reason")
        if t == "build_changed" and d.from_version is None:
            raise ValueError("build_changed requires details.from_version")
        _check_details_size(d)
        _check_not_future(self.occurred_at)
        return self


# ---------------------------------------------------------------- runtime (launcher format, unchanged)
class RuntimeEvent(BaseModel):
    """Run/exit events exactly as the existing launcher sends them (schema_version 1)."""
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal[1] = 1
    event_id: UUID
    run_id: UUID
    player_id: str = Field(min_length=1, max_length=128)
    build_version: str = Field(min_length=1, max_length=64)
    event_type: Literal[RUNTIME_TYPES]  # type: ignore[valid-type]
    occurred_at: AwareDatetime
    evidence: Literal["launcher_observed", "next_launch_recovery", "game_shutdown_complete", "crash_report",
                      "user_confirmed", "watchdog", "server_timeout"]
    exit_code: Optional[int] = None
    session_id: Optional[str] = Field(default=None, max_length=128)
    problem_id: Optional[str] = Field(default=None, max_length=128)
    attempt_id: Optional[str] = Field(default=None, max_length=128)

    @model_validator(mode="after")
    def _evidence(self):
        _check_not_future(self.occurred_at)
        required = {"exit_normal": "game_shutdown_complete", "exit_crash_confirmed": "crash_report",
                    "exit_forced_confirmed": "user_confirmed", "exit_hang_suspected": "watchdog",
                    "exit_connection_lost_suspected": "server_timeout"}
        if self.event_type in required and self.evidence != required[self.event_type]:
            raise ValueError("Exit classification requires matching evidence")
        return self


# ---------------------------------------------------------------- routing
def route(event_type: object):
    """event_type -> (model, topic, key field). None when unknown."""
    if event_type in LEARNING_TYPES:
        return LearningEventV2, TOPIC_LEARNING, "session_id"
    if event_type in UPDATE_TYPES:
        return UpdateEventV2, TOPIC_UPDATE, "player_id"
    if event_type in RUNTIME_TYPES:
        return RuntimeEvent, TOPIC_RUNTIME, "run_id"
    return None


def body_hash(validated: dict) -> str:
    """processing.py rule: SHA-256 of sorted, compact JSON of the validated event (without received_at)."""
    clean = {k: v for k, v in validated.items() if k not in ("received_at", "payload_hash")}
    return hashlib.sha256(json.dumps(clean, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def to_record(model: BaseModel, received_at: datetime) -> dict:
    """Kafka value: validated fields + received_at + payload_hash (Silver uses it for id_conflict)."""
    validated = model.model_dump(mode="json", exclude_none=True)
    # keep the client's millisecond form of occurred_at instead of pydantic's microsecond form
    validated["occurred_at"] = model.occurred_at.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    record = dict(validated)
    record["payload_hash"] = body_hash(validated)
    record["received_at"] = received_at.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    return record
