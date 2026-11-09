"""One persistent direct writer. Durable outbox; failed targets never lose jobs."""
import os,sys,time
from pathlib import Path
from datetime import datetime,timezone
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
from database import database
from loader import Loader,connect,apply,Conflict
from pymongo.errors import PyMongoError
import pymysql
local=database();local.direct_outbox.update_many({"state":"processing"},{"$set":{"state":"pending"}})
local.direct_outbox.create_index([("state",1),("received_at",1)])
while True:
    job=local.direct_outbox.find_one_and_update({"state":"pending"},{"$set":{"state":"processing"},"$inc":{"attempts":1}},sort=[("received_at",1)])
    if not job:time.sleep(2);continue
    sql=None;remote=None
    try:
        sql,remote=connect()
        with sql.cursor() as cursor:
            cursor.execute("SELECT GET_LOCK('nodeverse_direct_loader',0)")
            if cursor.fetchone()[0]!=1:raise RuntimeError("Writer lock busy")
        result=apply(job["manifest"],Path("/journals")/(job["_id"]+".sqlite"),Loader(sql,remote))
        local.direct_outbox.update_one({"_id":job["_id"]},{"$set":{"state":"stored","stored_at":datetime.now(timezone.utc),"result":result},"$unset":{"last_error":""}})
    except (Conflict,ValueError,KeyError,TypeError) as error:
        local.direct_outbox.update_one({"_id":job["_id"]},{"$set":{"state":"blocked","last_error":type(error).__name__,"note":"Review record mapping, references or lifecycle configuration"}})
    except Exception as error:
        local.direct_outbox.update_one({"_id":job["_id"]},{"$set":{"state":"pending","last_error":type(error).__name__}})
        time.sleep(10)
    finally:
        if sql:sql.close()
        if remote is not None:remote.client.close()
