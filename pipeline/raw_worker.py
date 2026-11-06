import os
import json
from confluent_kafka import Consumer, KafkaException
from database import database
c=Consumer({"bootstrap.servers":"kafka:9092","group.id":"raw-archive-v1","auto.offset.reset":"earliest","enable.auto.commit":False})
db=database()
c.subscribe(["game.events.v1"])
try:
    while True:
        msg=c.poll(1)
        if msg is None: continue
        if msg.error(): raise KafkaException(msg.error())
        # Kafka position preserves every delivery, including client retries.
        key=os.environ.get("KAFKA_EPOCH","")+f"{msg.topic()}:{msg.partition()}:{msg.offset()}"
        try: payload=json.loads(msg.value())
        except (ValueError, TypeError, UnicodeDecodeError): payload={"unparsed":msg.value().decode("utf-8",errors="replace")}
        db.raw_events.replace_one({"_id":key},{"_id":key,"payload":payload,"partition":msg.partition(),"offset":msg.offset()},upsert=True)
        c.commit(message=msg,asynchronous=False)
finally: c.close()
