"""NODEVERSE Delta pipeline: Kafka -> Bronze -> Silver -> Gold -> MongoDB (P2, P3, P4, P4-2).

One Spark application, seven streaming queries, each with its own checkpoint:
  bronze      Kafka (nv.learning.v2, nv.runtime.v1, nv.update.v1) -> bronze.game_events   (append, 5 s)
  silver_*    bronze -> silver.learning_events / silver.update_events
              (state-store dedup on event_id, 7 days, then insert-only MERGE; 1 s)
  silver_audit bronze -> silver.quarantine (invalid_json, invalid_schema, id_conflict; 30 s)
  gold_1m     silver.learning_events -> gold.minigame_1m   (1 min windows)   -> rt_minigame_1m
  gold_alert  silver.learning_events -> gold.failure_alerts (5 min / 1 min)  -> rt_alerts
  gold_update silver.update_events   -> gold.update_progress_5m (5 min)      -> rt_updates
A driver timer refreshes rt_summary (10 s) and gold.version_adoption -> rt_versions (60 s).
Every MongoDB write is an _id upsert, so replaying a batch never inflates values.
"""
from __future__ import annotations

import logging
import os
import threading
import time
from datetime import datetime, timedelta, timezone

from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F

import tables as tb
import sys
sys.path.insert(0, "/opt/nodeverse")
from tables import path

log = logging.getLogger("delta_stream")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

MONGO_URI = os.getenv("MONGO_URI", "mongodb://mongo:27017")
MONGO_DB = os.getenv("MONGO_DB", "nodeverse_logs")
BRONZE_TRIGGER = os.getenv("BRONZE_TRIGGER", "5 seconds")
STAGE_TRIGGER = os.getenv("STAGE_TRIGGER", "1 second")
LATE_SECONDS = 300  # event_time falls back to received_at when the clock gap exceeds 5 minutes

ALERT_MIN_ATTEMPTS = 20
ALERT_MIN_RATE = 0.4
ALERT_BASELINE_FACTOR = 1.5

spark = tb.spark_session("nodeverse-delta")


# ---------------------------------------------------------------- MongoDB
_mongo = None


def mongo():
    global _mongo
    if _mongo is None:
        from pymongo import MongoClient
        _mongo = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)[MONGO_DB]
    return _mongo


def iso(ts: datetime) -> str:
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


def upsert(collection: str, docs: list[dict]) -> None:
    if not docs:
        return
    from pymongo import ReplaceOne
    mongo()[collection].bulk_write([ReplaceOne({"_id": d["_id"]}, d, upsert=True) for d in docs], ordered=False)


# ---------------------------------------------------------------- P2 Bronze
def start_bronze():
    src = (spark.readStream.format("kafka")
           .option("kafka.bootstrap.servers", tb.KAFKA)
           .option("subscribe", "nv.learning.v2,nv.runtime.v1,nv.update.v1")
           .option("startingOffsets", "earliest")
           .option("failOnDataLoss", "true")
           .option("maxOffsetsPerTrigger", os.getenv("MAX_OFFSETS_PER_TRIGGER", "10000"))
           .load())
    bronze = src.selectExpr("CAST(value AS STRING) AS value", "topic", "partition", "offset",
                            "timestamp AS kafka_ts", "to_date(timestamp) AS ingest_date")
    return (bronze.writeStream.format("delta").outputMode("append").queryName("bronze")
            .option("checkpointLocation", tb.checkpoint("bronze-v1"))
            .trigger(processingTime=BRONZE_TRIGGER)
            .start(path("bronze.game_events")))


# ---------------------------------------------------------------- P3 Silver
# Two streams read Bronze (docs/DECISIONS.md D19):
#   silver        dashboard path. JVM state-store dedup on topic:event_id (dropDuplicatesWithinWatermark,
#                 7 days on kafka_ts = Kafka retention) -> MERGE to Silver. State dedup cost depends on the
#                 batch only; the MERGE additionally probes target files (measure its cost).
#   silver_audit  quarantine path. Keeps topic:event_id -> payload_hash in the state store and writes
#                 id_conflict / invalid_json / invalid_schema rows to silver.quarantine. Off the dashboard path.
SILVER_SPECS = {
    # topic: (json schema, table)
    "nv.learning.v2": (tb.LEARNING_JSON, "silver.learning_events"),
    "nv.update.v1": (tb.UPDATE_JSON, "silver.update_events"),
}
DEDUP_HOURS = int(os.getenv("DEDUP_TTL_HOURS", str(7 * 24)))
DEDUP_TTL_MS = DEDUP_HOURS * 3600 * 1000
AUDIT_TRIGGER = os.getenv("AUDIT_TRIGGER", "30 seconds")
DECISION_SCHEMA = ("key string, value string, topic string, partition int, offset long, "
                   "event_id string, action string")
