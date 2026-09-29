class_name Mission
extends RefCounted
## Fictional mission shown in the OBSERVATORY: an ordered list of objectives,
## each completed by one simulation event type. Status is derived, never stored.

const ORIGIN_CHAMBER_ID := &"mission.origin_chamber"
const ORIGIN_CHAMBER_TITLE := "ORIGIN CHAMBER — FIRST CONSTRUCT"

## Each objective: {"id", "title", "done_on": event type, "min_count": int}
const ORIGIN_CHAMBER_OBJECTIVES: Array[Dictionary] = [
	{"id": &"activate", "title": "Activate the core", "done_on": SimEvent.CORE_ONLINE, "min_count": 1},
	{"id": &"fragments", "title": "Release geometric fragments", "done_on": SimEvent.FRAGMENTS_EMITTED, "min_count": 1},
	{"id": &"seed", "title": "Seed the structure", "done_on": SimEvent.STRUCTURE_SEEDED, "min_count": 1},
	{"id": &"layers", "title": "Assemble all layers", "done_on": SimEvent.LAYER_ADDED, "min_count": OriginChamberScript.LAYER_COUNT},
	{"id": &"finish", "title": "Apply materials and lighting", "done_on": SimEvent.LIGHTING_APPLIED, "min_count": 1},
	{"id": &"verify", "title": "Pass verification", "done_on": SimEvent.VERIFICATION_PASSED, "min_count": 1},
	{"id": &"final", "title": "Reach final form", "done_on": SimEvent.STRUCTURE_FINALIZED, "min_count": 1},
]


## Returns objectives with "count" and "done" fields derived from emitted events.
static func evaluate(emitted: Array[SimEvent]) -> Array[Dictionary]:
	var counts := {}
	for e in emitted:
		counts[e.type] = int(counts.get(e.type, 0)) + 1
	var out: Array[Dictionary] = []
	for o in ORIGIN_CHAMBER_OBJECTIVES:
		var row := o.duplicate()
		row["count"] = int(counts.get(o["done_on"], 0))
		row["done"] = row["count"] >= int(o["min_count"])
		out.append(row)
	return out


static func completed_count(objectives: Array[Dictionary]) -> int:
	var n := 0
	for o in objectives:
		if o["done"]:
			n += 1
	return n
