"""P4 completion check: time from sending one event to its rt_minigame_1m update (target <= 15 s).

Run inside the spark container:  python3 /app/probe_latency.py [--probes 3]
"""
import argparse
import json
import os
import time
import sys
import urllib.request
import urllib.error
import uuid
from datetime import datetime, timezone

from pymongo import MongoClient

p = argparse.ArgumentParser()
p.add_argument("--probes", type=int, default=3)
p.add_argument("--game", default="ST10")
p.add_argument("--timeout", type=float, default=60)
a = p.parse_args()
db = MongoClient(os.getenv("MONGO_URI", "mongodb://mongo:27017"))[os.getenv("MONGO_DB", "nodeverse_logs")]
url = os.getenv("COLLECTOR_URL", "http://collector:8000") + "/v2/events"
key = os.environ["INGEST_KEY"]
# Container creation is not readiness. Do not include startup connection failures in latency samples.
ready_deadline = time.monotonic() + 45
while True:
    try:
        with urllib.request.urlopen(os.getenv("COLLECTOR_URL", "http://collector:8000") + "/health/ready", timeout=3) as response:
            if response.status == 200:
                break
    except (OSError, urllib.error.URLError):
        pass
    if time.monotonic() >= ready_deadline:
        print(json.dumps({"passed_15s": False, "reason": "collector_not_ready"}), flush=True)
        sys.exit(1)
    time.sleep(1)
results = []
for i in range(a.probes):
    now = datetime.now(timezone.utc)
    if now.second >= 50:  # avoid crossing a minute boundary mid-probe
        time.sleep(61 - now.second)
        now = datetime.now(timezone.utc)
    window = now.replace(second=0, microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
    doc_id = f"{a.game}:{window}"
    before = (db.rt_minigame_1m.find_one({"_id": doc_id}) or {}).get("attempts", 0)
    probe = str(uuid.uuid4())
    event = {"schema_version": 2, "event_id": str(uuid.uuid4()), "player_id": f"probe-{probe[:8]}",
             "session_id": probe, "run_id": probe, "attempt_id": str(uuid.uuid4()), "minigame_id": a.game,
             "category": "DS", "build_version": "0.3.0", "content_version": "base", "event_type": "attempt_started",
             "occurred_at": now.isoformat(timespec="milliseconds").replace("+00:00", "Z"), "sequence": 1,
             "details": {}}
    sent = time.monotonic()
    req = urllib.request.Request(url, data=json.dumps(event).encode(),
                                 headers={"Content-Type": "application/json", "X-API-Key": key})
    status = urllib.request.urlopen(req, timeout=15).status
    elapsed = None
    while time.monotonic() - sent < a.timeout:
        doc = db.rt_minigame_1m.find_one({"_id": doc_id}) or {}
        if doc.get("attempts", 0) > before:
            elapsed = round(time.monotonic() - sent, 2)
            break
        time.sleep(0.25)
    results.append({"doc": doc_id, "http": status, "seconds_to_rt_minigame_1m": elapsed})
    print(json.dumps(results[-1]), flush=True)
ok = all(r["seconds_to_rt_minigame_1m"] is not None and r["seconds_to_rt_minigame_1m"] <= 15 for r in results)
print(json.dumps({"passed_15s": ok, "max": max((r["seconds_to_rt_minigame_1m"] or 1e9) for r in results)}))

sys.exit(0 if ok else 1)
