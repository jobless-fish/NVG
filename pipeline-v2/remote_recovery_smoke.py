"""Explicit worker-only crash/recovery test; never touches DB service or volumes."""
import json,subprocess,time,uuid
from pathlib import Path
from datetime import datetime,timezone
import urllib.request

def main():
 key=next(line.split('=',1)[1].strip().strip('\"').strip("'") for line in Path('../pipeline/.env').read_text(encoding='utf-8-sig').splitlines() if line.startswith('INGEST_KEY='))
 e={"schema_version":1,"event_id":str(uuid.uuid4()),"run_id":str(uuid.uuid4()),"player_id":"pipeline-recovery-test","build_version":"0.3.0","event_type":"run_heartbeat","evidence":"launcher_observed","occurred_at":datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')}
 Path('results/recovery-event.json').write_text(json.dumps(e,indent=2))
 base='http://192.168.0.81:8000/v2/events'
 def call(body=None):
  req=urllib.request.Request(base if body else base+'/'+e['event_id'],data=json.dumps(body).encode() if body else None,headers={'X-API-Key':key,'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=20) as r:return r.status,json.load(r)
 started=time.monotonic();report={'event_id':e['event_id'],'scope':'remote-writer process only','observed_states':[]}
 subprocess.run(['docker','kill','nodeverse-v2-live-remote-writer-1'],check=True,capture_output=True)
 try:
  status,_=call(e);report['accepted_while_worker_stopped']=status==202
 finally:
  subprocess.run(['docker','start','nodeverse-v2-live-remote-writer-1'],check=True,capture_output=True)
 deadline=time.monotonic()+100
 while time.monotonic()<deadline:
  _,r=call();state=r.get('state');report['observed_states'].append(state)
  print(json.dumps({'state':state,'elapsed_s':round(time.monotonic()-started,1)}),flush=True)
  if state=='stored':report['passed']=True;break
  time.sleep(3)
 report['seconds']=round(time.monotonic()-started,1)
 Path('results/recovery-result.json').write_text(json.dumps(report,indent=2))
 raise SystemExit(0 if report.get('passed') else 1)
if __name__=='__main__':main()
