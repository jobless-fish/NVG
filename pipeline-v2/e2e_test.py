"""Real HTTP integration sender. Saves immutable fixtures; no game/server code changes.
Run with .venv/Scripts/python e2e_test.py. Final storage is checked separately by review_verify.py.
"""
import argparse
import copy
from datetime import datetime, timedelta, timezone
import json
import random
from pathlib import Path
import uuid
import time
import urllib.request
import urllib.error

import contract
from check import settings
from simulator import Session, send_all, post, ts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8002")
    parser.add_argument("--run-id", default="e2e-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S"))
    args = parser.parse_args()
    key = settings(Path(__file__).with_name(".env")).get("INGEST_KEY", "")
    if len(key) < 24:
        parser.error("configure INGEST_KEY")
    deadline = time.monotonic() + 45
    while True:
        try:
            with urllib.request.urlopen(args.url.rstrip("/") + "/health/ready", timeout=3) as response:
                if response.status == 200:
                    break
        except (OSError, urllib.error.URLError):
            pass
        if time.monotonic() >= deadline:
            parser.error("collector not ready; no fixture sent")
        time.sleep(1)
    folder = Path("results") / args.run_id
    folder.mkdir(parents=True, exist_ok=True)
    fixture = folder / "events.json"
    if fixture.exists():
        parser.error("run-id already exists; choose a fresh ID to preserve evidence")
    rng = random.Random(args.run_id)
    events = []
    for n, game in enumerate(contract.MINIGAME_CATEGORY):
        events.extend(Session(args.run_id, "test-" + args.run_id + "-" + str(n), game, n, rng).script())
    for kind in contract.UPDATE_TYPES:
        events.append({"schema_version": 2, "event_id": str(uuid.uuid4()), "player_id": "test-" + args.run_id,
                       "run_id": str(uuid.uuid4()), "build_version": "0.3.0", "content_version": "base",
                       "event_type": kind, "occurred_at": ts(), "details": {
                           "target_version": "e2e-content", "result": "optional", "kind": "optional",
                           "failure_reason": "hash_mismatch", "from_version": "0.2.0", "duration_ms": 1000}})
    evidence = {"exit_normal": "game_shutdown_complete", "exit_crash_confirmed": "crash_report",
                "exit_forced_confirmed": "user_confirmed", "exit_hang_suspected": "watchdog",
                "exit_connection_lost_suspected": "server_timeout"}
    for kind in contract.RUNTIME_TYPES:
        events.append({"schema_version": 1, "event_id": str(uuid.uuid4()), "run_id": str(uuid.uuid4()),
                       "player_id": "test-" + args.run_id, "build_version": "0.3.0", "event_type": kind,
                       "occurred_at": ts(), "evidence": evidence.get(kind, "launcher_observed")})
    fixture.write_text(json.dumps(events, indent=2), encoding="utf-8")
    expected = []
    for e in events:
        model, topic, _ = contract.route(e["event_type"])
        record = contract.to_record(model.model_validate(e), datetime.now(timezone.utc))
        expected.append({"event_id": e["event_id"], "topic": topic, "payload_hash": record["payload_hash"]})
    first = events[0]
    expected_path = folder / "expected.json"
    expected_path.write_text(json.dumps({"run_id": args.run_id, "events": expected,
                                        "conflict_event_id": first["event_id"]}, indent=2), encoding="utf-8")
    initial = send_all(args.url, key, events)
    replay = send_all(args.url, key, events)
    conflict = copy.deepcopy(first)
    conflict["details"]["moves"] = 999999
    conflict_status = post(args.url, key, conflict)[0]
    negative = []
    for name, changes in (("too_old", {"occurred_at": ts(datetime.now(timezone.utc) - timedelta(days=7))}),
                          ("future", {"occurred_at": ts(datetime.now(timezone.utc) + timedelta(minutes=6))}),
                          ("extra_detail", {"details": {"unapproved": "test"}})):
        event = dict(first, event_id=str(uuid.uuid4()), **changes)
        status, body, _ = post(args.url, key, event)
        negative.append({"name": name, "status": status, "dlq": body.get("dlq") if isinstance(body, dict) else False})
    invalid_status, invalid_body, _ = post(args.url, key, b"{invalid")
    negative.append({"name": "invalid_json", "status": invalid_status, "dlq": invalid_body.get("dlq", False)})
    unauthorized = post(args.url, "deliberately-invalid-test-key", first, retries=1)[0]
    ok = (initial.get(202, 0) == len(events) and replay.get(202, 0) == len(events)
          and conflict_status == 202 and unauthorized == 401
          and all(r["status"] == 422 and r["dlq"] for r in negative))
    report = {"run_id": args.run_id, "passed_http": ok, "unique_events": len(events),
              "minigames": sorted(contract.MINIGAME_CATEGORY), "initial": initial, "replay": replay,
              "conflict_status": conflict_status, "negative": negative, "unauthorized": unauthorized,
              "note": "202 proves Kafka receipt only; run the storage verifier afterwards"}
    (folder / "http.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2), flush=True)
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
