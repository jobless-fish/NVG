from pyspark.sql import SparkSession
from pymongo import MongoClient
import json
spark=SparkSession.builder.appName("nodeverse-curation").getOrCreate()
spark.sparkContext.setLogLevel("WARN")
def store(batch,batch_id):
    db=MongoClient("mongodb://mongo:27017").nodeverse
    db.curated.create_index([("session_id",1),("problem_id",1),("attempt_id",1),("sequence",1)])
    from processing import route, aggregate
    for row in batch.selectExpr("CAST(value AS STRING) AS value", "topic", "partition", "offset").toLocalIterator():
        position=f"{row.topic}:{row.partition}:{row.offset}"
        try: event=json.loads(row.value)
        except (ValueError, TypeError):
            db.quarantine_events.update_one({"_id":position},{"$setOnInsert":{"reason":"invalid_json","body":row.value[:4096]}},upsert=True)
            continue
        if not isinstance(event,dict):
            db.quarantine_events.update_one({"_id":position},{"$setOnInsert":{"reason":"invalid_shape"}},upsert=True)
            continue
        route(db,event,position)
    aggregate(db)
source=spark.readStream.format("kafka").option("kafka.bootstrap.servers","kafka:9092").option("subscribe","game.events.v1").option("startingOffsets","earliest").load()
source.writeStream.foreachBatch(store).option("checkpointLocation","/checkpoints/curated-v1").trigger(processingTime="5 seconds").start().awaitTermination()
