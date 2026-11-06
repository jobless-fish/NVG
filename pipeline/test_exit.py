import json, os, subprocess, time, uuid, urllib.request, urllib.error
from datetime import datetime, timezone
key=os.environ.get("INGEST_KEY","replace-with-a-long-random-local-key")
e={"event_id":str(uuid.uuid4()),"run_id":str(uuid.uuid4()),"player_id":"exit-test-"+uuid.uuid4().hex,"build_version":"test","event_type":"exit_unexpected_unknown","evidence":"next_launch_recovery","occurred_at":datetime.now(timezone.utc).isoformat()}
def send(body):
    request=urllib.request.Request("http://127.0.0.1:8000/v1/events",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","X-API-Key":key})
    try:
        with urllib.request.urlopen(request,timeout=15) as response: return response.status
    except urllib.error.HTTPError as error: return error.code
assert send({**e,"event_type":"exit_crash_confirmed"})==422
assert send(e)==202
assert send(e)==202
assert send({**e,"event_type":"exit_forced_confirmed","evidence":"user_confirmed"})==202
query='const d=db.getSiblingDB("nodeverse");print(JSON.stringify({runtime:d.runtime_events.countDocuments({_id:"'+e['event_id']+'"}),incident:d.incidents.findOne({_id:"'+e['event_id']+'"}),quarantine:d.quarantine_events.countDocuments({"payload.event_id":"'+e['event_id']+'",reason:"event_id_conflict"}),learning:d.curated.countDocuments({_id:"'+e['event_id']+'"})}));'
for _ in range(60):
    data=json.loads(subprocess.check_output(["docker","compose","exec","-T","mongo","mongosh","--quiet","--eval",query],text=True))
    if data["runtime"]==1 and data["quarantine"]==1 and data["learning"]==0 and data["incident"]["event_type"]=="exit_unexpected_unknown":
        print("PASS: exit classification evidence, deduplication, conflict quarantine, learning isolation");break
    time.sleep(2)
else: raise AssertionError(data)
# SQLite survives reopening; network failure retains pending event.
import tempfile
from pathlib import Path
from launcher import Outbox
with tempfile.TemporaryDirectory() as folder:
    box=Outbox(Path(folder));box.enqueue(e);box.flush("http://127.0.0.1:1",key);box.db.close()
    box=Outbox(Path(folder));assert box.db.execute("SELECT count(*) FROM queue WHERE state='pending'").fetchone()[0]==1;box.db.close()
print("PASS: persistent offline queue")
