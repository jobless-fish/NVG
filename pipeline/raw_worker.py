import json
from confluent_kafka import Consumer, KafkaException
from pymongo import MongoClient
c=Consumer({"bootstrap.servers":"kafka:9092","group.id":"raw-archive-v1","auto.offset.reset":"earliest","enable.auto.commit":False})
db=MongoClient("mongodb://mongo:27017").nodeverse
c.subscribe(["game.events.v1"])
try:
    while True:
        msg=c.poll(1)
        if msg is None: continue
        if msg.error(): raise KafkaException(msg.error())
        # Kafka position preserves every delivery, including client retries.
        key=f"{msg.topic()}:{msg.partition()}:{msg.offset()}"
        db.raw_events.replace_one({"_id":key},{"_id":key,"payload":json.loads(msg.value()),"partition":msg.partition(),"offset":msg.offset()},upsert=True)
        c.commit(message=msg,asynchronous=False)
finally: c.close()