STATE_SCHEMA = "hash string"
_EID = F.get_json_object("value", "$.event_id")
_HASH = F.get_json_object("value", "$.payload_hash")


def _parse(df: DataFrame, schema) -> DataFrame:
    return (df.withColumn("j", F.from_json("value", schema))
            .select("value", F.col("topic").alias("kafka_topic"), F.col("partition").alias("kafka_partition"),
                    F.col("offset").alias("kafka_offset"), "kafka_ts", "j.*")
            .withColumn("occurred_at", F.to_timestamp("occurred_at"))
            .withColumn("received_at", F.to_timestamp("received_at")))


_COMPLETE = (F.col("event_id").isNotNull() & F.col("payload_hash").isNotNull() & F.col("player_id").isNotNull()
             & F.col("event_type").isNotNull() & F.col("occurred_at").isNotNull()
             & F.col("received_at").isNotNull() & (F.col("schema_version") == 2))


def _append(df: DataFrame, table: str, app: str, batch_id: int) -> None:
    # idempotent append: a replayed batch_id is skipped by Delta (txnAppId/txnVersion)
    (df.write.format("delta").mode("append")
     .option("txnAppId", app).option("txnVersion", batch_id).save(path(table)))


def start_silver():
    queries = []
    for topic, (schema, table) in SILVER_SPECS.items():
        rows = (_parse(spark.readStream.format("delta").load(path("bronze.game_events"))
                       .where(F.col("topic") == topic), schema)
                .where(_COMPLETE)
                .withWatermark("kafka_ts", f"{DEDUP_HOURS} hours")
                .dropDuplicatesWithinWatermark(["event_id"])
                .withColumn("event_time",
                            F.when(F.abs(F.col("occurred_at").cast("long") - F.col("received_at").cast("long"))
                                   > LATE_SECONDS, F.col("received_at")).otherwise(F.col("occurred_at")))
                .withColumn("event_date", F.to_date("event_time"))
                # kafka_ts (the watermark column) must stay in the streaming plan; it is dropped per batch
                .select(*tb.SCHEMAS[table][0].fieldNames(), "kafka_ts"))
        name = table.split(".")[1]

        def write(batch: DataFrame, batch_id: int, table=table, name=name) -> None:
            started = time.monotonic()
            # Events are immutable: replay inserts no extra rows; conflicting payloads never overwrite.
            # Keep insert-only MERGE so downstream append streams do not read rewritten event rows.
            from delta.tables import DeltaTable
            source = batch.drop("kafka_ts").persist()
            try:
                if not source.isEmpty():
                    (DeltaTable.forPath(spark, path(table)).alias("t")
                     .merge(source.alias("s"), "t.event_id = s.event_id")
                     .whenNotMatchedInsertAll().execute())
                    if os.getenv("REMOTE_EXPORT_ENABLED", "0") == "1":
                        from remote.outbox import stage
                        stage(row.asDict(recursive=True) for row in source.toLocalIterator())
            finally:
                source.unpersist()
            log.info("silver %s batch %s in %.1fs", name, batch_id, time.monotonic() - started)

        queries.append(rows.writeStream.queryName("silver_" + name).foreachBatch(write)
                       .option("checkpointLocation", tb.checkpoint(f"silver-{name}-v2"))
                       .trigger(processingTime=STAGE_TRIGGER).start())
    return tuple(queries)


def audit(key, pdfs, state):
    """Per key (topic:event_id): first copy -> first, same hash -> dropped, other hash -> id_conflict."""
    import pandas as pd
    (k,) = key
    if state.hasTimedOut:  # nothing seen for DEDUP_TTL: forget the id
        state.remove()
        return
    rows = pd.concat(list(pdfs))
    if len(rows) > 1:
        rows = rows.sort_values(["partition", "offset"])
    cols = ["key", "value", "topic", "partition", "offset", "event_id", "action"]
    if k.startswith("bad:"):  # no usable event_id/hash, never stored in state
        yield rows.assign(action="invalid")[cols]
        return
    known = state.get[0] if state.exists else None
    actions = []
    for h in rows["hash"]:
        if known is None:
            known = h
            actions.append("first")
        elif h == known:
            actions.append("duplicate")
        else:
            actions.append("id_conflict")
    state.update((known,))
    state.setTimeoutDuration(DEDUP_TTL_MS)
    rows = rows.assign(action=actions)
    rows = rows[rows["action"] != "duplicate"]
    if len(rows):
        yield rows[cols]


