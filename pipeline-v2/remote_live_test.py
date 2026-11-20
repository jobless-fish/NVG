"""Authorized live smoke: create one named test member and one play set through port 8000.
Real remote writes. Immutable fixture is saved before sending.
"""
import argparse, json, time, uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
import urllib.request, urllib.error

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--allow-live-writes', action='store_true')
    p.add_argument('--case', default='live-remote-test')
    p.add_argument('--reuse-test-member', action='store_true')
    a = p.parse_args()
    if not a.allow_live_writes:
        p.error('explicit --allow-live-writes required')
    if not __import__('re').fullmatch('[a-z0-9-]+', a.case):
        p.error('invalid case name')
    folder = Path('results') / a.case
    folder.mkdir(parents=True, exist_ok=True)
    fixture_path = folder / 'fixture.json'
    if fixture_path.exists():
        fixture = json.loads(fixture_path.read_text(encoding='utf-8'))
    else:
        token = uuid.uuid4().hex[:10]
        player = 'pipeline-live-e2e-' + token
        if a.reuse_test_member:
            player = json.loads(Path('results/live-remote-test/fixture.json').read_text(encoding='utf-8'))['player_id']
        source_session, source_run, attempt1, attempt2 = [str(uuid.uuid4()) for _ in range(4)]
        started = datetime.now(timezone.utc) - timedelta(seconds=2)
        specs = [('problem_started', attempt1, {'level': 1}), ('attempt_started', attempt1, {'level': 1}), ('operation_failed', attempt1, {'operation': 'pop', 'failure_reason': 'empty_stack', 'state_before': '{"items":[]}', 'state_after': '{"items":[]}'}), ('hint_used', attempt1, {'hint_id': 'stack-lifo-h1'}), ('attempt_failed', attempt1, {'failure_reason': 'retry', 'mistakes': 1}), ('attempt_started', attempt2, {'level': 1}), ('operation_succeeded', attempt2, {'operation': 'push', 'state_before': '{"items":[]}', 'state_after': '{"items":[1]}'}), ('attempt_succeeded', attempt2, {'moves': 1, 'stars': 3}), ('problem_completed', attempt2, {'level': 1})]
        events = []
        for sequence, (et, attempt, details) in enumerate(specs, 1):
            events.append({'schema_version': 2, 'event_id': str(uuid.uuid4()), 'player_id': player, 'session_id': source_session, 'run_id': source_run, 'attempt_id': attempt, 'minigame_id': 'ST03', 'category': 'DS', 'build_version': '0.3.0', 'content_version': 'pipeline-e2e-20261120', 'event_type': et, 'sequence': sequence, 'occurred_at': (started + timedelta(milliseconds=sequence * 100)).isoformat(timespec='milliseconds').replace('+00:00', 'Z'), 'details': details})
        fixture = {'player_id': player, 'nickname': '[연동시험] V2 자동 적재', 'source_session_id': source_session, 'run_id': source_run, 'events': events}
        fixture_path.write_text(json.dumps(fixture, ensure_ascii=False, indent=2), encoding='utf-8')
        context_path = Path('.env.remote-context.json')
        context = json.loads(context_path.read_text(encoding='utf-8'))
        context.setdefault('members', {})[player] = {'external_member_key': 'game:member:' + player, 'nickname': fixture['nickname'], 'verified': True, 'create_if_missing': True}
        context_path.write_text(json.dumps(context, ensure_ascii=False, indent=2), encoding='utf-8')
    key = next((line.split('=', 1)[1].strip().strip('"').strip("'") for line in Path('../pipeline/.env').read_text(encoding='utf-8-sig').splitlines() if line.startswith('INGEST_KEY=')))
    base = 'http://192.168.0.81:8000'

    def call(path, event=None):
        req = urllib.request.Request(base + path, data=json.dumps(event).encode() if event is not None else None, headers={'Content-Type': 'application/json', 'X-API-Key': key})
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return (r.status, json.load(r))
        except urllib.error.HTTPError as e:
            return (e.code, json.loads(e.read()))
    report = {'fixture': str(fixture_path), 'responses': [], 'delivery': []}
    for i in [0, 2, 1, 5, 8, 3, 4, 7, 6]:
        e = fixture['events'][i]
        status, body = call('/v2/events', e)
        report['responses'].append({'event_id': e['event_id'], 'sequence': e['sequence'], 'status': status})
        print(json.dumps(report['responses'][-1]), flush=True)
        if status != 202:
            report['failure'] = body
            (folder / 'http-result.json').write_text(json.dumps(report, indent=2))
            raise SystemExit(1)
    for e in fixture['events']:
        status, _ = call('/v2/events', e)
        if status != 202:
            raise RuntimeError('Replay not accepted')
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        delivery = [call('/v2/events/' + e['event_id'])[1] for e in fixture['events']]
        print(json.dumps({'delivery_states': [d.get('state') for d in delivery], 'reasons': [d.get('reason') for d in delivery if d.get('reason')]}), flush=True)
        if all((d.get('state') == 'stored' for d in delivery)):
            report['delivery'] = delivery
            report['passed_http_and_delivery'] = True
            break
        if any((d.get('state') == 'blocked' for d in delivery)):
            report['delivery'] = delivery
            break
        time.sleep(3)
    else:
        report['delivery'] = delivery
    (folder / 'http-result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    raise SystemExit(0 if report.get('passed_http_and_delivery') else 1)
if __name__ == '__main__':
    main()
