import os, json, secrets, threading, time, uuid
from pathlib import Path
from datetime import datetime,timezone
from fastapi import FastAPI, Header, HTTPException, Depends
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from database import database
from simulator import scenarios, send, now
app=FastAPI(title="NODEVERSE Pipeline Lab")
db=database()
lock=threading.Lock();stop=threading.Event()
def auth(x_api_key:str=Header(default="")):
    if not secrets.compare_digest(x_api_key,os.environ["INGEST_KEY"]):raise HTTPException(401,"키를 확인해 주세요")
class Config(BaseModel):
    seed:int=42
    count:int=Field(default=64,ge=8,le=1000)
    rate:float=Field(default=3,ge=0.2,le=20)
@app.get("/",response_class=HTMLResponse)
def home():return Path("lab.html").read_text(encoding="utf-8")
@app.get("/health")
def health():db.command("ping");return {"status":"ready"}
@app.on_event("startup")
def recover():
    db.lab_runs.update_many({"status":{"$in":["sending","settling"]}},{"$set":{"status":"interrupted","note":"Lab restarted; start a new batch"}})
    db.raw_events.create_index([("payload.received_at",-1),("_id",-1)])
    db.raw_events.create_index("payload.event_id")
    db.raw_events.create_index("payload.player_id")
    db.raw_events.create_index("payload.session_id")
    db.lab_deliveries.create_index([("run_id",1),("ordinal",1)],unique=True)
def counts(run):
    prefix={"$regex":"^lab-"+run+"-"}
    metrics=list(db.metrics.find({"_id.player_id":prefix}))
    return {"metric_events":sum(x["events"] for x in metrics),"failures":sum(x["failures"] for x in metrics),"successes":sum(x["successes"] for x in metrics),"hints":sum(x["hints"] for x in metrics),"raw":db.raw_events.count_documents({"payload.player_id":prefix}),"curated":db.curated.count_documents({"player_id":prefix}),"runtime":db.runtime_events.count_documents({"player_id":prefix}),"incidents":db.incidents.count_documents({"player_id":prefix}),"quarantine":db.quarantine_events.count_documents({"payload.player_id":prefix})}
def worker(run,cfg):
    expected=dict.fromkeys(["raw","curated","runtime","incidents","quarantine","metric_events","failures","successes","hints"],0)
    try:
        db.lab_runs.update_one({"_id":run},{"$set":{"status":"sending"}})
        for i,(kind,event,target,authorized) in enumerate(scenarios(cfg.seed,cfg.count,run)):
            if stop.is_set():break
            status,body,elapsed=send("http://gateway:8000",os.environ["INGEST_KEY"],event,authorized)
            if target==202:
                expected["raw"]+=1
                if kind=="conflict_replay":expected["quarantine"]+=1
                elif kind!="duplicate_replay":
                    category="runtime" if kind=="runtime" else "curated"
                    expected[category]+=1
                    if category=="curated":
                        expected["metric_events"]+=1
                        name={"attempt_failed":"failures","attempt_succeeded":"successes","hint_used":"hints"}.get(event["event_type"])
                        if name:expected[name]+=1
                    if category=="runtime" and event["event_type"].startswith("exit_"):expected["incidents"]+=1
            db.lab_deliveries.insert_one({"run_id":run,"ordinal":i,"scenario":kind,"event":event,"expected_status":target,"status":status,"pass":status==target,"response":body,"elapsed_ms":elapsed,"at":now()})
            db.lab_runs.update_one({"_id":run},{"$set":{"expected":expected,"sent":i+1}})
            if stop.wait(1/cfg.rate):break
        db.lab_runs.update_one({"_id":run},{"$set":{"status":"settling"}})
        converged=False
        for _ in range(60):
            actual=counts(run)
            if actual==expected:converged=True;break
            time.sleep(1)
        errors=db.lab_deliveries.count_documents({"run_id":run,"pass":False})
        db.lab_runs.update_one({"_id":run},{"$set":{"status":"stopped" if stop.is_set() else "passed" if converged and not errors else "failed","actual":actual,"converged":converged,"http_errors":errors,"finished_at":now()}})
    except Exception as error:
        db.lab_runs.update_one({"_id":run},{"$set":{"status":"failed","error":type(error).__name__+": "+str(error)}})
    finally:lock.release()