def to_quarantine(decisions: DataFrame, batch_id: int) -> None:
    started = time.monotonic()
    decisions = decisions.persist()
    try:
        q = (decisions.where(F.col("action") != "first")
             .select(F.col("topic").alias("kafka_topic"), F.col("partition").alias("kafka_partition"),
                     F.col("offset").alias("kafka_offset"),
                     F.when(F.col("action") == "id_conflict", F.lit("id_conflict"))
                      .when(F.get_json_object("value", "$").isNull(), F.lit("invalid_json"))
                      .otherwise(F.lit("invalid_schema")).alias("reason"),
                     "event_id", "value", F.current_timestamp().alias("detected_at")))
        # first copies that the silver stream rejects as incomplete are invalid_schema too
        for topic, (schema, _) in SILVER_SPECS.items():
            first = _parse(decisions.where((F.col("action") == "first") & (F.col("topic") == topic))
                           .withColumn("kafka_ts", F.current_timestamp()), schema)
            q = q.unionByName(first.where(~_COMPLETE).select(
                "kafka_topic", "kafka_partition", "kafka_offset", F.lit("invalid_schema").alias("reason"),
                "event_id", "value", F.current_timestamp().alias("detected_at")))
        q = q.persist()
        if q.limit(1).count():
            _append(q, "silver.quarantine", "silver-quarantine-v2", batch_id)
        q.unpersist()
    finally:
        decisions.unpersist()
    log.info("audit batch %s in %.1fs", batch_id, time.monotonic() - started)


def start_silver_audit():
    from pyspark.sql.streaming.state import GroupStateTimeout
    bronze = (spark.readStream.format("delta").load(path("bronze.game_events"))
              .where(F.col("topic").isin(*SILVER_SPECS)))
    keyed = bronze.select(
        F.when(_EID.isNotNull() & _HASH.isNotNull(), F.concat_ws(":", "topic", _EID))
         .otherwise(F.concat_ws(":", F.lit("bad"), "topic", "partition", "offset")).alias("key"),
        "value", "topic", "partition", "offset", _EID.alias("event_id"), _HASH.alias("hash"))
    decisions = keyed.groupBy("key").applyInPandasWithState(
        audit, outputStructType=DECISION_SCHEMA, stateStructType=STATE_SCHEMA,
        outputMode="append", timeoutConf=GroupStateTimeout.ProcessingTimeTimeout)
    return (decisions.writeStream.queryName("silver_audit").foreachBatch(to_quarantine)
            .option("checkpointLocation", tb.checkpoint("silver-audit-v2"))
            .trigger(processingTime=AUDIT_TRIGGER).start())


# ---------------------------------------------------------------- P4 Gold
def _count(event_type: str):
    return F.sum(F.when(F.col("event_type") == event_type, 1).otherwise(0)).cast("long")


def _merge(table: str, df: DataFrame, keys: list[str]) -> None:
    from delta.tables import DeltaTable
    cond = " AND ".join(f"t.{k} = s.{k}" for k in keys)
    # every Gold table is keyed by window_start: a literal lower bound lets Delta skip files of older windows
    # by their min/max stats, so the MERGE reads only recent files however long the table grows (D21)
    lo = df.agg(F.min("window_start")).first()[0]
    if lo is None:
        return
    cond += f" AND t.window_start >= TIMESTAMP '{lo.strftime('%Y-%m-%d %H:%M:%S')}'"
    (DeltaTable.forPath(spark, path(table)).alias("t").merge(df.alias("s"), cond)
     .whenMatchedUpdateAll().whenNotMatchedInsertAll().execute())


