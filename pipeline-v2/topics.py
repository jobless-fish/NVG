"""Kafka topics of the common contract (standard library only; used by build_compose.py)."""

TOPIC_LEARNING = "nv.learning.v2"
TOPIC_RUNTIME = "nv.runtime.v1"
TOPIC_BUNDLE = "nv.bundle.v2"   # reserved: no producer/consumer yet (see docs/DECISIONS.md D2)
TOPIC_DLQ = "nv.dlq.v1"
TOPIC_UPDATE = "nv.update.v1"

# name -> partitions (retention 7 days for all)
TOPICS = {
    TOPIC_LEARNING: 6,
    TOPIC_RUNTIME: 3,
    TOPIC_BUNDLE: 3,
    TOPIC_DLQ: 3,
    TOPIC_UPDATE: 3,
}
RETENTION_MS = 7 * 24 * 3600 * 1000