@app.post("/api/start",dependencies=[Depends(auth)])
def start(cfg:Config):
    if not lock.acquire(blocking=False):raise HTTPException(409,"이미 전송 중입니다")
    stop.clear();run=uuid.uuid4().hex[:16]
    try:
        db.lab_runs.insert_one({"_id":run,"seed":cfg.seed,"count":cfg.count,"rate":cfg.rate,"status":"sending","started_at":now(),"sent":0,"expected":{}})
        threading.Thread(target=worker,args=(run,cfg),daemon=True).start()
    except Exception:lock.release();raise
    return {"run_id":run}
@app.post("/api/stop",dependencies=[Depends(auth)])
def halt():stop.set();return {"status":"stopping"}
@app.get("/api/runs",dependencies=[Depends(auth)])
def runs():return list(db.lab_runs.find().sort("started_at",-1).limit(20))
@app.get("/api/runs/{run}",dependencies=[Depends(auth)])
def details(run:str):
    record=db.lab_runs.find_one({"_id":run})
    if not record:raise HTTPException(404)
    record["actual"]=counts(run)
    record["deliveries"]=list(db.lab_deliveries.find({"run_id":run},{"_id":0}).sort("ordinal",-1).limit(40))
    record["http_errors"]=db.lab_deliveries.count_documents({"run_id":run,"pass":False})
    record["exit_types"]=list(db.runtime_events.aggregate([{"$match":{"player_id":{"$regex":"^lab-"+run+"-"}}},{"$group":{"_id":"$event_type","count":{"$sum":1}}}]))
    return record
@app.get("/api/runs/{run}/export",dependencies=[Depends(auth)])
def export(run:str):
    result=details(run)
    result["deliveries"]=list(db.lab_deliveries.find({"run_id":run},{"_id":0}).sort("ordinal",1))
    return result

@app.get("/api/runs/{run}/documents/{collection}",dependencies=[Depends(auth)])
def documents(run:str,collection:str):
    if collection not in ("raw_events","curated","runtime_events","incidents","quarantine_events","metrics"):raise HTTPException(400,"지원하지 않는 컬렉션")
    if not db.lab_runs.find_one({"_id":run}):raise HTTPException(404)
    prefix={"$regex":"^lab-"+run+"-"}
    field="payload.player_id" if collection in ("raw_events","quarantine_events") else "_id.player_id" if collection=="metrics" else "player_id"
    return list(db[collection].find({field:prefix}).limit(30))

@app.get("/overview",response_class=HTMLResponse)
def overview():return Path("overview.html").read_text(encoding="utf-8")
@app.get("/api/runs/{run}/charts",dependencies=[Depends(auth)])
def charts(run:str):
    record=db.lab_runs.find_one({"_id":run})
    if not record:raise HTTPException(404)
    prefix={"$regex":"^lab-"+run+"-"}
    outcomes=list(db.lab_deliveries.aggregate([{"$match":{"run_id":run}},{"$group":{"_id":"$status","count":{"$sum":1}}}]))
    def distribution(collection,field="event_type"):
        return list(db[collection].aggregate([{"$match":{"player_id":prefix}},{"$group":{"_id":"$"+field,"count":{"$sum":1}}},{"$sort":{"_id":1}}]))
    return {"run":record,"actual":counts(run),"outcomes":outcomes,"learning":distribution("curated"),"exits":[x for x in distribution("runtime_events") if x["_id"].startswith("exit_")],"quarantine":list(db.quarantine_events.aggregate([{"$match":{"payload.player_id":prefix}},{"$group":{"_id":"$reason","count":{"$sum":1}}}])),"unexpected":db.lab_deliveries.count_documents({"run_id":run,"pass":False})}

from incoming import router as incoming_router
app.include_router(incoming_router(db,auth))
