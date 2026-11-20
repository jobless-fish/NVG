"""Read-only local Docker inventory. No document values or credentials exported."""
import json,subprocess,argparse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument("--output",type=Path,required=True);a=p.parse_args()
script='const d=db.getSiblingDB("nodeverse");print(JSON.stringify(d.getCollectionInfos().map(c=>({name:c.name,count:d[c.name].countDocuments({}),indexes:d[c.name].getIndexes(),validator:c.options.validator||null,sampled_types:d[c.name].aggregate([{$limit:25},{$project:{fields:{$objectToArray:"$$ROOT"}}},{$unwind:"$fields"},{$group:{_id:"$fields.k",types:{$addToSet:{$type:"$fields.v"}}}}]).toArray()}))));'
r=subprocess.run(["docker","exec","pipeline-mongo-1","mongosh","--quiet","--eval",script],capture_output=True,text=True,encoding="utf-8",check=True)
a.output.write_text(json.dumps({"source":"MongoDB nodeverse (local)","value_exported":False,"collections":json.loads(r.stdout),"target":"nodeverse_logs","automatic_conversion":False},ensure_ascii=False,indent=2),encoding="utf-8")
print("Inventory written; no destination database was changed")
