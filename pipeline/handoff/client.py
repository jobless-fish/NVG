"""Server-to-server client for the 2026-11-09 handoff contract (not /v1/events)."""
import argparse,copy,json,os,sqlite3,time,uuid,urllib.request,urllib.error,urllib.parse
from pathlib import Path
from datetime import datetime,timezone
FORBIDDEN={"password","password_hash","authorization","session_cookie","secret_key","admin_registration_code"}
REQUIRED={"session":{"id","player_id","topic","started_at"},"problem":{"id","task_id","content_version","title","topic"},"run":{"id","session_id","task_id","started_at"},"attempt":{"id","run_id","number","started_at"},"event":{"id","session_id","sequence","event_type","occurred_at"},"end_attempt":{"id","status","ended_at"},"end_run":{"id","status","ended_at"},"end_session":{"id","status","ended_at"}}

def safe_tree(value):
    if isinstance(value,dict):
        if any(k.lower() in FORBIDDEN for k in value):raise ValueError("Forbidden secret field")
        for v in value.values():safe_tree(v)
    elif isinstance(value,list):
        for v in value:safe_tree(v)

def validate(path,body):
    safe_tree(body)
    if path=="/api/game/player-login":
        import re
        if set(body)!={"member_id","display_name"}:raise ValueError("Member fields must match contract")
        if not isinstance(body["member_id"],str) or not re.fullmatch(r"[A-Za-z0-9_.@-]{1,120}",body["member_id"]):raise ValueError("Invalid member_id")
        name=body["display_name"]
        if not isinstance(name,str) or not name.strip() or len(name)>80 or any(ord(c)<32 or ord(c)==127 for c in name):raise ValueError("Invalid display_name")
        limit=4096
    elif path=="/api/game/records":
        if set(body)!={"record_type","data"}:raise ValueError("Invalid record envelope")
        kind=body["record_type"];data=body["data"]
        if kind not in REQUIRED or not isinstance(data,dict) or not REQUIRED[kind]<=set(data):raise ValueError("Missing record fields")
        for field in ["id","player_id","session_id","run_id","attempt_id"]:
            if field in data and data[field]!="$player_id":uuid.UUID(data[field])
        if kind=="run":uuid.UUID(data["task_id"])
        if "topic" in data and data["topic"] not in ["stack","queue","tree"]:raise ValueError("Invalid topic")
        for field in ["started_at","ended_at","occurred_at"]:
            if field in data and datetime.fromisoformat(data[field].replace("Z","+00:00")).tzinfo is None:raise ValueError("Timestamp needs timezone")
        for field in ["sequence","number","hint_step"]:
            if field in data and (type(data[field]) is not int or data[field]<1):raise ValueError("Counter must be >= 1")
        if kind.startswith("end_"):
            allowed=["success","failure","abandoned"] if kind=="end_attempt" else ["completed","abandoned"]
            if data["status"] not in allowed:raise ValueError("Invalid end status")
        if kind=="event":
            et=data["event_type"]
            if et in ["operation_succeeded","operation_failed"] and not {"run_id","attempt_id","operation"}<=set(data):raise ValueError("Operation references required")
            if et=="operation_failed" and not data.get("failure_reason"):raise ValueError("failure_reason required")
            if et=="hint" and not {"run_id","attempt_id","hint_id","hint_step"}<=set(data):raise ValueError("Structured hint fields required")
        for field in ["state_before","state_after","payload"]:
            if field in data and (not isinstance(data[field],dict) or len(json.dumps(data[field],ensure_ascii=False).encode())>16384):raise ValueError("Invalid structured payload")
        limit=65536
    else:raise ValueError("Unknown endpoint")
    if len(json.dumps(body,ensure_ascii=False).encode())>limit:raise ValueError("Request too large")

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None

