"""Deterministic routing, immutable event IDs and replay-safe metrics."""
import hashlib, json
from pymongo.errors import DuplicateKeyError

def route(db, event, position):
    from gateway import Event, RuntimeEvent
    try:
        model = RuntimeEvent if event.get("event_type", "").startswith(("exit_", "run_")) else Event
        validated=model.model_validate({k:v for k,v in event.items() if k != "received_at"}).model_dump(mode="json")
    except Exception:
        db.quarantine_events.update_one({"_id":position},{"$setOnInsert":{"reason":"invalid_schema","payload":event}},upsert=True)
        return
    canonical=json.dumps(validated,sort_keys=True,separators=(",",":"))
    digest=hashlib.sha256(canonical.encode()).hexdigest()
    event_id=validated.pop("event_id")
    try:
        db.event_registry.insert_one({"_id":event_id,"hash":digest})
    except DuplicateKeyError:
        if db.event_registry.find_one({"_id":event_id})["hash"] != digest:
            db.quarantine_events.update_one({"_id":position},{"$setOnInsert":{"reason":"event_id_conflict","payload":event}},upsert=True)
            return
    collection = db.runtime_events if model is RuntimeEvent else db.curated
    collection.update_one({"_id":event_id},{"$setOnInsert":validated},upsert=True)
    if model is RuntimeEvent and validated["event_type"].startswith("exit_"):
        db.incidents.update_one({"_id":event_id},{"$setOnInsert":validated},upsert=True)

def aggregate(db):
    stages=[{"$group":{"_id":{"player_id":"$player_id","problem_id":"$problem_id"},"events":{"$sum":1},**{name:{"$sum":{"$cond":[{"$eq":["$event_type",kind]},1,0]}} for name,kind in [("failures","attempt_failed"),("successes","attempt_succeeded"),("hints","hint_used")]}}},{"$merge":{"into":"metrics","on":"_id","whenMatched":"replace","whenNotMatched":"insert"}}]
    list(db.curated.aggregate(stages))
