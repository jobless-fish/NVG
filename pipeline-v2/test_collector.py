"""Unit tests for POST /v2/events and /v1/events (Kafka replaced by an in-memory sink)."""
import json
import os
import random
import uuid
from datetime import datetime, timedelta, timezone

import pytest

os.environ["INGEST_KEY"] = "test-key-at-least-24-characters!!"
from fastapi.testclient import TestClient  # noqa: E402

import collector  # noqa: E402
import contract  # noqa: E402
from simulator import Session, ts, update_flow  # noqa: E402

client = TestClient(collector.app)
HEAD = {"X-API-Key": os.environ["INGEST_KEY"]}


@pytest.fixture
def sink(monkeypatch):
    sent = []
    monkeypatch.setattr(collector, "send", lambda topic, key, value, timeout=12.0: sent.append((topic, key, value)))
    return sent


def learning(event_type="operation_failed", **details):
    s = Session("unit", "install-1", "ST04", 0, random.Random(1))
    return s.event(event_type, **(details or {"operation": "push", "failure_reason": "queue_full", "moves": 14}))


def post(body, headers=HEAD):
    data = body if isinstance(body, (bytes, str)) else json.dumps(body)
    return client.post("/v2/events", content=data, headers={**headers, "Content-Type": "application/json"})


def test_learning_202_to_learning_topic(sink):
    e = learning()
    r = post(e)
    assert r.status_code == 202, r.text
    topic, key, value = sink[0]
    assert topic == "nv.learning.v2" and key == e["session_id"]
    assert value["received_at"].endswith("Z") and len(value["payload_hash"]) == 64
    assert value["occurred_at"] == e["occurred_at"]
    assert value["details"] == e["details"]


def test_same_body_same_hash_different_body_different_hash(sink):
    e = learning()
    post(e), post(e)
    post(dict(e, details=dict(e["details"], moves=15)))
    hashes = [v["payload_hash"] for _, _, v in sink]
    assert hashes[0] == hashes[1] != hashes[2]


def test_extra_detail_key_422_and_one_dlq(sink):
    e = learning()
    e["details"]["secret"] = 1
    r = post(e)
    assert r.status_code == 422 and r.json()["dlq"] is True
    assert len(sink) == 1 and sink[0][0] == "nv.dlq.v1" and sink[0][1] == e["event_id"]
    assert sink[0][2]["reason"] == "schema_error" and "secret" in sink[0][2]["raw"]


def test_extra_top_level_key_422(sink):
    r = post(dict(learning(), user_id="admin"))
    assert r.status_code == 422 and sink[0][0] == "nv.dlq.v1"


@pytest.mark.parametrize("change", [
    {"category": "SQL"},                       # ST04 is DS
    {"minigame_id": "ST99"},
    {"sequence": 0},
    {"schema_version": 1},
    {"occurred_at": "2026-11-18T03:40:12Z"},   # no milliseconds
    {"occurred_at": "2026-11-18T12:40:12.345+09:00"},  # not UTC
    {"build_version": "v0.3"},
    {"session_id": "not-a-uuid"},
])
def test_contract_violations_422(sink, change):
    assert post(dict(learning(), **change)).status_code == 422


def test_future_event_422(sink):
    future = datetime.now(timezone.utc) + timedelta(minutes=10)
    assert post(dict(learning(), occurred_at=ts(future))).status_code == 422


def test_too_old_event_422_dlq(sink):
    old = datetime.now(timezone.utc) - timedelta(days=6, minutes=1)
    e = dict(learning(), occurred_at=ts(old))
    r = post(e)
    assert r.status_code == 422 and r.json()["reason"] == "too_old" and r.json()["dlq"] is True
    assert len(sink) == 1 and sink[0][0] == "nv.dlq.v1" and sink[0][2]["reason"] == "too_old"


def test_five_day_old_event_accepted(sink):
    e = dict(learning(), occurred_at=ts(datetime.now(timezone.utc) - timedelta(days=5)))
    assert post(e).status_code == 202


