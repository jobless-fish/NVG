"""Seeded synthetic scenarios; every delivery goes through the real ingestion API."""
import copy, json, random, time, uuid, urllib.request, urllib.error
from datetime import datetime, timezone

def now(): return datetime.now(timezone.utc).isoformat()
def scenarios(seed, count, run):
    rng=random.Random(seed)
    kinds=["learning","runtime","duplicate","conflict","invalid","evidence","unauthorized","delayed"]
    types=["problem_started","attempt_started","operation","attempt_failed","hint_used","attempt_succeeded"]
    exits=[("run_started","launcher_observed"),("run_heartbeat","launcher_observed"),("exit_normal","game_shutdown_complete"),("exit_crash_confirmed","crash_report"),("exit_forced_confirmed","user_confirmed"),("exit_unexpected_unknown","next_launch_recovery"),("exit_hang_suspected","watchdog"),("exit_connection_lost_suspected","server_timeout")]
    for i in range(count):
        kind=kinds[i%len(kinds)]
        player=f"lab-{run}-p{rng.randrange(1,9)}"
        event={"schema_version":1,"event_id":str(uuid.uuid5(uuid.NAMESPACE_URL,f"{run}:{seed}:{i}")),"run_id":str(uuid.uuid5(uuid.NAMESPACE_URL,run+player)),"player_id":player,"session_id":player+"-s1","problem_id":f"problem-{rng.randrange(1,6)}","attempt_id":f"attempt-{i}","event_type":rng.choice(types),"occurred_at":now(),"sequence":i,"duration_ms":rng.randrange(50,60000)}
        if kind in ("runtime","evidence"):
            event={k:v for k,v in event.items() if k not in ("sequence","duration_ms")}
            t,e=exits[(i//8)%len(exits)]
            event.update(event_type=t,evidence=e,build_version="synthetic-1.0")
            if kind=="evidence":event.update(event_type="exit_crash_confirmed",evidence="launcher_observed")
        if kind=="invalid":event["sequence"]=-1
        if kind=="delayed":
            from datetime import timedelta
            event["occurred_at"]=(datetime.now(timezone.utc)-timedelta(days=rng.randrange(1,5))).isoformat()
        expected=401 if kind=="unauthorized" else 422 if kind in ("invalid","evidence") else 202
        yield kind,event,expected,kind!="unauthorized"
        if kind in ("duplicate","conflict"):
            other=copy.deepcopy(event)
            if kind=="conflict":other["duration_ms"]+=1
            yield kind+"_replay",other,202,True

def send(url,key,event,authorized):
    request=urllib.request.Request(url+"/v1/events",data=json.dumps(event).encode(),headers={"Content-Type":"application/json","X-API-Key":key if authorized else "synthetic-invalid-key"})
    started=time.monotonic()
    try:
        with urllib.request.urlopen(request,timeout=12) as response: status=response.status;body=response.read().decode()
    except urllib.error.HTTPError as error: status=error.code;body=error.read().decode()
    except (OSError,TimeoutError) as error: status=0;body=type(error).__name__
    return status,body,round((time.monotonic()-started)*1000,1)
