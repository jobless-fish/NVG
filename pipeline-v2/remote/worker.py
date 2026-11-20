"""Single durable export worker. Never resets existing 'stored' history or target data."""
import json
import os
import socket
import time
import atexit
import signal
import threading
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
import pymysql
from pymongo import MongoClient, ReturnDocument
from pymongo.errors import DuplicateKeyError
from remote.projection import Projector, Waiting, Conflict, dt


def now():
    return datetime.now(timezone.utc)

def sql_connect():
    return pymysql.connect(host=os.environ["DIRECT_MYSQL_HOST"], port=int(os.getenv("DIRECT_MYSQL_PORT", "3306")),
                           user=os.environ["DIRECT_MYSQL_USER"], password=os.environ["DIRECT_MYSQL_PASSWORD"],
                           database=os.getenv("DIRECT_MYSQL_DATABASE", "nodeverse"), charset="utf8mb4",
                           connect_timeout=5, read_timeout=6, write_timeout=6, autocommit=False)

def contexts():
    p = Path(os.getenv("REMOTE_CONTEXT_PATH", "/run/private/remote-context.json"))
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {"members": {}}


def claim(local):
    # Earliest due work wins; a low-sequence context retry must not starve arrivals.
    return local.remote_event_outbox.find_one_and_update(
        {"state": {"$in": ["pending", "retrying", "waiting_context"]}, "next_attempt_at": {"$lte": now()}},
        {"$set": {"state": "processing", "updated_at": now()}, "$inc": {"attempts": 1}},
        sort=[("next_attempt_at", 1), ("queued_at", 1), ("sequence", 1), ("_id", 1)],
        return_document=ReturnDocument.AFTER)

def acquire(local, owner):
    try:
        doc = local.remote_worker_lease.find_one_and_update(
            {"_id": "writer", "$or": [{"owner": owner}, {"expires_at": {"$lte": now()}}]},
            {"$set": {"owner": owner, "expires_at": now() + timedelta(seconds=45)}},
            upsert=True, return_document=ReturnDocument.AFTER)
        return doc.get("owner") == owner
    except DuplicateKeyError:
        return False

def mirror_metrics(local, remote):
    for name in ["rt_minigame_1m", "rt_alerts", "rt_updates", "rt_versions", "rt_summary"]:
        for source in local[name].find({}):
            if not isinstance(source.get("updated_at"), datetime):
                continue
            doc = dict(source, sink_source="nodeverse-v2")
            # Atomic timestamp guard: a delayed older projection must not overwrite a newer aggregate.
            remote[name].update_one({"_id": doc["_id"]}, [{"$replaceWith": {"$cond": [
                {"$gte": [{"$literal": doc["updated_at"]}, {"$ifNull": ["$updated_at", datetime(1970,1,1,tzinfo=timezone.utc)]}]},
                {"$literal": doc}, "$$ROOT"]}}], upsert=True)
    keep = [x["_id"] for x in local.rt_versions.find({}, {"_id":1})]
    remote.rt_versions.delete_many({"sink_source":"nodeverse-v2", "_id":{"$nin":keep}})

