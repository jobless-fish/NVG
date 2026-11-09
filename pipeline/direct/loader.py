"""Explicit direct loading. No source-database migration or automatic forwarding."""
import argparse,copy,json,os,sqlite3,sys,uuid,hashlib
from pathlib import Path
from datetime import datetime,timezone,timedelta
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"handoff"))
from client import validate,sample
COLLECTIONS={"session":"game_sessions","problem":"game_problems","run":"problem_runs","attempt":"solution_attempts","event":"gameplay_events"}
FIELDS={"session":{"id","player_id","topic","started_at","level","game_version"},"problem":{"id","task_id","content_version","title","topic"},"run":{"id","session_id","task_id","started_at"},"attempt":{"id","run_id","number","started_at"},"event":{"id","session_id","run_id","attempt_id","sequence","event_type","occurred_at","operation","failure_reason","state_before","state_after","hint_id","hint_step","payload"}}
class Conflict(ValueError):pass

def dt(value):
    t=datetime.fromisoformat(value.replace("Z","+00:00")).astimezone(timezone.utc)
    if t>datetime.now(timezone.utc)+timedelta(minutes=5):raise ValueError("Timestamp too far in future")
    return t.replace(microsecond=t.microsecond//1000*1000)

def manifest_check(manifest):
    if not manifest or manifest[0]["path"]!="/api/game/player-login":raise ValueError("Member must be first")
    if sum(e["path"]=="/api/game/player-login" for e in manifest)!=1:raise ValueError("One member per batch")
    for entry in manifest:
        validate(entry["path"],entry["body"])
        if entry["path"].endswith("records"):
            kind=entry["body"]["record_type"];data=entry["body"]["data"]
            allowed=FIELDS.get(kind,{"id","status","ended_at"})
            if set(data)-allowed:raise ValueError("Unknown fields require contract review")
    return manifest

def connect():
    import pymysql
    from pymongo import MongoClient
    required=["DIRECT_MYSQL_HOST","DIRECT_MYSQL_USER","DIRECT_MYSQL_PASSWORD","DIRECT_MONGO_URI","DIRECT_SESSION_OPEN_STATUS","DIRECT_RUN_OPEN_STATUS","DIRECT_ATTEMPT_OPEN_OUTCOME"]
    if any(not os.environ.get(k) for k in required):raise ValueError("Missing direct database credentials or lifecycle configuration")
    sql=pymysql.connect(host=os.environ["DIRECT_MYSQL_HOST"],port=int(os.environ.get("DIRECT_MYSQL_PORT","3306")),user=os.environ["DIRECT_MYSQL_USER"],password=os.environ["DIRECT_MYSQL_PASSWORD"],database=os.environ.get("DIRECT_MYSQL_DATABASE","nodeverse"),charset="utf8mb4",autocommit=False,connect_timeout=5)
    mongo=MongoClient(os.environ["DIRECT_MONGO_URI"],tz_aware=True,serverSelectionTimeoutMS=5000)[os.environ.get("DIRECT_MONGO_DATABASE","nodeverse_logs")]
    return sql,mongo

class Loader:
    def __init__(self,sql,mongo):self.sql=sql;self.db=mongo
    def preflight(self):
        self.db.command("ping")
        with self.sql.cursor() as c:
            c.execute("SELECT VERSION()");version=c.fetchone()[0]
            c.execute("SHOW COLUMNS FROM game_members");schema=c.fetchall();columns={r[0] for r in schema}
            if not any(r[0]=="member_id" and r[1].lower()=="char(32)" for r in schema):raise ValueError("Member UUID must be CHAR(32)")
            if not {"member_id","external_member_key","nickname","data_source","registered_at"}<=columns:raise ValueError("Member schema mismatch")
            c.execute("SHOW INDEX FROM game_members");idx=c.fetchall()
            groups={}
            for x in idx:
                if x[1]==0:groups.setdefault(x[2],[]).append((x[3],x[4]))
            if not any([v for _,v in sorted(g)]==["external_member_key"] for g in groups.values()):raise ValueError("External key unique index required")
        existing=set(self.db.list_collection_names())
        if not set(COLLECTIONS.values())<=existing:raise ValueError("Target collections must already exist")
        for coll,keys in [("game_problems",["task_id","content_version"]),("solution_attempts",["run_id","number"]),("gameplay_events",["session_id","sequence"])]:
            if not any(i.get("unique") and list(i["key"])==keys for i in self.db[coll].list_indexes()):raise ValueError("Required unique index missing")
        self.sql.rollback()
        with self.sql.cursor() as c:
            c.execute("SELECT @@server_uuid");server_uuid=c.fetchone()[0]
        self.identity={"mysql_uuid":server_uuid,"mysql_db":self.sql.db.decode() if isinstance(self.sql.db,bytes) else self.sql.db,"mongo_host":self.db.client.address,"mongo_db":self.db.name}
        self.sql.rollback()
        return {"mysql_version":version,"mongo_version":self.db.client.server_info()["version"],"schema":"checked"}
    def member(self,data):
        import pymysql
        key="game:member:"+data["member_id"]
        for attempt in range(2):
            try:
                with self.sql.cursor() as c:
                    c.execute("SELECT member_id,external_member_key,data_source FROM game_members WHERE external_member_key=%s FOR UPDATE",(key,));row=c.fetchone()
                    if row:
                        if row[1]!=key or row[2]!="live":raise Conflict("External member key collision")
                        player=str(uuid.UUID(row[0]));c.execute("UPDATE game_members SET nickname=%s WHERE member_id=%s",(data["display_name"],uuid.UUID(player).hex))
                    else:
                        player=str(uuid.uuid4());c.execute("INSERT INTO game_members(member_id,external_member_key,nickname,data_source,registered_at) VALUES(%s,%s,%s,%s,%s)",(uuid.UUID(player).hex,key,data["display_name"],"live",datetime.now(timezone.utc).replace(tzinfo=None)))
                self.sql.commit();return player
            except pymysql.IntegrityError:
                self.sql.rollback()
                if attempt:raise Conflict("Member uniqueness conflict")
            except Exception:self.sql.rollback();raise
    def required(self,coll,ident):
        obj=self.db[coll].find_one({"_id":ident})
        if not obj:raise Conflict("Missing referenced "+coll)
        return obj
    def record(self,kind,data):
        if kind.startswith("end_"):return self.finish(kind,data)
        from pymongo.errors import DuplicateKeyError
        doc={k:v for k,v in data.items() if k!="id"};doc["_id"]=str(uuid.UUID(data["id"]))
        for k in ["player_id","session_id","run_id","attempt_id"]:
            if k in doc:doc[k]=str(uuid.UUID(doc[k]))
        if kind=="run":doc["task_id"]=str(uuid.UUID(doc["task_id"]))
        for k in ["started_at","occurred_at"]:
            if k in doc:doc[k]=dt(doc[k])
        col=self.db[COLLECTIONS[kind]];old=col.find_one({"_id":doc["_id"]})
        if old:
            if all(old.get(k)==v for k,v in doc.items()):return
            raise Conflict("ID content conflict")
        if kind=="session":
            with self.sql.cursor() as c:
                c.execute("SELECT member_id FROM game_members WHERE member_id=%s AND data_source='live'",(uuid.UUID(doc["player_id"]).hex,))
                if not c.fetchone():raise Conflict("Unknown member UUID")
            self.sql.rollback();doc.update(status=os.environ["DIRECT_SESSION_OPEN_STATUS"],ended_at=None)
        if kind=="run":
            s=self.required("game_sessions",doc["session_id"]);p=self.required("game_problems",doc["task_id"])
            if s["status"]!=os.environ["DIRECT_SESSION_OPEN_STATUS"] or s["topic"]!=p["topic"] or doc["started_at"]<s["started_at"]:raise Conflict("Run/session relation invalid")
            doc.update(status=os.environ["DIRECT_RUN_OPEN_STATUS"],ended_at=None)
        if kind=="attempt":
            run=self.required("problem_runs",doc["run_id"])
            if run["status"]!=os.environ["DIRECT_RUN_OPEN_STATUS"] or doc["started_at"]<run["started_at"]:raise Conflict("Attempt/run relation invalid")
            doc.update(outcome=os.environ["DIRECT_ATTEMPT_OPEN_OUTCOME"],ended_at=None)
        if kind=="event":
            allowed=set(os.environ.get("DIRECT_EVENT_TYPES","operation_succeeded,operation_failed,hint").split(","))
            if doc["event_type"] not in allowed:raise Conflict("Event type needs agreed mapping")
            session=self.required("game_sessions",doc["session_id"])
            if session["status"]!=os.environ["DIRECT_SESSION_OPEN_STATUS"] or doc["occurred_at"]<session["started_at"]:raise Conflict("Session closed or invalid event time")
            if "run_id" not in doc or "attempt_id" not in doc:raise Conflict("Structured event references required")
            run=self.required("problem_runs",doc["run_id"]);attempt=self.required("solution_attempts",doc["attempt_id"])
            if run["session_id"]!=doc["session_id"] or attempt["run_id"]!=doc["run_id"] or run["status"]!=os.environ["DIRECT_RUN_OPEN_STATUS"] or attempt["outcome"]!=os.environ["DIRECT_ATTEMPT_OPEN_OUTCOME"] or doc["occurred_at"]<attempt["started_at"]:raise Conflict("Event relation or time invalid")
            doc["received_at"]=datetime.now(timezone.utc)
        try:col.insert_one(doc)
        except DuplicateKeyError:raise Conflict("Unique key conflict; inspect before retry")
    def finish(self,kind,data):
        if os.environ.get("DIRECT_FINALIZATION_POLICY_CONFIRMED")!="1":raise ValueError("Agree finalization and time policies before ending records")
        coll={"end_session":"game_sessions","end_run":"problem_runs","end_attempt":"solution_attempts"}[kind];old=self.required(coll,str(uuid.UUID(data["id"])));ended=dt(data["ended_at"]);field="outcome" if kind=="end_attempt" else "status"
        if old.get("ended_at") is not None:
            if old["ended_at"]==ended and old[field]==data["status"]:return
            raise Conflict("Already finalized with other content")
        if ended<old["started_at"]:raise Conflict("End precedes start")
        if kind=="end_session" and self.db.problem_runs.count_documents({"session_id":old["_id"],"ended_at":None}):raise Conflict("Runs still open")
        if kind=="end_run" and self.db.solution_attempts.count_documents({"run_id":old["_id"],"ended_at":None}):raise Conflict("Attempts still open")
        event_filter={"attempt_id" if kind=="end_attempt" else "run_id" if kind=="end_run" else "session_id":old["_id"],"occurred_at":{"$gt":ended}}
        if self.db.gameplay_events.count_documents(event_filter):raise Conflict("Events after end")
        update={field:data["status"],"ended_at":ended}
        if kind=="end_session":update["duration_ms"]=int((ended-old["started_at"]).total_seconds()*1000)
        if self.db[coll].update_one({"_id":old["_id"],"ended_at":None},{"$set":update}).modified_count!=1:raise Conflict("Concurrent finalization")

def apply(manifest,journal,loader):
    manifest_check(manifest);digest=hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()
    journal=Path(journal);journal.parent.mkdir(parents=True,exist_ok=True);db=sqlite3.connect(journal)
    db.execute("CREATE TABLE IF NOT EXISTS batch(hash TEXT PRIMARY KEY)");db.execute("CREATE TABLE IF NOT EXISTS progress(n INTEGER PRIMARY KEY,player TEXT)")
    old=db.execute("SELECT hash FROM batch").fetchone()
    if old and old[0]!=digest:raise Conflict("Journal belongs to another immutable manifest")
    with db:db.execute("INSERT OR IGNORE INTO batch VALUES(?)",(digest,))
    try:
        loader.preflight()
        db.execute("CREATE TABLE IF NOT EXISTS destination(identity TEXT)")
        identity=json.dumps(loader.identity,sort_keys=True)
        prior=db.execute("SELECT identity FROM destination").fetchone()
        if prior and prior[0]!=identity:raise Conflict("Journal belongs to another destination")
        if not prior:
            with db:db.execute("INSERT INTO destination VALUES(?)",(identity,))
        for i,entry in enumerate(manifest):
            if db.execute("SELECT n FROM progress WHERE n=?",(i,)).fetchone():continue
            body=copy.deepcopy(entry["body"]);player=None
            if entry["path"].endswith("player-login"):player=loader.member(body)
            else:
                if body["record_type"]=="session" and body["data"]["player_id"]=="$player_id":body["data"]["player_id"]=db.execute("SELECT player FROM progress WHERE n=0").fetchone()[0]
                loader.record(body["record_type"],body["data"])
            with db:db.execute("INSERT INTO progress VALUES(?,?)",(i,player))
        return {"state":"applied","records":len(manifest)}
    finally:db.close()

def main():
    p=argparse.ArgumentParser();p.add_argument("action",choices=["sample","plan","check","apply"]);p.add_argument("--manifest",type=Path);p.add_argument("--journal",type=Path);p.add_argument("--output",type=Path);a=p.parse_args()
    if a.action=="sample":
        if a.output.exists():raise ValueError("Do not overwrite immutable sample")
        a.output.write_text(json.dumps(sample(),ensure_ascii=False,indent=2),encoding="utf-8");print("Sample created; no DB connected");return
    if a.action=="plan":
        m=manifest_check(json.loads(a.manifest.read_text(encoding="utf-8")));print(json.dumps({"mode":"dry-run","mysql_table":"game_members","records":len(m),"record_types":[x["body"].get("record_type","member") for x in m],"db_connected":False}));return
    if a.action=="apply" and os.environ.get("DIRECT_EXCLUSIVE_WRITER")!="1":raise ValueError("Confirm exclusive writer coordination before apply")
    sql,mongo=connect();loader=Loader(sql,mongo)
    try:
        if a.action=="check":print(json.dumps(loader.preflight()))
        else:
            with sql.cursor() as c:
                c.execute("SELECT GET_LOCK('nodeverse_direct_loader',0)")
                if c.fetchone()[0]!=1:raise Conflict("Another loader is active")
            print(json.dumps(apply(json.loads(a.manifest.read_text(encoding="utf-8")),a.journal,loader)))
    finally:sql.close();mongo.client.close()
if __name__=="__main__":main()
