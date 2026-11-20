"""Offline OPTIMIZE/ZORDER. Plan by default. Stop streaming writers before --execute.
No VACUUM, schema migration, deletion or checkpoint changes.
"""
import argparse
import json
from datetime import date
import tables as tb

COLUMNS = {
    "bronze.game_events": ["topic", "partition"],
    "silver.learning_events": ["minigame_id", "player_id", "event_id"],
    "silver.update_events": ["player_id", "event_id"],
}


def statements(table, day=None):
    if table not in COLUMNS:
        raise ValueError("unsupported table")
    partition = "ingest_date" if table.startswith("bronze.") else "event_date"
    predicate = ""
    if day:
        date.fromisoformat(day)
        predicate = f" WHERE {partition} = DATE '{day}'"
    return f"OPTIMIZE {table}{predicate} ZORDER BY ({', '.join(COLUMNS[table])})"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--table", nargs="+", choices=list(COLUMNS), default=["silver.learning_events"])
    p.add_argument("--date", help="UTC partition YYYY-MM-DD; omit to optimize all")
    p.add_argument("--execute", action="store_true")
    a = p.parse_args()
    plans = [(table, statements(table, a.date)) for table in a.table]
    if not a.execute:
        print(json.dumps({"execute": False, "sql": [sql for _, sql in plans], "requires": "stop streaming writers"}))
        return
    spark = tb.spark_session("nodeverse-maintenance")
    try:
        from pathlib import Path
        tb.register_names(spark)
        reports = []
        for table, sql in plans:
            before = spark.sql(f"DESCRIBE DETAIL {table}").first().asDict()
            before_rows = spark.table(table).count()
            result = [r.asDict(recursive=True) for r in spark.sql(sql).collect()]
            after = spark.sql(f"DESCRIBE DETAIL {table}").first().asDict()
            after_rows = spark.table(table).count()
            if before_rows != after_rows:
                raise RuntimeError("OPTIMIZE row count changed; inspect before resuming streams")
            reports.append({"before_rows": before_rows, "after_rows": after_rows, "table": table, "sql": sql,
                            "before_files": before["numFiles"], "after_files": after["numFiles"], "metrics": result})
        encoded = json.dumps(reports, default=str, indent=2)
        Path("/data/metrics").mkdir(exist_ok=True)
        Path("/data/metrics/maintenance.json").write_text(encoded)
        print(encoded)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
