"""Prevent false-success test runs and timestamp-changing update replays."""
from types import SimpleNamespace
import pytest
import simulator


def test_update_replay_keeps_exact_payload(tmp_path, monkeypatch):
    monkeypatch.setattr(simulator, "RUNS", tmp_path)
    sent = []
    def send(url, key, events):
        sent.append(events)
        return {202: len(events)}
    monkeypatch.setattr(simulator, "send_all", send)
    args = SimpleNamespace(run_id="replay", installs=2, hash_failures=1, target="v1")
    simulator.cmd_updates(args, "unused", "unused")
    # Replaying must not regenerate timestamps or payloads even if generator changes.
    monkeypatch.setattr(simulator, "update_flow", lambda *a, **k: pytest.fail("regenerated replay"))
    simulator.cmd_updates(args, "unused", "unused")
    assert sent[0] == sent[1] and sent[0]


def test_smoke_transport_failure_exits_nonzero(tmp_path, monkeypatch):
    monkeypatch.setattr(simulator, "RUNS", tmp_path)
    monkeypatch.setattr(simulator, "send_all", lambda *a: {503: 1})
    with pytest.raises(SystemExit) as result:
        simulator.cmd_smoke(SimpleNamespace(run_id="failure", count=1), "unused", "unused")
    assert result.value.code == 1


def test_contract_check_failure_exits_nonzero(monkeypatch):
    monkeypatch.setattr(simulator, "post", lambda *a: (503, {}, 0.0))
    with pytest.raises(SystemExit) as result:
        simulator.cmd_checks(SimpleNamespace(run_id="failure"), "unused", "unused")
    assert result.value.code == 1
