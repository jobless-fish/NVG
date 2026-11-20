"""P6 verification and time-travel demo. Run inside the spark container (see README):

  verify.py counts [--run-id X]       Bronze = Kafka offsets, Silver duplicates = 0, Gold = Silver aggregates
  verify.py lag                       Kafka end offset - Bronze offset per partition (consumer lag)
  verify.py history  --table T [--limit 10]
  verify.py timetravel --table T [--versions 5]   row count at each recent version (VERSION AS OF n)
"""
from __future__ import annotations

import argparse
import json
import sys

from pyspark.sql import functions as F

import tables as tb

TOPICS = "nv.learning.v2,nv.runtime.v1,nv.update.v1"


def kafka_positions(spark):
    return (spark.read.format("kafka").option("kafka.bootstrap.servers", tb.KAFKA).option("subscribe", TOPICS)
            .option("startingOffsets", "earliest").option("endingOffsets", "latest").load()
            .groupBy("topic", "partition").agg(F.count(F.lit(1)).alias("kafka_rows"),
                                               (F.max("offset") + 1).alias("end_offset")))


def counts(spark, run_id):
    out, ok = {}, True
    k = kafka_positions(spark)
    b = spark.table("bronze.game_events").groupBy("topic").agg(F.count(F.lit(1)).alias("bronze_rows"))
    per_topic = (k.groupBy("topic").agg(F.sum("kafka_rows").alias("kafka_rows"))
                 .join(b, "topic", "full").fillna(0).orderBy("topic").collect())
    out["bronze_vs_kafka"] = [r.asDict() for r in per_topic]
    ok &= all(r.kafka_rows == r.bronze_rows for r in per_topic)

    for table in ("silver.learning_events", "silver.update_events"):
        df = spark.table(table)
        if run_id:
            df = df.where(F.col("player_id").contains(run_id))
        r = df.agg(F.count(F.lit(1)).alias("rows"), F.countDistinct("event_id").alias("unique")).first()
        out[table] = {"rows": r.rows, "unique_event_ids": r.unique, "duplicates": r.rows - r.unique}
        ok &= r.rows == r.unique
    q = spark.table("silver.quarantine").groupBy("reason").count().collect()
    out["silver.quarantine"] = {r.reason: r["count"] for r in q}

    # Gold vs Silver for the same 1-minute windows (late events beyond the 2-minute watermark are dropped by design)
    s = (spark.table("silver.learning_events")
         .groupBy(F.window("event_time", "1 minute").start.alias("window_start"), "minigame_id")
         .agg(F.sum(F.when(F.col("event_type") == "attempt_started", 1).otherwise(0)).alias("s_attempts"),
              F.sum(F.when(F.col("event_type") == "attempt_succeeded", 1).otherwise(0)).alias("s_success"),
              F.sum(F.when(F.col("event_type") == "attempt_failed", 1).otherwise(0)).alias("s_fail")))
    g = spark.table("gold.minigame_1m").select("window_start", "minigame_id", "attempts", "successes", "failures")
    j = s.join(g, ["window_start", "minigame_id"], "full").fillna(0, ["s_attempts", "s_success", "s_fail", "attempts", "successes", "failures"])
    diff = j.where((F.coalesce(F.col("attempts"), F.lit(0)) != F.col("s_attempts"))
                   | (F.coalesce(F.col("successes"), F.lit(0)) != F.col("s_success"))
                   | (F.coalesce(F.col("failures"), F.lit(0)) != F.col("s_fail"))
                   ).select("window_start", "minigame_id", "s_attempts", "attempts")
    totals = j.agg(F.sum("s_attempts").alias("silver_attempts"), F.sum("attempts").alias("gold_attempts"),
                   F.sum("s_success").alias("silver_successes"), F.sum("successes").alias("gold_successes"),
                   F.sum("s_fail").alias("silver_failures"), F.sum("failures").alias("gold_failures")).first()
    out["gold_vs_silver"] = {**{k: int(v or 0) for k, v in totals.asDict().items()},
                             "mismatched_windows": diff.count(),
                             "examples": [r.asDict() for r in diff.limit(5).collect()]}
    ok &= out["gold_vs_silver"]["mismatched_windows"] == 0
    out["passed"] = bool(ok)
    return out


def lag(spark):
    k = kafka_positions(spark)
    b = spark.table("bronze.game_events").groupBy("topic", "partition").agg((F.max("offset") + 1).alias("bronze_end"))
    rows = (k.join(b, ["topic", "partition"], "left").fillna(0, ["bronze_end"])
            .withColumn("lag", F.col("end_offset") - F.col("bronze_end")).orderBy("topic", "partition").collect())
    return {"partitions": [r.asDict() for r in rows], "total_lag": sum(r.lag for r in rows)}


def history(spark, table, limit):
    rows = spark.sql(f"DESCRIBE HISTORY {table} LIMIT {int(limit)}").select(
        "version", "timestamp", "operation", "operationMetrics").collect()
    return [{"version": r.version, "timestamp": str(r.timestamp), "operation": r.operation,
             "metrics": {k: v for k, v in (r.operationMetrics or {}).items()
                         if k in ("numOutputRows", "numTargetRowsInserted", "numTargetRowsUpdated",
                                  "numTargetRowsDeleted", "numAddedFiles")}} for r in rows]


def timetravel(spark, table, versions):
    latest = spark.sql(f"DESCRIBE HISTORY {table} LIMIT 1").first().version
    out = []
    for v in range(max(0, latest - versions + 1), latest + 1):
        n = spark.sql(f"SELECT COUNT(*) AS n FROM {table} VERSION AS OF {v}").first().n
        out.append({"version": v, "rows": n})
    return {"table": table, "latest_version": latest, "versions": out}


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("counts"); c.add_argument("--run-id")
    sub.add_parser("lag")
    h = sub.add_parser("history"); h.add_argument("--table", default="bronze.game_events"); h.add_argument("--limit", type=int, default=10)
    t = sub.add_parser("timetravel"); t.add_argument("--table", default="silver.learning_events"); t.add_argument("--versions", type=int, default=5)
    a = p.parse_args()
    spark = tb.spark_session("nodeverse-verify", shuffle_partitions=4)
    tb.register_names(spark)
    if a.cmd == "counts":
        result = counts(spark, a.run_id)
    elif a.cmd == "lag":
        result = lag(spark)
    elif a.cmd == "history":
        result = history(spark, a.table, a.limit)
    else:
        result = timetravel(spark, a.table, a.versions)
    print(json.dumps(result, indent=2, default=str))
    if a.cmd == "counts" and not result["passed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