def gold_minigame(agg: DataFrame, batch_id: int) -> None:
    started = time.monotonic()
    rows = (agg.select(F.col("window.start").alias("window_start"), F.col("window.end").alias("window_end"),
                       "minigame_id", "category", "attempts", "successes", "failures", "hints", "players")
            .withColumn("success_rate", F.when((F.col("successes") + F.col("failures")) > 0,
                                               F.col("successes") / (F.col("successes") + F.col("failures"))))
            .withColumn("updated_at", F.current_timestamp())).persist()
    try:
        _merge("gold.minigame_1m", rows, ["window_start", "minigame_id"])
        upsert("rt_minigame_1m", [dict(r.asDict(), _id=f"{r.minigame_id}:{iso(r.window_start)}")
                                  for r in rows.collect()])
    finally:
        rows.unpersist()
    log.info("gold_1m batch %s in %.1fs", batch_id, time.monotonic() - started)


def gold_alerts(agg: DataFrame, batch_id: int) -> None:
    cur = (agg.select(F.col("window.start").alias("window_start"), F.col("window.end").alias("window_end"),
                      "minigame_id", "category", "attempts", "successes", "failures")
           .withColumn("failure_rate", F.when((F.col("successes") + F.col("failures")) > 0,
                                              F.col("failures") / (F.col("successes") + F.col("failures"))))
           .localCheckpoint())
    # baseline = failure rate over the 30 minutes before the window, from gold.minigame_1m
    lo = cur.agg(F.min("window_start")).first()[0]
    if lo is None:
        return
    hist = (spark.read.format("delta").load(path("gold.minigame_1m"))
            .where(F.col("window_start") >= F.lit(lo - timedelta(minutes=30)))  # file skipping (D21)
            .select(F.col("minigame_id").alias("h_game"), F.col("window_start").alias("h_start"),
                    F.col("successes").alias("h_s"), F.col("failures").alias("h_f")))
    keys = cur.select(F.col("window_start").alias("k_start"), F.col("minigame_id").alias("k_game")).distinct()
    joined = keys.join(hist, (keys.k_game == hist.h_game)
                       & (hist.h_start >= keys.k_start - F.expr("INTERVAL 30 MINUTES"))
                       & (hist.h_start < keys.k_start), "left")
    base = (joined.groupBy("k_start", "k_game")
            .agg(F.sum("h_f").alias("bf"), F.sum(F.col("h_s") + F.col("h_f")).alias("bt"))
            .select(F.col("k_start").alias("window_start"), F.col("k_game").alias("minigame_id"),
                    F.when(F.col("bt") > 0, F.col("bf") / F.col("bt")).alias("baseline_rate")))
    rows = (cur.join(base, ["window_start", "minigame_id"], "left")
            .withColumn("alert", (F.col("attempts") >= ALERT_MIN_ATTEMPTS)
                        & F.coalesce(F.col("failure_rate") >= ALERT_MIN_RATE, F.lit(False))
                        & (F.col("baseline_rate").isNull()
                           | (F.col("failure_rate") >= F.col("baseline_rate") * ALERT_BASELINE_FACTOR)))
            .withColumn("updated_at", F.current_timestamp())
            .select(*tb.SCHEMAS["gold.failure_alerts"][0].fieldNames())).persist()
    try:
        _merge("gold.failure_alerts", rows, ["window_start", "minigame_id"])
        upsert("rt_alerts", [dict(r.asDict(), _id=f"{r.minigame_id}:{iso(r.window_start)}") for r in rows.collect()])
    finally:
        rows.unpersist()


def start_gold_learning():
    silver = spark.readStream.format("delta").load(path("silver.learning_events"))
    one_min = (silver.withWatermark("event_time", "2 minutes")
               .groupBy(F.window("event_time", "1 minute"), "minigame_id", "category")
               .agg(_count("attempt_started").alias("attempts"), _count("attempt_succeeded").alias("successes"),
                    _count("attempt_failed").alias("failures"), _count("hint_used").alias("hints"),
                    F.approx_count_distinct("player_id").alias("players")))
    q1 = (one_min.writeStream.outputMode("update").queryName("gold_1m").foreachBatch(gold_minigame)
          .option("checkpointLocation", tb.checkpoint("gold-minigame-1m-v1"))
          .trigger(processingTime=STAGE_TRIGGER).start())
    five_min = (silver.withWatermark("event_time", "2 minutes")
                .groupBy(F.window("event_time", "5 minutes", "1 minute"), "minigame_id", "category")
                .agg(_count("attempt_started").alias("attempts"), _count("attempt_succeeded").alias("successes"),
                     _count("attempt_failed").alias("failures")))
    q2 = (five_min.writeStream.outputMode("update").queryName("gold_alert").foreachBatch(gold_alerts)
          .option("checkpointLocation", tb.checkpoint("gold-failure-alerts-v1"))
          .trigger(processingTime=STAGE_TRIGGER).start())
    return q1, q2


