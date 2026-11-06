import os, json, secrets
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime
from confluent_kafka import Producer
app = FastAPI(title="NODEVERSE event gateway")
p = Producer({"bootstrap.servers":"kafka:9092", "enable.idempotence":True, "acks":"all", "message.timeout.ms":5000})
class Event(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal[1] = 1
    event_id: UUID
    player_id: str = Field(min_length=1,max_length=128)
    session_id: str = Field(min_length=1,max_length=128)
    problem_id: str = Field(min_length=1,max_length=128)
    attempt_id: str = Field(min_length=1,max_length=128)
    event_type: Literal["problem_started","attempt_started","operation","attempt_failed","hint_used","attempt_succeeded"]
    occurred_at: AwareDatetime
    sequence: int = Field(ge=0)
    duration_ms: int = Field(default=0,ge=0,le=86400000)
@app.get("/health")
def health():
    try: p.list_topics(timeout=3)
    except Exception: raise HTTPException(503,"Kafka unavailable")
    return {"status":"ready"}
@app.post("/v1/events",status_code=202)
def ingest(event: Event, x_api_key: str = Header(default="")):
    if not secrets.compare_digest(x_api_key, os.environ["INGEST_KEY"]):
        raise HTTPException(401,"Invalid ingestion key")
    if event.occurred_at > datetime.now(timezone.utc).replace(microsecond=0) + __import__('datetime').timedelta(minutes=5):
        raise HTTPException(422,"Event timestamp is in the future")
    payload=event.model_dump(mode="json")
    payload["received_at"]=datetime.now(timezone.utc).isoformat()
    result=[]
    try:
        p.produce("game.events.v1",key=event.session_id,value=json.dumps(payload),on_delivery=lambda err,msg: result.append(err))
        p.flush(6)
    except Exception: raise HTTPException(503,"Retry with the same event_id")
    if not result or result[0] is not None: raise HTTPException(503,"Retry with the same event_id")
    return {"event_id":str(event.event_id),"status":"accepted"}