class Client:
    def __init__(self,folder):
        folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(folder/"handoff.sqlite")
        self.db.execute("PRAGMA journal_mode=WAL");self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("CREATE TABLE IF NOT EXISTS jobs(id INTEGER PRIMARY KEY, path TEXT, body TEXT, state TEXT DEFAULT 'pending', status INTEGER, note TEXT)")
        self.db.execute("CREATE TABLE IF NOT EXISTS metadata(name TEXT PRIMARY KEY,value TEXT)")
    def enqueue(self,manifest):
        if self.db.execute("SELECT count(*) FROM jobs").fetchone()[0]:raise ValueError("Use a new folder for a new manifest; existing queue is immutable")
        for entry in manifest:validate(entry["path"],entry["body"])
        with self.db:
            self.db.executemany("INSERT INTO jobs(path,body) VALUES(?,?)",[(e["path"],json.dumps(e["body"],ensure_ascii=False)) for e in manifest])
    def flush(self,base,key,max_attempts=3):
        parsed=urllib.parse.urlsplit(base)
        if parsed.scheme not in ("http","https") or not parsed.hostname or parsed.username or parsed.password or parsed.path not in ("","/") or parsed.query or parsed.fragment:raise ValueError("Set API origin only, without path or credentials")
        if not key or any(c in key for c in "\r\n"):raise ValueError("GAME_SERVER_API_KEY missing or invalid")
        origin=parsed.scheme+"://"+parsed.netloc
        saved=self.db.execute("SELECT value FROM metadata WHERE name='origin'").fetchone()
        if saved and saved[0]!=origin:raise ValueError("Queue is bound to another API origin")
        with self.db:self.db.execute("INSERT OR IGNORE INTO metadata VALUES('origin',?)",(origin,))
        opener=urllib.request.build_opener(NoRedirect())
        for ident,path,body,state in self.db.execute("SELECT id,path,body,state FROM jobs WHERE state!='sent' ORDER BY id").fetchall():
            if state=="blocked":return {"state":"blocked","job":ident}
            payload=json.loads(body)
            if path=="/api/game/records" and payload["record_type"]=="session":
                mapping=self.db.execute("SELECT value FROM metadata WHERE name='player_id'").fetchone()
                if not mapping:raise ValueError("Member response must precede session")
                if payload["data"]["player_id"]=="$player_id":payload["data"]["player_id"]=mapping[0]
            validate(path,payload)
            for attempt in range(max_attempts):
                req=urllib.request.Request(origin+path,data=json.dumps(payload,ensure_ascii=False).encode(),headers={"Authorization":"Bearer "+key,"Content-Type":"application/json"})
                status=0;response={}
                try:
                    with opener.open(req,timeout=10) as res:status=res.status;response=json.load(res)
                except urllib.error.HTTPError as e:status=e.code
                except (OSError,TimeoutError):status=0
                except (ValueError,UnicodeError):status=502
                if status in (200,201):
                    try:
                        if path=="/api/game/player-login":player=str(uuid.UUID(response["player"]["player_id"]))
                        else:
                            if uuid.UUID(response["record_id"])!=uuid.UUID(payload["data"]["id"]):raise ValueError("Unexpected record ID")
                    except (KeyError,TypeError,ValueError):status=502
                    else:
                        with self.db:
                            if path=="/api/game/player-login":self.db.execute("INSERT OR REPLACE INTO metadata VALUES('player_id',?)",(player,))
                            self.db.execute("UPDATE jobs SET state='sent',status=?,note='accepted' WHERE id=?",(status,ident))
                        break
                transient=status==0 or status>=500
                with self.db:self.db.execute("UPDATE jobs SET state=?,status=?,note=? WHERE id=?",("pending" if transient else "blocked",status,"retry_same_body" if transient else "operator_review",ident))
                if not transient:return {"state":"blocked","job":ident,"status":status}
                if attempt+1<max_attempts:time.sleep(min(2**attempt,8))
            else:return {"state":"pending","job":ident,"status":status}
        return {"state":"sent","count":self.db.execute("SELECT count(*) FROM jobs").fetchone()[0]}

def sample():
    t=datetime.now(timezone.utc).isoformat();p=str(uuid.uuid5(uuid.NAMESPACE_URL,"nodeverse:stack-pop-test:integration-1"));s,r,a,e=[str(uuid.uuid4()) for _ in range(4)]
    return [{"path":"/api/game/player-login","body":{"member_id":"integration-"+uuid.uuid4().hex[:12],"display_name":"Integration Test"}},*[{"path":"/api/game/records","body":{"record_type":kind,"data":data}} for kind,data in [("problem",{"id":p,"task_id":"stack-pop-test","content_version":"integration-1","title":"Stack pop test","topic":"stack"}),("session",{"id":s,"player_id":"$player_id","topic":"stack","started_at":t}),("run",{"id":r,"session_id":s,"task_id":p,"started_at":t}),("attempt",{"id":a,"run_id":r,"number":1,"started_at":t}),("event",{"id":e,"session_id":s,"run_id":r,"attempt_id":a,"sequence":1,"event_type":"operation_succeeded","operation":"pop","occurred_at":t,"state_before":{"size":2},"state_after":{"size":1},"payload":{}})]]]

def main():
    p=argparse.ArgumentParser();p.add_argument("action",choices=["sample","queue","send","status"]);p.add_argument("--folder",type=Path,required=True);p.add_argument("--manifest",type=Path);args=p.parse_args()
    if args.action=="sample":
        args.folder.mkdir(parents=True,exist_ok=True);target=args.folder/"sample.json"
        if target.exists():raise ValueError("Sample already exists; preserve IDs for retries")
        target.write_text(json.dumps(sample(),ensure_ascii=False,indent=2),encoding="utf-8");print("Sample created; no network request made");return
    c=Client(args.folder)
    try:
        if args.action=="queue":c.enqueue(json.loads(args.manifest.read_text(encoding="utf-8")));print("Manifest queued")
        elif args.action=="send":print(json.dumps(c.flush(os.environ.get("HANDOFF_API_BASE_URL",""),os.environ.get("GAME_SERVER_API_KEY",""))))
        else:print(json.dumps(c.db.execute("SELECT id,path,state,status,note FROM jobs ORDER BY id").fetchall()))
    finally:c.db.close()
if __name__=="__main__":main()