# ---------------------------------------------------------------- P4-2 update progress
def gold_updates(agg: DataFrame, batch_id: int) -> None:
    cur = agg.select(F.col("window.start").alias("window_start"), F.col("window.end").alias("window_end"),
                     "target_version", "checks", "prompted", "accepted", "dismissed", "downloads_started",
                     "downloads_succeeded", "downloads_failed", "mounted", "p50_duration_ms").persist()
    try:
        bounds = cur.agg(F.min("window_start").alias("lo"), F.max("window_end").alias("hi")).first()
        if bounds is None or bounds.lo is None:
            return
        failed = (spark.read.format("delta").load(path("silver.update_events"))
                  .where((F.col("event_type") == "pack_download_failed")
                         & (F.col("event_time") >= F.lit(bounds.lo)) & (F.col("event_time") < F.lit(bounds.hi)))
                  .select(F.window("event_time", "5 minutes").start.alias("window_start"),
                          F.coalesce(F.col("details.target_version"), F.lit("none")).alias("target_version"),
                          F.col("details.failure_reason").alias("reason"))
                  .groupBy("window_start", "target_version", "reason").count())
        w = Window.partitionBy("window_start", "target_version").orderBy(F.desc("count"), F.asc("reason"))
        top = (failed.withColumn("rn", F.row_number().over(w)).where("rn = 1")
               .select("window_start", "target_version", F.col("reason").alias("top_failure_reason")))
        done = F.col("downloads_succeeded") + F.col("downloads_failed")
        rows = (cur.join(top, ["window_start", "target_version"], "left")
                .withColumn("failure_rate", F.when(done > 0, F.col("downloads_failed") / done))
                .withColumn("updated_at", F.current_timestamp())
                .select(*tb.SCHEMAS["gold.update_progress_5m"][0].fieldNames())).persist()
        _merge("gold.update_progress_5m", rows, ["window_start", "target_version"])
        upsert("rt_updates", [dict(r.asDict(), _id=f"{r.target_version}:{iso(r.window_start)}")
                              for r in rows.collect()])
        rows.unpersist()
    finally:
        cur.unpersist()


def start_gold_updates():
    silver = spark.readStream.format("delta").load(path("silver.update_events"))
    agg = (silver.withWatermark("event_time", "10 minutes")
           .withColumn("target_version", F.coalesce(F.col("details.target_version"), F.lit("none")))
           .groupBy(F.window("event_time", "5 minutes"), "target_version")
           .agg(_count("update_checked").alias("checks"), _count("update_prompted").alias("prompted"),
                _count("update_accepted").alias("accepted"), _count("update_dismissed").alias("dismissed"),
                _count("pack_download_started").alias("downloads_started"),
                _count("pack_download_succeeded").alias("downloads_succeeded"),
                _count("pack_download_failed").alias("downloads_failed"),
                _count("pack_mounted").alias("mounted"),
                F.percentile_approx(F.when(F.col("event_type") == "pack_download_succeeded",
                                           F.col("details.duration_ms")), 0.5).cast("long").alias("p50_duration_ms")))
    return (agg.writeStream.outputMode("update").queryName("gold_update").foreachBatch(gold_updates)
            .option("checkpointLocation", tb.checkpoint("gold-update-progress-v1"))
            .trigger(processingTime=STAGE_TRIGGER).start())


# ---------------------------------------------------------------- periodic: rt_summary, version_adoption
def refresh_summary() -> None:
    recent = (spark.read.format("delta").load(path("silver.learning_events"))
              .where(F.col("event_date") >= F.date_sub(F.current_date(), 1)))
    r = recent.agg(
        F.sum(F.when(F.col("received_at") >= F.expr("current_timestamp() - INTERVAL 1 MINUTE"), 1).otherwise(0))
        .alias("events_last_1m"),
        F.countDistinct(F.when(F.col("received_at") >= F.expr("current_timestamp() - INTERVAL 5 MINUTES"),
                               F.col("session_id"))).alias("active_sessions_5m")).first()
    upsert("rt_summary", [{"_id": "global", "events_last_1m": int(r.events_last_1m or 0),
                           "active_sessions_5m": int(r.active_sessions_5m or 0),
                           "updated_at": datetime.now(timezone.utc)}])