def main():
    lc = MongoClient(os.getenv("MONGO_URI", "mongodb://mongo:27017"), tz_aware=True, serverSelectionTimeoutMS=5000, socketTimeoutMS=7000)
    local = lc[os.getenv("MONGO_DB", "nodeverse_logs")]
    rc = MongoClient(os.environ["DIRECT_MONGO_URI"], tz_aware=True, serverSelectionTimeoutMS=5000, socketTimeoutMS=7000)
    remote = rc[os.getenv("DIRECT_MONGO_DATABASE", "nodeverse_logs")]
    owner = socket.gethostname() + ":" + str(uuid.uuid4())
    local.remote_event_outbox.create_index([("state",1),("next_attempt_at",1)])
    last_metrics = 0.0
    recovered = False
    stop = threading.Event()
    def release():
        stop.set()
        try:
            local.remote_worker_lease.delete_one({"_id":"writer","owner":owner})
        except Exception:
            pass
    atexit.register(release)
    def shutdown(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown)
    def heartbeat():
        while not stop.wait(10):
            try:
                local.remote_worker_lease.update_one({"_id":"writer","owner":owner},
                    {"$set":{"expires_at":now()+timedelta(seconds=45)}})
            except Exception:
                pass
    threading.Thread(target=heartbeat, daemon=True).start()
    while True:
        sql = None
        try:
            if not acquire(local, owner):
                time.sleep(2)
                continue
            local.remote_event_outbox.update_many(
                {"state":"processing","updated_at":{"$lt":now()-timedelta(minutes=5)}},
                {"$set":{"state":"pending","next_attempt_at":now()}})
            if not recovered:
                local.remote_event_outbox.update_many({"state":"processing"}, {"$set":{"state":"pending","next_attempt_at":now()}})
                recovered = True
            if time.monotonic() - last_metrics >= 5:
                mirror_metrics(local, remote)
                last_metrics = time.monotonic()
            job = claim(local)
            if job is None:
                local.remote_sink_health.update_one({"_id":"worker"},{"$set":{"state":"ready","updated_at":now()}},upsert=True)
                time.sleep(0.5)
                continue
            try:
                event = job["event"]
                Projector(local, remote, None, {}).archive(event)
                local.remote_event_outbox.update_one({"_id": job["_id"], "remote_archive_stored_at": {"$exists": False}},
                    {"$set": {"archive_stored": True, "remote_archive_stored_at": now()}})
                local.remote_sink_health.update_one({"_id":"worker"}, {"$set":{"state":"processing","updated_at":now()}}, upsert=True)
                if event.get("schema_version") == 2 and event.get("session_id"):
                    sql = sql_connect()
                    with sql.cursor() as cursor:
                        cursor.execute("SELECT GET_LOCK('nodeverse_direct_loader',0)")
                        if cursor.fetchone()[0] != 1:
                            raise Waiting("other_database_writer_active")
                result = Projector(local, remote, sql, contexts()).project(event)
                state = "quarantined" if result.get("scope") == "learning_quarantine" else "stored"
                completed = now()
                local.remote_event_outbox.update_one({"_id":job["_id"]},{"$set":{
                    "state":state,"completed_at":completed,
                    ("quarantined_at" if state == "quarantined" else "stored_at"):completed,
                    "updated_at":completed,"result":result,"archive_stored":True,
                    "queue_to_terminal_ms":max(0,int((completed-job["queued_at"]).total_seconds()*1000))},
                    "$unset":{"reason":"","last_error":""}})
            except Waiting as e:
                archived = remote["pipeline_learning_events"].find_one({"_id":job["_id"]},{"_id":1}) is not None
                local.remote_event_outbox.update_one({"_id":job["_id"]},{"$set":{
                    "state":"waiting_context","reason":str(e),"archive_stored":archived,
                    "updated_at":now(),"next_attempt_at":now()+timedelta(seconds=min(60,5*2**min(job["attempts"]-1,4)))}})
            except (Conflict, ValueError, KeyError, TypeError) as e:
                local.remote_event_outbox.update_one({"_id":job["_id"]},{"$set":{
                    "state":"blocked","reason":str(e)[:200],"updated_at":now()}})
            except Exception as e:
                local.remote_event_outbox.update_one({"_id":job["_id"]},{"$set":{
                    "state":"retrying","last_error":type(e).__name__,"updated_at":now(),
                    "next_attempt_at":now()+timedelta(seconds=min(60,2**min(job["attempts"],5)))}})
        except Exception as e:
            # Never log credentials/connection strings or raw DB error text.
            try:
                local.remote_sink_health.update_one({"_id":"worker"},{"$set":{
                    "state":"error","error_type":type(e).__name__,"updated_at":now()}},upsert=True)
            except Exception:
                pass
            print(json.dumps({"component":"remote_sink","error":type(e).__name__}),flush=True)
            time.sleep(3)
        finally:
            if sql is not None:
                sql.close()

if __name__ == "__main__":
    main()
