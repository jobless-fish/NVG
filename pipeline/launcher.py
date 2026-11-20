"""Windows EXE launcher. Standard-library only; persistent outbox and next-run recovery."""
import argparse, json, os, sqlite3, subprocess, time, uuid, urllib.request, urllib.error
from datetime import datetime, timezone
from pathlib import Path

def now(): return datetime.now(timezone.utc).isoformat()
class Outbox:
    def __init__(self, folder):
        folder.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(folder / "telemetry.sqlite")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("CREATE TABLE IF NOT EXISTS queue(id TEXT PRIMARY KEY, body TEXT, state TEXT DEFAULT 'pending')")
        self.db.execute("CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, body TEXT)")
    def enqueue(self,event):
        self.db.execute("INSERT OR IGNORE INTO queue(id,body) VALUES(?,?)",(event["event_id"],json.dumps(event)))
        self.db.commit()
    def flush(self,url,key):
        for ident,body in self.db.execute("SELECT id,body FROM queue WHERE state='pending' LIMIT 50").fetchall():
            request=urllib.request.Request(url+"/v1/events",data=body.encode(),headers={"Content-Type":"application/json","X-API-Key":key})
            try:
                with urllib.request.urlopen(request,timeout=2) as response:
                    if response.status != 202: return
                self.db.execute("DELETE FROM queue WHERE id=?",(ident,))
                self.db.commit()
            except urllib.error.HTTPError as error:
                if error.code in (401,422):
                    self.db.execute("UPDATE queue SET state=? WHERE id=?",("rejected_"+str(error.code),ident));self.db.commit()
                return
            except (OSError,TimeoutError): return

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("exe",type=Path)
    parser.add_argument("--build",required=True)
    parser.add_argument("--url",default="http://127.0.0.1:8000")
    parser.add_argument("--data",type=Path,default=Path(os.environ.get("LOCALAPPDATA",str(Path.home()))) / "NODEVERSE" / "telemetry")
    args=parser.parse_args()
    if not args.exe.is_file(): parser.error("EXE does not exist")
    key=os.environ.get("INGEST_KEY","")
    if not key: parser.error("Set INGEST_KEY")
    box=Outbox(args.data)
    identity=args.data / "installation_id"
    if not identity.exists(): identity.write_text(str(uuid.uuid4()))
    def event(base,kind,evidence,**extra):
        return {**base,"event_id":str(uuid.uuid4()),"occurred_at":now(),"event_type":kind,"evidence":evidence,**extra}
    # Persist recovery report and deletion together so recovery itself can be interrupted.
    with box.db:
        for rid,body in box.db.execute("SELECT id,body FROM runs").fetchall():
            report=event(json.loads(body),"exit_unexpected_unknown","next_launch_recovery")
            box.db.execute("INSERT INTO queue(id,body) VALUES(?,?)",(report["event_id"],json.dumps(report)))
            box.db.execute("DELETE FROM runs WHERE id=?",(rid,))
    base={"schema_version":1,"run_id":str(uuid.uuid4()),"player_id":identity.read_text().strip(),"build_version":args.build}
    box.db.execute("INSERT INTO runs VALUES(?,?)",(base["run_id"],json.dumps(base)));box.db.commit()
    box.enqueue(event(base,"run_started","launcher_observed"))
    marker=args.data / (base["run_id"]+".normal")
    env={**os.environ,"NODEVERSE_RUN_ID":base["run_id"],"NODEVERSE_EXIT_MARKER":str(marker)}
    process=subprocess.Popen([str(args.exe.resolve())],cwd=args.exe.resolve().parent,env=env)
    try:
        last=0
        while process.poll() is None:
            if time.monotonic()-last>=15:
                box.enqueue(event(base,"run_heartbeat","launcher_observed"));last=time.monotonic()
                box.flush(args.url,key)
            time.sleep(0.5)
        # Exit code 0 alone is not proof of normal game shutdown.
        normal=marker.exists() and marker.read_text().strip()==base["run_id"]
        report=event(base,"exit_normal" if normal else "exit_unexpected_unknown","game_shutdown_complete" if normal else "launcher_observed",exit_code=process.returncode)
        with box.db:
            box.db.execute("INSERT INTO queue(id,body) VALUES(?,?)",(report["event_id"],json.dumps(report)))
            box.db.execute("DELETE FROM runs WHERE id=?",(base["run_id"],))
        marker.unlink(missing_ok=True)
        box.flush(args.url,key)
    finally: box.db.close()
if __name__=="__main__": main()
