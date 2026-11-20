"""NODEVERSE v2 event simulator (standard library only). Every event goes through the real POST /v2/events.

  python simulator.py smoke   --count 100 --run-id smoke-001     # learning events; saved to runs/<run-id>.jsonl
  python simulator.py smoke   --run-id smoke-001                 # same run-id again = identical resend
  python simulator.py checks                                     # P1/P3 checks: 422+DLQ, duplicate, id_conflict
  python simulator.py updates --installs 30 --run-id upd-001     # update progress events (P4-2)
  python simulator.py load    --users 1200 --rate 200 --duration 600 --run-id load-001   # P6 load test

Environment: INGEST_KEY (required), COLLECTOR_URL (default http://127.0.0.1:8000).
"""
from __future__ import annotations

import argparse
import json
import os
import random
import threading
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

GAMES = {
    "ST01": "DS", "ST02": "DS", "ST03": "DS", "ST04": "DS", "ST05": "DS",
    "DS09": "DS", "ST07": "DS", "ST08": "DS", "DS10": "DS", "ST10": "DS",
    "ALG02": "ALGO", "ALG01": "ALGO", "ALG03": "ALGO", "ST06": "ALGO", "ST09": "ALGO", "ALG04": "ALGO",
    "SQL01": "SQL", "SQL02": "SQL", "SQL03": "SQL", "SQL04": "SQL",
    "DATA02": "DATA", "DATA01": "DATA", "DATA03": "DATA", "DATA04": "DATA",
}
OPERATIONS = ["push", "pop", "enqueue", "dequeue", "insert", "delete", "link", "swap", "select", "join"]
RUNS = Path("runs")


def ts(dt: datetime | None = None) -> str:
    return (dt or datetime.now(timezone.utc)).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def uid(*parts) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "/".join(str(p) for p in parts)))


# ---------------------------------------------------------------- event builders
class Session:
    """One play session of one install on one minigame; emits a realistic v2 sequence."""

    def __init__(self, run_id: str, player: str, game: str, n: int, rng: random.Random,
                 build="0.3.0", content="base"):
        self.rng, self.run_id = rng, run_id
        self.base = {"schema_version": 2, "player_id": player, "session_id": uid(run_id, player, game, n, "s"),
                     "run_id": uid(run_id, player, "run"), "minigame_id": game, "category": GAMES[game],
                     "build_version": build, "content_version": content}
        self.seq = 0
        self.attempt = None

    def event(self, event_type: str, **details) -> dict:
        self.seq += 1
        e = dict(self.base, event_id=uid(self.base["session_id"], self.seq), event_type=event_type,
                 occurred_at=ts(), sequence=self.seq, details=details)
        if self.attempt:
            e["attempt_id"] = self.attempt
        return e

    def script(self, fail_bias: float = 0.3):
        """Generator of events for a full problem."""
        yield self.event("problem_started", level=1)
        for a in range(self.rng.randint(1, 3)):
            self.attempt = uid(self.base["session_id"], "attempt", a)
            yield self.event("attempt_started", level=1)
            mistakes = 0
            for m in range(self.rng.randint(2, 5)):
                op = self.rng.choice(OPERATIONS)
                if self.rng.random() < fail_bias:
                    mistakes += 1
                    yield self.event("operation_failed", operation=op, failure_reason="invalid_order", moves=m + 1,
                                     mistakes=mistakes)
                else:
                    yield self.event("operation_succeeded", operation=op, moves=m + 1, mistakes=mistakes)
            if self.rng.random() < 0.2:
                yield self.event("hint_used", hint_id=f"h{a + 1}")
            if self.rng.random() < fail_bias + 0.2:
                yield self.event("attempt_failed", mistakes=mistakes, moves=5)
            else:
                yield self.event("attempt_succeeded", stars=self.rng.randint(1, 3), mistakes=mistakes, moves=5)
                break
        self.attempt = None
        yield self.event("problem_completed", level=1)


def update_flow(run_id: str, install: str, rng: random.Random, target="content-2026.11.19",
                fail_reason: str | None = None) -> list[dict]:
    base = {"schema_version": 2, "player_id": install, "run_id": uid(run_id, install, "run"),
            "build_version": "0.3.0", "content_version": "content-2026.11.12"}
    out = []
    start = datetime.now(timezone.utc) - timedelta(seconds=20)

    def ev(event_type, **details):  # one step per second so "latest version per install" is unambiguous
        out.append(dict(base, event_id=uid(run_id, install, len(out)), event_type=event_type,
                        occurred_at=ts(start + timedelta(seconds=len(out))), details=details))
    ev("update_checked", result="optional", target_version=target)
    ev("update_prompted", kind="optional", target_version=target)
    if rng.random() < 0.2:
        ev("update_dismissed", target_version=target)
        return out
    ev("update_accepted", target_version=target)
    ev("pack_download_started", target_version=target)
    if fail_reason:
        ev("pack_download_failed", target_version=target, failure_reason=fail_reason, bytes=1834201,
           duration_ms=rng.randint(500, 9000))
        return out
    ev("pack_download_succeeded", target_version=target, bytes=1834201, duration_ms=rng.randint(800, 6000))
    ev("pack_mounted", target_version=target)
    base["content_version"] = target  # events after mounting carry the new pack version
    ev("update_checked", result="up_to_date", target_version=target)
    return out


