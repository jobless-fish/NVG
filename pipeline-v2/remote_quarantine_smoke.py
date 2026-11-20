"""Explicit public-ingress quarantine/replay test using an existing synthetic member."""
import argparse
import json
import time
import uuid
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-live-writes", action="store_true")
    args = parser.parse_args()
    if not args.allow_live_writes:
        parser.error("--allow-live-writes required: creates a synthetic play set in remote DB")
    original = json.loads(Path("results/live-remote-test/fixture.json").read_text(encoding="utf-8"))
    session, run, attempt = [str(uuid.uuid4()) for _ in range(3)]
    started = datetime.now(timezone.utc) - timedelta(seconds=1)
    specs = [("operation_succeeded", {}), ("problem_started", {"level": 1}),
             ("attempt_started", {}), ("operation_succeeded", {}),
             ("attempt_succeeded", {}), ("problem_completed", {"level": 1})]
    events = [dict(original["events"][0], event_id=str(uuid.uuid4()), session_id=session,
                   run_id=run, attempt_id=attempt, sequence=i, event_type=kind, details=details,
                   occurred_at=(started + timedelta(milliseconds=i*100)).isoformat(timespec="milliseconds").replace("+00:00", "Z"))
              for i, (kind, details) in enumerate(specs, 1)]
    folder = Path("results/quarantine-smoke") / run
    folder.mkdir(parents=True)
    (folder / "fixture.json").write_text(json.dumps(events, indent=2), encoding="utf-8")
    key = next(line.split("=", 1)[1].strip().strip("\"'") for line in
               Path("../pipeline/.env").read_text(encoding="utf-8-sig").splitlines() if line.startswith("INGEST_KEY="))
    base = "http://192.168.0.81:8000/v2/events"

    def call(event=None, ident=None):
        request = urllib.request.Request(base + ("/" + ident if ident else ""),
            data=json.dumps(event).encode() if event else None,
            headers={"Content-Type": "application/json", "X-API-Key": key})
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, json.load(response)

    start = time.monotonic()
    for event in reversed(events):
        assert call(event)[0] == 202
    for event in events:
        assert call(event)[0] == 202
    expected = ["quarantined", "stored", "stored", "quarantined", "stored", "stored"]
    while time.monotonic() - start < 180:
        deliveries = [call(ident=e["event_id"])[1] for e in events]
        states = [d["state"] for d in deliveries]
        print(json.dumps({"states": states}), flush=True)
        if states == expected:
            result = {"passed": True, "run_id": run, "seconds": round(time.monotonic()-start, 2),
                      "delivery": deliveries, "meaning": "4 dashboard events; 2 explicit exclusions; exact replay"}
            (folder / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
            print(json.dumps({"passed": True, "result": str(folder / "result.json")}), flush=True)
            return
        time.sleep(3)
    raise RuntimeError("quarantine smoke timed out; fixtures retained")


if __name__ == "__main__":
    main()
