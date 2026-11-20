import json, os, time, uuid, urllib.request, urllib.error, subprocess
from datetime import datetime, timezone
key=os.environ.get("INGEST_KEY","replace-with-a-long-random-local-key")
e={"event_id":str(uuid.uuid4()),"player_id":"smoke-"+uuid.uuid4().hex,"session_id":"s1","problem_id":"p1","attempt_id":"a1","event_type":"attempt_failed","occurred_at":datetime.now(timezone.utc).isoformat(),"sequence":1}
def send(key,value):
    req=urllib.request.Request("http://127.0.0.1:8000/v1/events",data=json.dumps(value).encode(),headers={"Content-Type":"application/json","X-API-Key":key})
    try:
        with urllib.request.urlopen(req,timeout=15) as response: return response.status
    except urllib.error.HTTPError as err: return err.code
assert send("wrong",e)==401
assert send(key,{**e,"sequence":-1})==422
assert send(key,e)==202
assert send(key,e)==202
query='const d=db.getSiblingDB("nodeverse"); print(JSON.stringify({raw:d.raw_events.countDocuments({"payload.event_id":"'+e['event_id']+'"}),curated:d.curated.countDocuments({_id:"'+e['event_id']+'"}),metric:d.metrics.findOne({"_id.player_id":"'+e['player_id']+'"})}));'
for _ in range(90):
    result=subprocess.check_output(["docker","compose","exec","-T","mongo","mongosh","--quiet","--eval",query],text=True)
    data=json.loads(result.strip())
    if data["raw"]==2 and data["curated"]==1 and data["metric"] and data["metric"]["failures"]==1:
        print("PASS: authentication, validation, Kafka ACK, raw archival, deduplication, metrics",data);break
    time.sleep(2)
else: raise RuntimeError(data)