def test_details_long_values_within_limit(sink):
    e = learning("operation_succeeded", operation="x", state_before="a" * 512, state_after="b" * 512)
    assert post(e).status_code == 202
    # 2KB limit: allowed keys only, so build an oversize object via several long strings
    big = learning("operation_succeeded", operation="o" * 64, failure_reason="f" * 64, hint_id="h" * 64,
                   state_before="a" * 512, state_after="b" * 512)
    assert post(big).status_code == 202  # still under 2KB
    assert len(json.dumps(big["details"])) < 2048


def test_invalid_json_422_dlq(sink):
    r = post(b"{not json")
    assert r.status_code == 422 and r.json()["reason"] == "invalid_json"
    assert sink[0][0] == "nv.dlq.v1" and sink[0][1] is None


def test_unknown_event_type_422(sink):
    r = post(dict(learning(), event_type="operation"))
    assert r.status_code == 422 and r.json()["reason"] == "unknown_event_type"


def test_update_event_routed_to_update_topic(sink):
    for e in update_flow("unit", "install-9", random.Random(2), fail_reason="hash_mismatch"):
        assert post(e).status_code == 202, (e["event_type"], post(e).text)
    topics = {t for t, _, _ in sink}
    assert topics == {"nv.update.v1"} and all(k == "install-9" for _, k, _ in sink)


def test_update_rules(sink):
    e = update_flow("unit", "install-9", random.Random(2))[0]  # update_checked
    assert post(dict(e, details={"target_version": "content-2026.11.19"})).status_code == 422  # result missing
    assert post(dict(e, details={"result": "maybe"})).status_code == 422
    assert post(dict(e, details={"result": "offline", "operation": "x"})).status_code == 422  # learning key


def test_runtime_event_v2_and_v1(sink):
    rt = {"schema_version": 1, "event_id": str(uuid.uuid4()), "run_id": str(uuid.uuid4()), "player_id": "install-1",
          "build_version": "0.3.0", "event_type": "run_heartbeat",
          "occurred_at": datetime.now(timezone.utc).isoformat(), "evidence": "launcher_observed"}
    assert post(rt).status_code == 202
    assert client.post("/v1/events", json=rt, headers=HEAD).status_code == 202
    assert [t for t, _, _ in sink] == ["nv.runtime.v1", "nv.runtime.v1"] and sink[0][1] == rt["run_id"]
    bad = dict(rt, event_type="exit_normal", evidence="launcher_observed")
    assert post(bad).status_code == 422


def test_v1_rejects_learning(sink):
    assert client.post("/v1/events", json=learning(), headers=HEAD).status_code == 422


def test_auth(sink):
    assert post(learning(), headers={"X-API-Key": "wrong"}).status_code == 401
    assert post(learning(), headers={}).status_code == 401
    assert sink == []


def test_kafka_down_503(monkeypatch):
    def fail(*a, **k):
        raise RuntimeError("offline")
    monkeypatch.setattr(collector, "send", fail)
    assert post(learning()).status_code == 503


def test_body_limit(sink):
    assert post(b"{" + b" " * 20000 + b"}").status_code == 413


def test_catalog_has_24_games():
    assert len(contract.MINIGAME_CATEGORY) == 24
    assert set(contract.MINIGAME_CATEGORY.values()) == {"DS", "ALGO", "SQL", "DATA"}


def test_simulator_events_are_valid():
    rng = random.Random(5)
    for game in contract.MINIGAME_CATEGORY:
        for e in Session("unit", "p", game, 0, rng).script():
            contract.LearningEventV2.model_validate(e)
    for e in update_flow("unit", "p", rng):
        contract.UpdateEventV2.model_validate(e)


def test_runtime_future_timestamp_rejected_before_runtime_topic(sink):
    event = {"schema_version": 1, "event_id": str(uuid.uuid4()), "run_id": str(uuid.uuid4()),
             "player_id": "future-runtime", "build_version": "0.3.0", "event_type": "run_started",
             "occurred_at": (datetime.now(timezone.utc) + timedelta(minutes=6)).isoformat(),
             "evidence": "launcher_observed"}
    response = post(event)
    assert response.status_code == 422
    assert response.json()["reason"] == "schema_error"
    assert all(topic != contract.TOPIC_RUNTIME for topic, _, _ in sink)
