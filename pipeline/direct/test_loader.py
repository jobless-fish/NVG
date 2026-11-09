import copy,json,os,sqlite3,tempfile,uuid
from pathlib import Path
from datetime import datetime,timezone,timedelta
from loader import connect,Loader,apply,sample,Conflict,manifest_check
# Fresh isolated databases per test invocation, with no delete/drop.
import pymysql
fixture="check_"+uuid.uuid4().hex[:12]
bootstrap=pymysql.connect(host=os.environ["DIRECT_MYSQL_HOST"],user=os.environ["DIRECT_MYSQL_USER"],password=os.environ["DIRECT_MYSQL_PASSWORD"])
with bootstrap.cursor() as c:c.execute("CREATE DATABASE `"+fixture+"`")
bootstrap.close();os.environ["DIRECT_MYSQL_DATABASE"]=fixture;os.environ["DIRECT_MONGO_DATABASE"]=fixture
sql,db=connect()
with sql.cursor() as c:
    c.execute("CREATE TABLE game_members(member_id CHAR(32) PRIMARY KEY,external_member_key VARCHAR(150) UNIQUE NOT NULL,nickname VARCHAR(80) NOT NULL,data_source VARCHAR(8) NOT NULL,registered_at DATETIME(6) NOT NULL)")
sql.commit()
for name in ["game_sessions","game_problems","problem_runs","solution_attempts","gameplay_events"]:db.create_collection(name)
db.game_problems.create_index([("task_id",1),("content_version",1)],unique=True)
db.solution_attempts.create_index([("run_id",1),("number",1)],unique=True)
db.gameplay_events.create_index([("session_id",1),("sequence",1)],unique=True)
loader=Loader(sql,db);manifest=sample()
with tempfile.TemporaryDirectory() as tmp:
    journal=Path(tmp)/"progress.sqlite"
    assert apply(manifest,journal,loader)["state"]=="applied"
    assert db.gameplay_events.count_documents({})==1
    assert apply(manifest,journal,loader)["state"]=="applied"
    assert db.gameplay_events.count_documents({})==1
    # Simulate process death after DB commit but before journal acknowledgement.
    local=sqlite3.connect(journal);local.execute("DELETE FROM progress WHERE n=5");local.commit();local.close()
    apply(manifest,journal,loader);assert db.gameplay_events.count_documents({})==1
    session=db.game_sessions.find_one();member=loader.member(manifest[0]["body"])
    assert session["player_id"]==member
    with sql.cursor() as c:
        c.execute("SELECT member_id FROM game_members");assert c.fetchone()[0]==uuid.UUID(member).hex
    event=manifest[-1]["body"]["data"];bad=copy.deepcopy(event);bad["operation"]="push"
    try:loader.record("event",bad);raise AssertionError("conflict accepted")
    except Conflict:pass
    bad=copy.deepcopy(event);bad["id"]=str(uuid.uuid4());bad["run_id"]=str(uuid.uuid4())
    try:loader.record("event",bad);raise AssertionError("orphan accepted")
    except Conflict:pass
    bad=copy.deepcopy(event);bad["id"]=str(uuid.uuid4())
    try:loader.record("event",bad);raise AssertionError("sequence collision accepted")
    except Conflict:pass
    ended=(datetime.now(timezone.utc)+timedelta(seconds=1)).isoformat()
    loader.record("end_attempt",{"id":manifest[4]["body"]["data"]["id"],"status":"success","ended_at":ended})
    loader.record("end_run",{"id":manifest[3]["body"]["data"]["id"],"status":"completed","ended_at":ended})
    loader.record("end_session",{"id":session["_id"],"status":"completed","ended_at":ended})
    loader.record("end_session",{"id":session["_id"],"status":"completed","ended_at":ended})
    assert db.game_sessions.find_one()["duration_ms"]>=0
    assert isinstance(db.gameplay_events.find_one()["occurred_at"],datetime)
    changed=copy.deepcopy(manifest);changed[0]["body"]["display_name"]="changed"
    try:apply(changed,journal,loader);raise AssertionError("manifest change accepted")
    except Conflict:pass
print(json.dumps({"pass":True,"test_environment":"isolated MySQL 8.4 / MongoDB 8.0; not receiver server","checks":["preflight","member UUID mapping","six ordered writes","idempotent replay","resume after DB commit","content conflict","orphan rejection","sequence uniqueness","end lifecycle","UTC BSON datetime","immutable journal"]}))
sql.close();db.client.close()
