"""Delta table layout under /data/delta and shared Spark setup.

Tables are stored by path and registered by name in every Spark session
(CREATE TABLE ... USING DELTA LOCATION). This keeps names like
`bronze.game_events` usable in SQL (DESCRIBE HISTORY, VERSION AS OF) without a
persistent metastore, so a restarted or separate verify process sees the same
tables (docs/DECISIONS.md D7).
"""
from __future__ import annotations

import os
import time

from pyspark.sql import SparkSession
from pyspark.sql import types as T

LAKE = os.getenv("LAKE_ROOT", "/data/delta")
CHECKPOINTS = os.getenv("CHECKPOINT_ROOT", "/data/checkpoints")  # inside the lake volume (D8)
KAFKA = os.getenv("KAFKA_BOOTSTRAP", "kafka-1:9092,kafka-2:9092,kafka-3:9092")


def path(name: str) -> str:
    db, table = name.split(".")
    return f"{LAKE}/{db}/{table}"


def checkpoint(name: str) -> str:
    return f"{CHECKPOINTS}/{name}"


# ---------------------------------------------------------------- schemas
TS, STR, INT, LONG, DBL, DATE = T.TimestampType(), T.StringType(), T.IntegerType(), T.LongType(), T.DoubleType(), T.DateType()


def _s(*fields):
    return T.StructType([T.StructField(n, t, True) for n, t in fields])


LEARNING_DETAILS = _s(("operation", STR), ("failure_reason", STR), ("level", INT), ("moves", INT),
                      ("mistakes", INT), ("stars", INT), ("hint_id", STR), ("state_before", STR), ("state_after", STR))
UPDATE_DETAILS = _s(("target_version", STR), ("result", STR), ("kind", STR), ("failure_reason", STR),
                    ("bytes", LONG), ("duration_ms", LONG), ("from_version", STR))

# JSON value written by the collector (fields as strings, parsed later)
LEARNING_JSON = _s(("schema_version", INT), ("event_id", STR), ("player_id", STR), ("session_id", STR),
                   ("run_id", STR), ("attempt_id", STR), ("minigame_id", STR), ("category", STR),
                   ("build_version", STR), ("content_version", STR), ("event_type", STR), ("occurred_at", STR),
                   ("sequence", LONG), ("details", LEARNING_DETAILS), ("received_at", STR), ("payload_hash", STR))
UPDATE_JSON = _s(("schema_version", INT), ("event_id", STR), ("player_id", STR), ("run_id", STR),
                 ("build_version", STR), ("content_version", STR), ("event_type", STR), ("occurred_at", STR),
                 ("details", UPDATE_DETAILS), ("received_at", STR), ("payload_hash", STR))

KAFKA_POS = (("kafka_topic", STR), ("kafka_partition", INT), ("kafka_offset", LONG))