# ---------------------------------------------------------------- HTTP
def post(url: str, key: str, body: dict | bytes, timeout=15.0, retries=5):
    data = body if isinstance(body, bytes) else json.dumps(body).encode()
    for attempt in range(retries):
        req = urllib.request.Request(url + "/v2/events", data=data,
                                     headers={"Content-Type": "application/json", "X-API-Key": key})
        started = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, json.loads(r.read() or b"{}"), time.monotonic() - started
        except urllib.error.HTTPError as e:
            status, payload = e.code, e.read()
            if status == 503 and attempt < retries - 1:  # same id + same body, per contract
                time.sleep(min(2 ** attempt, 8))
                continue
            try:
                payload = json.loads(payload)
            except ValueError:
                pass
            return status, payload, time.monotonic() - started
        except OSError as e:
            if attempt == retries - 1:
                return 0, {"error": type(e).__name__}, time.monotonic() - started
            time.sleep(min(2 ** attempt, 8))
    return 0, {}, 0.0


def save(run_id: str, events: list[dict]) -> Path:
    RUNS.mkdir(exist_ok=True)
    f = RUNS / f"{run_id}.jsonl"
    f.write_text("".join(json.dumps(e) + "\n" for e in events), encoding="utf-8")
    return f


def load_run(run_id: str) -> list[dict] | None:
    f = RUNS / f"{run_id}.jsonl"
    return [json.loads(x) for x in f.read_text(encoding="utf-8").splitlines()] if f.exists() else None


def send_all(url, key, events, workers=16):
    stats: dict[int, int] = {}
    with ThreadPoolExecutor(workers) as pool:
        for status, _, _ in pool.map(lambda e: post(url, key, e), events):
            stats[status] = stats.get(status, 0) + 1
    return stats


# ---------------------------------------------------------------- commands
def cmd_smoke(a, url, key):
    events = load_run(a.run_id)
    if events is None:
        rng = random.Random(a.run_id)
        events, n = [], 0
        while len(events) < a.count:
            s = Session(a.run_id, f"install-{a.run_id}-{n % 20}", rng.choice(list(GAMES)), n, rng)
            events.extend(s.script())
            n += 1
        events = events[:a.count]
        save(a.run_id, events)
        print(f"generated {len(events)} events -> runs/{a.run_id}.jsonl")
    else:
        print(f"resending {len(events)} identical events from runs/{a.run_id}.jsonl")
    stats = send_all(url, key, events)
    print(json.dumps({"run_id": a.run_id, "sent": len(events), "unique_event_ids": len({e['event_id'] for e in events}),
                      "status": stats}))
    if stats.get(202, 0) != len(events):
        raise SystemExit(1)


def cmd_checks(a, url, key):
    rng = random.Random(a.run_id)
    s = Session(a.run_id, f"install-{a.run_id}", "ST04", 0, rng)
    first = s.event("operation_failed", operation="push", failure_reason="queue_full", moves=1, mistakes=1)
    results = {}
    results["valid_202"] = post(url, key, first)[0]
    results["duplicate_202"] = post(url, key, first)[0]
    conflict = dict(first, details=dict(first["details"], moves=99))
    results["conflict_202_then_quarantined"] = post(url, key, conflict)[0]
    bad_key = s.event("hint_used", hint_id="h1")
    bad_key["details"]["secret"] = "x"
    st, body, _ = post(url, key, bad_key)
    results["extra_detail_key_422"] = st
    results["extra_detail_key_dlq"] = body.get("dlq") if isinstance(body, dict) else None
    wrong_cat = dict(s.event("attempt_started"), category="SQL")
    results["wrong_category_422"] = post(url, key, wrong_cat)[0]
    results["invalid_json_422"] = post(url, key, b"{not json")[0]
    upd = update_flow(a.run_id, f"install-{a.run_id}", rng)[0]
    results["update_event_202"] = post(url, key, upd)[0]
    rt = {"schema_version": 1, "event_id": str(uuid.uuid4()), "run_id": str(uuid.uuid4()),
          "player_id": f"install-{a.run_id}", "build_version": "0.3.0", "event_type": "run_started",
          "occurred_at": ts(), "evidence": "launcher_observed"}
    results["runtime_event_202"] = post(url, key, rt)[0]
    expected = {"valid_202": 202, "duplicate_202": 202, "conflict_202_then_quarantined": 202,
                "extra_detail_key_422": 422, "extra_detail_key_dlq": True, "wrong_category_422": 422,
                "invalid_json_422": 422, "update_event_202": 202, "runtime_event_202": 202}
    ok = all(results[k] == v for k, v in expected.items())
    print(json.dumps({"results": results, "passed": ok,
                      "expect_in_silver": "1 learning row for event_id " + first["event_id"]
                      + " and 1 quarantine row (id_conflict)"}, indent=2))
    if not ok:
        raise SystemExit(1)


