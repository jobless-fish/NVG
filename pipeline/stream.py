from pyspark.sql import SparkSession
from pymongo import MongoClient
import json
spark=SparkSession.builder.appName("nodeverse-curation").getOrCreate()
spark.sparkContext.setLogLevel("WARN")
def store(batch,batch_id):
    db=MongoClient("mongodb://mongo:27017").nodeverse
    db.curated.create_index([("session_id",1),("problem_id",1),("attempt_id",1),("sequence",1)])
    # Single local driver; Mongo unique _id makes retries and batch replay idempotent.
    for row in batch.selectExpr("CAST(value AS STRING) AS value").toLocalIterator():
        event=json.loads(row.value)
        event["_id"]=event.pop("event_id")
        db.curated.replace_one({"_id":event["_id"]},event,upsert=True)
    # Full recomputation avoids double increments after partial batch failures.
    pipeline=[{"$group":{"_id":{"player_id":"$player_id","problem_id":"$problem_id"},"events":{"$sum":1},"failures":{"$sum":{"$cond":[{"$eq":["$event_type","attempt_failed"]},1,0]}},"successes":{"$sum":{"$cond":[{"$eq":["$event_type","attempt_succeeded"]},1,0]}},"hints":{"$sum":{"$cond":[{"$eq":["$event_type","hint_used"]},1,0]}}}},{"$merge":{"into":"metrics","on":"_id","whenMatched":"replace","whenNotMatched":"insert"}}]
    list(db.curated.aggregate(pipeline))
source=spark.readStream.format("kafka").option("kafka.bootstrap.servers","kafka:9092").option("subscribe","game.events.v1").option("startingOffsets","earliest").load()
source.writeStream.foreachBatch(store).option("checkpointLocation","/checkpoints/curated-v1").trigger(processingTime="5 seconds").start().awaitTermination()