SCHEMAS = {
    "bronze.game_events": (_s(("value", STR), ("topic", STR), ("partition", INT), ("offset", LONG),
                              ("kafka_ts", TS), ("ingest_date", DATE)), ["ingest_date"]),
    "silver.learning_events": (_s(("schema_version", INT), ("event_id", STR), ("player_id", STR), ("session_id", STR),
                                  ("run_id", STR), ("attempt_id", STR), ("minigame_id", STR), ("category", STR),
                                  ("build_version", STR), ("content_version", STR), ("event_type", STR),
                                  ("occurred_at", TS), ("sequence", LONG), ("details", LEARNING_DETAILS),
                                  ("event_time", TS), ("received_at", TS), ("payload_hash", STR), *KAFKA_POS,
                                  ("event_date", DATE)), ["event_date"]),
    "silver.update_events": (_s(("schema_version", INT), ("event_id", STR), ("player_id", STR), ("run_id", STR),
                                ("build_version", STR), ("content_version", STR), ("event_type", STR),
                                ("occurred_at", TS), ("details", UPDATE_DETAILS), ("event_time", TS),
                                ("received_at", TS), ("payload_hash", STR), *KAFKA_POS, ("event_date", DATE)),
                             ["event_date"]),
    "silver.quarantine": (_s(*KAFKA_POS, ("reason", STR), ("event_id", STR), ("value", STR),
                             ("detected_at", TS)), []),
    "gold.minigame_1m": (_s(("window_start", TS), ("window_end", TS), ("minigame_id", STR), ("category", STR),
                            ("attempts", LONG), ("successes", LONG), ("failures", LONG), ("hints", LONG),
                            ("players", LONG), ("success_rate", DBL), ("updated_at", TS)), []),
    "gold.failure_alerts": (_s(("window_start", TS), ("window_end", TS), ("minigame_id", STR), ("category", STR),
                               ("attempts", LONG), ("successes", LONG), ("failures", LONG), ("failure_rate", DBL),
                               ("baseline_rate", DBL), ("alert", T.BooleanType()), ("updated_at", TS)), []),
    "gold.update_progress_5m": (_s(("window_start", TS), ("window_end", TS), ("target_version", STR),
                                   ("checks", LONG), ("prompted", LONG), ("accepted", LONG), ("dismissed", LONG),
                                   ("downloads_started", LONG), ("downloads_succeeded", LONG),
                                   ("downloads_failed", LONG), ("mounted", LONG), ("failure_rate", DBL),
                                   ("p50_duration_ms", LONG), ("top_failure_reason", STR), ("updated_at", TS)), []),
    "gold.version_adoption": (_s(("kind", STR), ("version", STR), ("installs", LONG), ("share", DBL),
                                 ("updated_at", TS)), []),
}


def spark_session(app: str, shuffle_partitions: int = 4) -> SparkSession:
    os.environ["TZ"] = "UTC"
    try:
        time.tzset()
    except AttributeError:
        pass
    spark = (SparkSession.builder.appName(app)
             .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
             .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
             .config("spark.sql.warehouse.dir", LAKE)
             .config("spark.sql.session.timeZone", "UTC")
             .config("spark.sql.shuffle.partitions", str(int(os.getenv("SHUFFLE_PARTITIONS", str(shuffle_partitions)))))
             .config("spark.databricks.delta.schema.autoMerge.enabled", "false")
             # Run queries side by side; retain Delta default source materialization for MERGE consistency.
             .config("spark.scheduler.mode", "FAIR")
             .config("spark.sql.streaming.noDataMicroBatches.enabled", "true")
             .config("spark.databricks.delta.snapshotPartitions", "2")
             .config("spark.sql.streaming.stateStore.providerClass",
                     "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider")
             # compaction runs inside the writing batch (no concurrent OPTIMIZE conflicts), but only once
             # 100 small files pile up, so it does not add seconds to every micro-batch
             .config("spark.databricks.delta.autoCompact.enabled", "true")
             .config("spark.databricks.delta.autoCompact.minNumFiles", "100")
             .config("spark.sql.adaptive.coalescePartitions.minPartitionSize", "1MB")
             .getOrCreate())
    spark.sparkContext.setLogLevel(os.getenv("SPARK_LOG_LEVEL", "WARN"))
    return spark


def ensure_tables(spark: SparkSession) -> None:
    """Create missing Delta tables at their path and register all names in this session."""
    from delta.tables import DeltaTable
    for name, (schema, parts) in SCHEMAS.items():
        loc = path(name)
        if not DeltaTable.isDeltaTable(spark, loc):
            builder = DeltaTable.createIfNotExists(spark).location(loc).addColumns(schema)
            if parts:
                builder = builder.partitionedBy(*parts)
            builder.execute()
    register_names(spark)


def register_names(spark: SparkSession) -> None:
    for db in sorted({n.split(".")[0] for n in SCHEMAS}):
        spark.sql(f"CREATE DATABASE IF NOT EXISTS {db}")
    for name in SCHEMAS:
        spark.sql(f"CREATE TABLE IF NOT EXISTS {name} USING DELTA LOCATION '{path(name)}'")