def refresh_version_adoption() -> None:
    from delta.tables import DeltaTable
    tb.register_names(spark)
    latest = spark.sql("""
        SELECT player_id, build_version, content_version,
               row_number() OVER (PARTITION BY player_id ORDER BY event_time DESC) AS rn
        FROM (SELECT player_id, build_version, content_version, event_time FROM silver.learning_events
              WHERE event_date >= date_sub(current_date(), 1)
              UNION ALL
              SELECT player_id, build_version, content_version, event_time FROM silver.update_events
              WHERE event_date >= date_sub(current_date(), 1))
        WHERE event_time >= current_timestamp() - INTERVAL 24 HOURS""").where("rn = 1")
    latest = latest.persist()
    try:
        total = latest.count()
        per = (latest.select(F.lit("build").alias("kind"), F.col("build_version").alias("version"))
               .unionByName(latest.select(F.lit("content").alias("kind"), F.col("content_version").alias("version")))
               .groupBy("kind", "version").agg(F.count(F.lit(1)).alias("installs"))
               .withColumn("share", F.col("installs") / F.lit(total if total else 1))
               .withColumn("updated_at", F.current_timestamp())).persist()
        (DeltaTable.forPath(spark, path("gold.version_adoption")).alias("t")
         .merge(per.alias("s"), "t.kind = s.kind AND t.version = s.version")
         .whenMatchedUpdateAll().whenNotMatchedInsertAll().whenNotMatchedBySourceDelete().execute())
        docs = [dict(r.asDict(), _id=f"{r.kind}:{r.version}") for r in per.collect()]
        upsert("rt_versions", docs)
        # versions with no install in the last 24 h are removed in Delta and in MongoDB (D12)
        mongo()["rt_versions"].delete_many({"_id": {"$nin": [d["_id"] for d in docs]}})
        per.unpersist()
    finally:
        latest.unpersist()


def periodic(stop: threading.Event) -> None:
    last_versions = 0.0
    while not stop.wait(10):
        try:
            # Persist observability outside stdout; rows/rates are per query, not end-to-end throughput.
            import json
            from pathlib import Path
            destination = Path(os.getenv("PROGRESS_PATH", "/data/metrics/streaming-progress.json"))
            destination.parent.mkdir(parents=True, exist_ok=True)
            report = {"updated_at": datetime.now(timezone.utc).isoformat(),
                      "queries": [{"name": q.name, "active": q.isActive,
                                   "status": q.status, "progress": q.lastProgress}
                                  for q in spark.streams.active]}
            temporary = destination.with_suffix(".tmp")
            temporary.write_text(json.dumps(report, default=str), encoding="utf-8")
            temporary.replace(destination)
            refresh_summary()
            if time.monotonic() - last_versions >= 60:
                refresh_version_adoption()
                last_versions = time.monotonic()
        except Exception:  # keep the streams alive; next tick retries
            log.exception("periodic refresh failed")



def start_runtime_export():
    import json
    from remote.outbox import stage
    rows = spark.readStream.format("delta").load(path("bronze.game_events")).where(F.col("topic") == "nv.runtime.v1")
    def write(batch, batch_id):
        stage(json.loads(row.value) for row in batch.select("value").toLocalIterator())
    return (rows.writeStream.queryName("remote_runtime").foreachBatch(write)
            .option("checkpointLocation", tb.checkpoint("remote-runtime-v1"))
            .trigger(processingTime=STAGE_TRIGGER).start())

def main() -> None:
    tb.ensure_tables(spark)
    queries = []
    for pool, starter in (("bronze", start_bronze), ("silver", start_silver), ("audit", start_silver_audit),
                          ("gold", start_gold_learning), ("update", start_gold_updates)):
        spark.sparkContext.setLocalProperty("spark.scheduler.pool", pool)  # FAIR: one pool per stage
        started = starter()
        queries.extend(started if isinstance(started, tuple) else [started])
    if os.getenv("REMOTE_EXPORT_ENABLED", "0") == "1":
        queries.append(start_runtime_export())
    spark.sparkContext.setLocalProperty("spark.scheduler.pool", "periodic")
    log.info("started queries: %s", [q.name for q in queries])
    stop = threading.Event()
    threading.Thread(target=periodic, args=(stop,), daemon=True, name="periodic").start()
    try:
        spark.streams.awaitAnyTermination()
    finally:
        stop.set()


if __name__ == "__main__":
    main()
