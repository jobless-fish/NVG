import os,json,time,uuid,urllib.request,urllib.error,urllib.parse
from pathlib import Path
from datetime import datetime,timezone
base=os.environ.get("LAB_URL","http://127.0.0.1:8010")
ingest=os.environ.get("INGEST_URL","http://127.0.0.1:8000")
key=next(x.split("=",1)[1].strip() for x in Path(".env").read_text().splitlines() if x.startswith("INGEST_KEY="))
def request(url,body=None,auth=True):
    req=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,headers={"Content-Type":"application/json","X-API-Key":key if auth else "wrong"})
    with urllib.request.urlopen(req,timeout=15) as response:return response.status,json.load(response)
def query(**q):return request(base+"/api/incoming?"+urllib.parse.urlencode(q))[1]
try:request(base+"/api/incoming",auth=False);raise AssertionError("missing auth")
except urllib.error.HTTPError as error:assert error.code==401
player="team-check-"+uuid.uuid4().hex[:10];session=str(uuid.uuid4());eid=str(uuid.uuid4())
event={"event_id":eid,"player_id":player,"session_id":session,"problem_id":"incoming-test","attempt_id":"a1","event_type":"operation","occurred_at":datetime.now(timezone.utc).isoformat(),"sequence":0}
for payload in [event,event,{**event,"duration_ms":1}]:assert request(ingest+"/v1/events",payload)[0]==202
for _ in range(45):
    data=query(player_id=player)
    if data["total"]==3 and sum(x["state"]=="processed" for x in data["rows"])==2 and sum(x["state"]=="quarantined" for x in data["rows"])==1:break
    time.sleep(1)
else:raise AssertionError(data)
assert query(session_id=session)["total"]==3
assert query(event_id=eid)["total"]==3
assert query(player_id=player,event_type="operation")["total"]==3
assert query(player_id=player,event_type="hint_used")["total"]==0
assert query(player_id=player,limit=1,offset=1)["has_more"]
assert query(player_id="lab-nonexistent")["total"]==0
all_rows=query(limit=100)
assert all(not row["payload"].get("player_id","").startswith("lab-") for row in all_rows["rows"])
assert query(include_dummy="true",limit=1)["total"]>=all_rows["total"]
try:query(limit=101);raise AssertionError("limit")
except urllib.error.HTTPError as error:assert error.code==422
result={"pass":True,"player_id":player,"checks":["authentication","direct API ingestion without batch","duplicate delivery","receipt-specific conflict quarantine","all exact-match filters","pagination","dummy exclusion","limit validation"],"data":data}
Path(os.environ.get("TEST_OUTPUT","incoming-test-results.json")).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
print("PASS: direct incoming events, filters, pagination, auth, duplicate and quarantine",player)
