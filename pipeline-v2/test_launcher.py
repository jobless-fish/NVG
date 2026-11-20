"""launcher.py: runtime events it builds must pass the API's RuntimeEvent model unchanged."""
import json
from datetime import datetime, timezone
import uuid

import contract


def test_launcher_event_shape_matches_runtime_model():
    base = {"schema_version": 1, "run_id": str(uuid.uuid4()), "player_id": str(uuid.uuid4()), "build_version": "0.3.0"}
    for kind, evidence in [("run_started", "launcher_observed"), ("run_heartbeat", "launcher_observed"),
                           ("exit_normal", "game_shutdown_complete"), ("exit_unexpected_unknown", "next_launch_recovery")]:
        e = {**base, "event_id": str(uuid.uuid4()), "occurred_at": datetime.now(timezone.utc).isoformat(),
             "event_type": kind, "evidence": evidence}
        contract.RuntimeEvent.model_validate(json.loads(json.dumps(e)))
        assert contract.route(kind)[1] == "nv.runtime.v1"


def test_launcher_posts_v2_and_passes_player_id():
    src = open("launcher.py", encoding="utf-8").read()
    assert '"/v2/events"' in src and '"NODEVERSE_PLAYER_ID":base["player_id"]' in src


def test_launcher_skips_events_older_than_six_days(tmp_path, monkeypatch):
    import json as _json
    from datetime import datetime, timedelta, timezone
    import launcher
    box = launcher.Outbox(tmp_path)
    old = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
    box.enqueue({"event_id": "old-1", "occurred_at": old})
    sent = []
    monkeypatch.setattr(launcher.urllib.request, "urlopen", lambda *a, **k: sent.append(a))
    box.flush("http://127.0.0.1:9", "k")
    assert sent == []
    assert box.db.execute("SELECT state FROM queue WHERE id='old-1'").fetchone()[0] == "expired"