def cmd_updates(a, url, key):
    events = load_run(a.run_id)
    if events is None:
        rng = random.Random(a.run_id)
        events = []
        for i in range(a.installs):
            reason = "hash_mismatch" if i < a.hash_failures else None
            events.extend(update_flow(a.run_id, f"install-{a.run_id}-{i}", rng, target=a.target, fail_reason=reason))
        save(a.run_id, events)
    stats = send_all(url, key, events)
    print(json.dumps({"run_id": a.run_id, "sent": len(events), "status": stats}))
    if stats.get(202, 0) != len(events):
        raise SystemExit(1)


def cmd_load(a, url, key):
    """users virtual installs spread over 24 games; open-loop at `rate` events/s for `duration` seconds."""
    rng = random.Random(a.run_id)
    games = list(GAMES)
    sessions = [Session(a.run_id, f"load-{a.run_id}-{u}", games[u % len(games)], 0, random.Random(u))
                for u in range(a.users)]
    scripts = [s.script() for s in sessions]
    counts = {"n": 0}

    def next_event():
        while True:
            i = rng.randrange(len(scripts))
            try:
                return next(scripts[i])
            except StopIteration:
                counts["n"] += 1
                sessions[i] = Session(a.run_id, sessions[i].base["player_id"], games[i % len(games)], counts["n"], rng)
                scripts[i] = sessions[i].script()

    status: dict[int, int] = {}
    lat: list[float] = []
    lock = threading.Lock()

    def one(e):
        st, _, dt = post(url, key, e, retries=1)
        with lock:
            status[st] = status.get(st, 0) + 1
            lat.append(dt)

    ids = []
    started = time.monotonic()
    total = int(a.rate * a.duration)
    with ThreadPoolExecutor(a.workers) as pool:
        for n in range(total):
            due = started + n / a.rate
            delay = due - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            e = next_event()
            ids.append(e["event_id"])
            pool.submit(one, e)
            if n and n % (a.rate * 10) == 0:
                print(f"  {n}/{total} sent, elapsed {time.monotonic() - started:.0f}s, status {status}")
    elapsed = time.monotonic() - started
    lat.sort()

    def pct(p):
        return round(lat[min(len(lat) - 1, int(len(lat) * p))] * 1000, 1) if lat else None
    report = {"run_id": a.run_id, "users": a.users, "target_rate": a.rate, "duration_s": round(elapsed, 1),
              "sent": total, "unique_event_ids": len(set(ids)), "status": status,
              "accepted_ratio": round(status.get(202, 0) / total, 4) if total else None,
              "achieved_rate": round(total / elapsed, 1), "latency_ms": {"p50": pct(0.5), "p95": pct(0.95),
                                                                         "p99": pct(0.99)},
              "finished_at": ts()}
    Path("results").mkdir(exist_ok=True)
    out = Path("results") / f"load-{a.run_id}.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"saved {out}")
    if report["accepted_ratio"] != 1.0:
        raise SystemExit(1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("smoke"); s.add_argument("--count", type=int, default=100); s.add_argument("--run-id", default="smoke-001")
    c = sub.add_parser("checks"); c.add_argument("--run-id", default=f"checks-{int(time.time())}")
    u = sub.add_parser("updates"); u.add_argument("--installs", type=int, default=30)
    u.add_argument("--hash-failures", type=int, default=5); u.add_argument("--target", default="content-2026.11.19")
    u.add_argument("--run-id", default=f"upd-{int(time.time())}")
    ld = sub.add_parser("load"); ld.add_argument("--users", type=int, default=1200); ld.add_argument("--rate", type=int, default=200)
    ld.add_argument("--duration", type=int, default=600); ld.add_argument("--workers", type=int, default=64)
    ld.add_argument("--run-id", default=f"load-{int(time.time())}")
    a = p.parse_args()
    key = os.environ.get("INGEST_KEY") or p.error("set INGEST_KEY")
    url = os.environ.get("COLLECTOR_URL", "http://127.0.0.1:8000").rstrip("/")
    {"smoke": cmd_smoke, "checks": cmd_checks, "updates": cmd_updates, "load": cmd_load}[a.cmd](a, url, key)


if __name__ == "__main__":
    main()
