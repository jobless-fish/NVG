"""Integration: real HTTP -> Kafka -> MongoDB, two seeded batches and bounded stop."""
import json,os,time,urllib.request,urllib.error
from pathlib import Path
base=os.environ.get("LAB_URL","http://127.0.0.1:8010")
key=os.environ.get("INGEST_KEY")
if not key:
    key=next(line.split("=",1)[1].strip() for line in Path(".env").read_text().splitlines() if line.startswith("INGEST_KEY="))
def api(path,body=None,authorized=True):
    req=urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers={"Content-Type":"application/json","X-API-Key":key if authorized else "wrong"})
    with urllib.request.urlopen(req,timeout=15) as response:return json.load(response)
try:api("/api/runs",authorized=False);raise AssertionError("unauthorized access")
except urllib.error.HTTPError as error:assert error.code==401
results=[]
for seed,count in [(42,64),(867,128)]:
    run=api("/api/start",{"seed":seed,"count":count,"rate":20})["run_id"]
    for _ in range(120):
        result=api("/api/runs/"+run)
        if result["status"] in ("passed","failed","interrupted"):break
        time.sleep(1)
    export=api("/api/runs/"+run+"/export")
    assert result["status"]=="passed",result
    assert result["actual"]==result["expected"]
    assert all(d["pass"] for d in export["deliveries"])
    assert len(export["deliveries"])==count+count//4
    assert len(result["exit_types"])==8
    results.append(export)
    print("PASS",seed,"requests",len(export["deliveries"]),"counts",result["actual"],flush=True)
# Stop is bounded and overlapping starts are rejected.
run=api("/api/start",{"seed":7,"count":1000,"rate":1})["run_id"]
try:api("/api/start",{"seed":8,"count":8,"rate":1});raise AssertionError("overlap")
except urllib.error.HTTPError as error:assert error.code==409
api("/api/stop",{})
for _ in range(90):
    result=api("/api/runs/"+run)
    if result["status"]=="stopped":break
    time.sleep(1)
assert result["status"]=="stopped" and result["sent"]<1000,result
results.append(api("/api/runs/"+run+"/export"))
path=Path(os.environ.get("LAB_TEST_OUTPUT","lab-test-results.json"))
path.write_text(json.dumps({"all_pass":True,"checks":["authentication","two seeds","HTTP expectations","exact storage counts","all runtime types","single active batch","stop"],"runs":results},ensure_ascii=False,indent=2),encoding="utf-8")
print("PASS auth, overlap prevention, stop and export",flush=True)
