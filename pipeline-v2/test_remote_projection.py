import hashlib,uuid
from datetime import datetime,timedelta,timezone
import mongomock
import pytest
import remote.projection as projection
from remote.projection import Projector,Waiting,Conflict,uid
from remote.outbox import stage
@pytest.fixture
def dbs(monkeypatch):
 c=mongomock.MongoClient(tz_aware=True)
 monkeypatch.setattr(projection,"resolve_member",lambda *a:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
 return c.local,c.target

def rows():
 session,run,attempt=[str(uuid.uuid4()) for _ in range(3)];start=datetime.now(timezone.utc).replace(microsecond=0)
 return [{"schema_version":2,"event_id":str(uuid.uuid4()),"payload_hash":hashlib.sha256(str(i).encode()).hexdigest(),"player_id":"player-1","session_id":session,"run_id":run,"attempt_id":attempt,"minigame_id":"ST03","category":"DS","build_version":"0.3.0","content_version":"base","event_type":et,"sequence":i,"occurred_at":(start+timedelta(milliseconds=i)).isoformat(),"received_at":(start+timedelta(milliseconds=i)).isoformat(),"details":{"level":1,"operation":"push"}} for i,et in enumerate(["problem_started","attempt_started","operation_succeeded","attempt_succeeded","problem_completed"],1)]

def test_projection_and_replay(dbs):
 local,target=dbs;p=Projector(local,target,None,{});events=rows()
 for e in events:p.project(e)
 for e in events:p.project(e)
 assert target.game_sessions.count_documents({})==1
 assert target.problem_runs.count_documents({"status":"completed"})==1
 assert target.solution_attempts.count_documents({"outcome":"success"})==1
 assert target.gameplay_events.count_documents({})==5
 run=target.problem_runs.find_one();session=target.game_sessions.find_one()
 assert session["player_id"]=="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
 assert run["session_id"]==session["_id"] and run["task_id"]==target.game_problems.find_one()["_id"]
 assert target.game_problems.find_one()["task_id"]=="ST03"
 assert run["level"]==1
 assert run["active_ms"] is None and run["paused_ms"] is None
 assert isinstance(target.gameplay_events.find_one()["occurred_at"],datetime)

def test_out_of_order(dbs):
 l,t=dbs;p=Projector(l,t,None,{});e=rows()
 with pytest.raises(Waiting,match="sequence_gap"):p.project(e[1])
 p.project(e[0]);p.project(e[1]);assert t.solution_attempts.count_documents({})==1

def test_same_sequence_changed_id(dbs):
 l,t=dbs;p=Projector(l,t,None,{});e=rows()[0];p.project(e)
 with pytest.raises(Conflict):p.project(dict(e,event_id=str(uuid.uuid4()),payload_hash="changed"))

def test_unknown_member_keeps_archive(dbs,monkeypatch):
 def unknown(*a):raise Waiting("member_mapping_required")
 monkeypatch.setattr(projection,"resolve_member",unknown);l,t=dbs
 with pytest.raises(Waiting):Projector(l,t,None,{}).project(rows()[0])
 assert t.pipeline_learning_events.count_documents({})==1 and t.game_sessions.count_documents({})==0

def test_stage_never_resets_stored(dbs):
 l,_=dbs;e=rows()[0];stage([e],l);l.remote_event_outbox.update_one({"_id":e["event_id"]},{"$set":{"state":"stored"}})
 stage([e],l);assert l.remote_event_outbox.find_one()["state"]=="stored"
 stage([dict(e,payload_hash="other")],l)
 assert l.remote_event_outbox.find_one()["payload_hash"]==e["payload_hash"] and l.remote_export_conflicts.count_documents({})==1

def test_child_session_identity():
 assert uid("session","s","p","ST03")==uid("session","s","p","ST03")
 assert uid("session","s","p","ST03")!=uid("session","s","p","ST04")


def test_worker_lease_prevents_two_owners(dbs):
 from remote.worker import acquire
 from datetime import datetime,timedelta,timezone
 local,_=dbs
 assert acquire(local,"owner-a")
 assert not acquire(local,"owner-b")
 local.remote_worker_lease.update_one({"_id":"writer"},{"$set":{"expires_at":datetime.now(timezone.utc)-timedelta(seconds=1)}})
 assert acquire(local,"owner-b")

def test_resolve_unknown_member_never_inserts():
 class Cursor:
  def __init__(self):self.queries=[]
  def __enter__(self):return self
  def __exit__(self,*a):pass
  def execute(self,query,args):self.queries.append(query)
  def fetchall(self):return []
 class SQL:
  def __init__(self):self.c=Cursor();self.rollbacks=0
  def cursor(self):return self.c
  def rollback(self):self.rollbacks+=1
 sql=SQL()
 with pytest.raises(Waiting,match="member_mapping_required"):
  projection.resolve_member(sql,"unbound-install-id",{})
 assert not any("INSERT" in q for q in sql.c.queries) and sql.rollbacks==1
