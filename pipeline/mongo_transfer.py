"""Offline bundled-MongoDB transfer. No drop/overwrite; credentials never printed."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent

def command(project,*args,capture=False):
    result=subprocess.run(["docker","compose","--project-name",project,"--project-directory",str(HERE),"-f",str(HERE/"compose.yaml"),"--profile","lab",*args],check=True,capture_output=capture)
    return result.stdout if capture else None

def snapshot(project,db):
    script='const d=db.getSiblingDB('+json.dumps(db)+'); print(JSON.stringify(d.getCollectionNames().sort().map(n=>({name:n,count:d[n].countDocuments({}),indexes:d[n].getIndexes().map(x=>{delete x.v;delete x.ns;return x;}).sort((a,b)=>a.name.localeCompare(b.name))}))));'
    return json.loads(command(project,"exec","-T","mongo","mongosh","--quiet","--eval",script,capture=True))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("action",choices=["backup","restore","verify"])
    p.add_argument("--project",default="pipeline")
    p.add_argument("--database",default="nodeverse")
    p.add_argument("--folder",type=Path,required=True)
    a=p.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+",a.database):p.error("Invalid database name")
    folder=a.folder.resolve();archive=folder/"mongo.archive.gz";manifest=folder/"manifest.json"
    if a.action=="backup":
        if folder.exists() and any(folder.iterdir()):p.error("Backup directory must be new or empty")
        folder.mkdir(parents=True,exist_ok=True)
        # Keep Mongo online, stop every bundled writer; do not silently resume writes.
        command(a.project,"stop","lab","gateway","raw-worker","spark")
        before=snapshot(a.project,a.database)
        with archive.open("wb") as target:
            subprocess.run(["docker","compose","--project-name",a.project,"--project-directory",str(HERE),"-f",str(HERE/"compose.yaml"),"exec","-T","mongo","mongodump","--db",a.database,"--archive","--gzip"],stdout=target,check=True)
        after=snapshot(a.project,a.database)
        if before!=after:raise RuntimeError("Database changed during backup; snapshot not certified")
        data={"format":1,"database":a.database,"created_at":datetime.now(timezone.utc).isoformat(),"mongo_image":"mongo:7.0.16","sha256":hashlib.sha256(archive.read_bytes()).hexdigest(),"collections":after,"scope":"MongoDB only; Kafka backlog and Spark checkpoints are NOT included"}
        manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
        print("Backup verified. Writers remain STOPPED. Resume with your original compose options.")
        return
    data=json.loads(manifest.read_text(encoding="utf-8"))
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=data["sha256"]:raise RuntimeError("Archive checksum mismatch")
    if a.action=="restore":
        if snapshot(a.project,a.database):raise RuntimeError("Target database is not empty; restore refused")
        with archive.open("rb") as source:
            subprocess.run(["docker","compose","--project-name",a.project,"--project-directory",str(HERE),"-f",str(HERE/"compose.yaml"),"exec","-T","mongo","mongorestore","--archive","--gzip","--stopOnError","--nsInclude",data["database"]+".*","--nsFrom",data["database"]+".*","--nsTo",a.database+".*"],stdin=source,check=True)
    actual=snapshot(a.project,a.database)
    result={"action":a.action,"target_project":a.project,"database":a.database,"archive_sha256":data["sha256"],"matches":actual==data["collections"],"collections":actual}
    (folder/(a.action+"-verification.json")).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    if not result["matches"]:raise RuntimeError("Collection counts or indexes differ")
    print("PASS: archive checksum, collection names, document counts, index definitions")
if __name__=="__main__":main()
