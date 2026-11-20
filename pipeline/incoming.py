"""Read-only incoming deliveries, independent of synthetic batch manifests."""
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import HTMLResponse
from pathlib import Path

def router(db,auth):
    api=APIRouter()
    @api.get("/incoming",response_class=HTMLResponse)
    def page():return Path("incoming.html").read_text(encoding="utf-8")
    @api.get("/api/incoming",dependencies=[Depends(auth)])
    def events(player_id:str=Query(default="",max_length=128),session_id:str=Query(default="",max_length=128),event_id:str=Query(default="",max_length=128),event_type:str=Query(default="",max_length=128),include_dummy:bool=False,offset:int=Query(default=0,ge=0,le=10000),limit:int=Query(default=30,ge=1,le=100)):
        q={}
        for name,value in [("player_id",player_id),("session_id",session_id),("event_id",event_id),("event_type",event_type)]:
            if value:q["payload."+name]=value
        if not include_dummy:
            if player_id.startswith("lab-"):q["payload.player_id"]={"$eq":player_id,"$not":{"$regex":"^lab-"}}
            elif not player_id:q["payload.player_id"]={"$not":{"$regex":"^lab-"}}
        total=db.raw_events.count_documents(q)
        records=list(db.raw_events.find(q).sort([("payload.received_at",-1),("_id",-1)]).skip(offset).limit(limit))
        ids=[x["payload"].get("event_id") for x in records if isinstance(x.get("payload"),dict) and isinstance(x["payload"].get("event_id"),str)]
        learned={x["_id"] for x in db.curated.find({"_id":{"$in":ids}},{"_id":1})}
        runtime={x["_id"] for x in db.runtime_events.find({"_id":{"$in":ids}},{"_id":1})}
        incidents={x["_id"] for x in db.incidents.find({"_id":{"$in":ids}},{"_id":1})}
        rejected={x["_id"]:x.get("reason") for x in db.quarantine_events.find({"_id":{"$in":[x["_id"] for x in records]}})}
        rows=[]
        for raw in records:
            payload=raw.get("payload",{});payload=payload if isinstance(payload,dict) else {"unparsed":payload}
            eid=payload.get("event_id");eid=eid if isinstance(eid,str) else None;reason=rejected.get(raw["_id"])
            state="quarantined" if reason else "processed" if eid in learned or eid in runtime else "pending"
            rows.append({"receipt_id":raw["_id"],"payload":payload,"state":state,"quarantine_reason":reason,"learning_stored":eid in learned,"runtime_stored":eid in runtime,"exit_stored":eid in incidents})
        return {"total":total,"offset":offset,"limit":limit,"rows":rows,"has_more":offset+len(rows)<total}
    @api.get("/api/server-incoming",dependencies=[Depends(auth)])
    def remote_events(player_id:str=Query(default="",max_length=128),session_id:str=Query(default="",max_length=128),event_id:str=Query(default="",max_length=128),event_type:str=Query(default="",max_length=128),offset:int=Query(default=0,ge=0,le=10000),limit:int=Query(default=30,ge=1,le=100)):
        import os
        from pymongo import MongoClient
        uri=os.environ.get("VIEW_MONGO_URI")
        if not uri:raise HTTPException(503,"서버 DB 조회 주소가 설정되지 않았습니다")
        client=MongoClient(uri,serverSelectionTimeoutMS=4000,socketTimeoutMS=4000,tz_aware=True)
        try:
            target=client[os.environ.get("VIEW_MONGO_DATABASE","nodeverse_logs")]
            q={}
            if player_id:q["session_id"]={"$in":[x["_id"] for x in target.game_sessions.find({"player_id":player_id},{"_id":1})]}
            if session_id:
                if player_id and session_id not in q["session_id"]["$in"]:return {"total":0,"offset":offset,"limit":limit,"rows":[],"has_more":False}
                q["session_id"]=session_id
            if event_id:q["_id"]=event_id
            if event_type:q["event_type"]=event_type
            total=target.gameplay_events.count_documents(q);rows=[]
            for doc in target.gameplay_events.find(q).sort([("received_at",-1),("_id",-1)]).skip(offset).limit(limit):
                session=target.game_sessions.find_one({"_id":doc.get("session_id")})
                run=target.problem_runs.find_one({"_id":doc.get("run_id")}) if doc.get("run_id") else None
                attempt=target.solution_attempts.find_one({"_id":doc.get("attempt_id")}) if doc.get("attempt_id") else None
                valid=bool(session) and (not doc.get("run_id") or bool(run) and run.get("session_id")==doc.get("session_id")) and (not doc.get("attempt_id") or bool(attempt) and attempt.get("run_id")==doc.get("run_id"))
                payload={**doc,"event_id":doc["_id"],"player_id":session.get("player_id") if session else None}
                rows.append({"receipt_id":doc["_id"],"payload":payload,"state":"processed" if valid else "pending","quarantine_reason":None,"learning_stored":True,"runtime_stored":bool(session),"exit_stored":False,"source":"server_mongodb","session":session,"run":run,"attempt":attempt})
            return {"total":total,"offset":offset,"limit":limit,"rows":rows,"has_more":offset+len(rows)<total}
        except Exception:
            raise HTTPException(503,"서버 MongoDB 조회에 실패했습니다. 연결 상태를 확인해 주세요")
        finally:client.close()
    return api
