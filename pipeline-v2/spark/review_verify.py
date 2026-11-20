"""Quiescent integration verification; stop the streaming writer before running."""
import json
import argparse
from pathlib import Path
from pymongo import MongoClient
import os
import tables as tb
from verify import counts, history, lag
from pyspark.sql import functions as F

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--expectations", help="immutable HTTP test fixture expected IDs/hashes")
args = parser.parse_args()

spark = tb.spark_session("nodeverse-review-verify", shuffle_partitions=2)
tb.register_names(spark)
report = counts(spark, None)
bronze = spark.table("bronze.game_events")
report["bronze_duplicate_offsets"] = bronze.count() - bronze.select("topic", "partition", "offset").distinct().count()
report["lag"] = lag(spark)
source_counts = {}
for topic, table in (("nv.learning.v2", "silver.learning_events"), ("nv.update.v1", "silver.update_events")):
    expected = bronze.where(F.col("topic") == topic).select(F.get_json_object("value", "$.event_id").alias("event_id")).distinct().count()
    actual = spark.table(table).count()
    source_counts[table] = {"bronze_unique_ids": expected, "silver_rows": actual, "matched": expected == actual}
report["source_unique_vs_silver"] = source_counts
report["history"] = {name: history(spark, name, 4) for name in (
    "bronze.game_events", "silver.learning_events", "silver.update_events", "gold.minigame_1m")}
db = MongoClient(os.environ.get("MONGO_URI", "mongodb://mongo:27017"))[os.environ.get("MONGO_DB", "nodeverse_logs")]
mismatches = []
extra_docs = {}
collections = {"gold.minigame_1m": "rt_minigame_1m", "gold.failure_alerts": "rt_alerts",
               "gold.update_progress_5m": "rt_updates", "gold.version_adoption": "rt_versions"}
for table, collection in collections.items():
    expected_ids = set()
    for r in spark.table(table).collect():
        if table == "gold.version_adoption":
            ident = r.kind + ":" + r.version
        elif table == "gold.update_progress_5m":
            ident = r.target_version + ":" + r.window_start.strftime("%Y-%m-%dT%H:%M:%SZ")
        else:
            ident = r.minigame_id + ":" + r.window_start.strftime("%Y-%m-%dT%H:%M:%SZ")
        expected_ids.add(ident)
        doc = db[collection].find_one({"_id": ident}) or {}
        differences = [k for k in r.asDict() if k != "updated_at" and doc.get(k) != r[k]]
        if not doc or differences:
            mismatches.append({"collection": collection, "id": ident, "fields": differences})
    extras = sorted({d["_id"] for d in db[collection].find({}, {"_id": 1})} - expected_ids)
    if extras:
        extra_docs[collection] = extras
report["mongo_gold_mismatches"] = mismatches
report["mongo_extra_documents"] = extra_docs
fixture_ok = True
if args.expectations:
    fixture = json.loads(Path(args.expectations).read_text())
    wanted = fixture["events"]
    ids = [e["event_id"] for e in wanted]
    observed = (bronze.select(F.get_json_object("value", "$.event_id").alias("event_id"),
                             F.get_json_object("value", "$.payload_hash").alias("payload_hash"))
                .where(F.col("event_id").isin(ids)).groupBy("event_id", "payload_hash").count().collect())
    copies = {(r.event_id, r.payload_hash): r["count"] for r in observed}
    silver_hashes = {}
    for table in ("silver.learning_events", "silver.update_events"):
        for r in spark.table(table).where(F.col("event_id").isin(ids)).select("event_id", "payload_hash").collect():
            silver_hashes[r.event_id] = r.payload_hash
    failures = []
    for event in wanted:
        if copies.get((event["event_id"], event["payload_hash"])) != 2:
            failures.append({"id": event["event_id"], "reason": "canonical Kafka/Bronze copies must equal 2"})
        if event["topic"] != "nv.runtime.v1" and silver_hashes.get(event["event_id"]) != event["payload_hash"]:
            failures.append({"id": event["event_id"], "reason": "Silver content missing or changed"})
    conflict_rows = spark.table("silver.quarantine").where(
        (F.col("event_id") == fixture["conflict_event_id"]) & (F.col("reason") == "id_conflict")).count()
    fixture_ok = not failures and conflict_rows == 1
    report["http_fixture_verification"] = {"run_id": fixture["run_id"], "expected_unique": len(wanted),
                                           "conflict_quarantined": conflict_rows, "failures": failures, "passed": fixture_ok}
report["mongo_collections"] = {name: db[name].count_documents({}) for name in db.list_collection_names()}
report["checkpoints"] = {p.name: {"offset_files": len(list((p/"offsets").glob("[0-9]*"))),
                                      "commit_files": len(list((p/"commits").glob("[0-9]*")))}
                         for p in Path(tb.CHECKPOINTS).iterdir() if p.is_dir()}
report["passed"] = bool(report["passed"] and not mismatches and not extra_docs and fixture_ok and report["bronze_duplicate_offsets"] == 0
                        and report["lag"]["total_lag"] == 0 and all(x["matched"] for x in source_counts.values()))
Path("/data/metrics").mkdir(exist_ok=True)
Path("/data/metrics/review-verification.json").write_text(json.dumps(report, indent=2, default=str))
print(json.dumps(report, indent=2, default=str))
spark.stop()
raise SystemExit(0 if report["passed"] else 1)
