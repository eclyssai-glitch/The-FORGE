class_name Mission
extends RefCounted
## Fictional mission shown in the OBSERVATORY: an ordered list of objectives,
## each completed by one simulation event type. Status is derived, never stored.
## One mission per scenario (see Scenario): evaluate(emitted, scenario) picks the list.

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


const GENESIS_ID := &"mission.genesis"
const GENESIS_TITLE := "GENESIS — A WORLD IS BORN"

const GENESIS_OBJECTIVES: Array[Dictionary] = [
	{"id": &"awaken", "title": "Wake MIKU", "done_on": SimEvent.MIKU_AWAKEN, "min_count": 1},
	{"id": &"hands", "title": "Summon the hands", "done_on": SimEvent.HANDS_SUMMONED, "min_count": 1},
	{"id": &"dust", "title": "Gather the stardust", "done_on": SimEvent.DUST_GATHERED, "min_count": 1},
	{"id": &"seed", "title": "Seed a new world", "done_on": SimEvent.PLANET_SEEDED, "min_count": 1},
	{"id": &"layers", "title": "Form mantle, crust and sky", "done_on": SimEvent.PLANET_LAYER, "min_count": GenesisScript.LAYER_COUNT},
	{"id": &"moons", "title": "Raise the documentation moons", "done_on": SimEvent.MOON_FORMED, "min_count": GenesisScript.MOON_COUNT},
	{"id": &"ring", "title": "Condense the ring of skills", "done_on": SimEvent.RING_FORMED, "min_count": 1},
	{"id": &"belt", "title": "Settle the memory belt", "done_on": SimEvent.BELT_FORMED, "min_count": 1},
	{"id": &"links", "title": "Weave the threads of light", "done_on": SimEvent.LINKS_WOVEN, "min_count": 1},
	{"id": &"stable", "title": "Hold a stable orbit", "done_on": SimEvent.PLANET_STABLE, "min_count": 1},
]


const LIVING_ID := &"mission.living"
const LIVING_TITLE := "MIKU — A LIVING CHARACTER"

const LIVING_OBJECTIVES: Array[Dictionary] = [
	{"id": &"life", "title": "Be alive before any work", "done_on": SimEvent.LIVING_MILESTONE, "min_count": 1},
	{"id": &"puppet", "title": "Command one hand, then two, then many", "done_on": SimEvent.LIVING_HANDS, "min_count": LivingScript.HAND_CUE_COUNT},
	{"id": &"order", "title": "Take the work order", "done_on": SimEvent.LIVING_WORK_ORDER, "min_count": 1},
	{"id": &"build", "title": "Build the world in stages", "done_on": SimEvent.LIVING_WORK_STEP, "min_count": LivingScript.STEP_COUNT},
	{"id": &"failure", "title": "Fail, and fail again", "done_on": SimEvent.LIVING_WORK_FAILED, "min_count": LivingScript.FAIL_COUNT},
	{"id": &"dismantle", "title": "Tear down what went wrong", "done_on": SimEvent.LIVING_WORK_DISMANTLED, "min_count": 1},
	{"id": &"recover", "title": "Recover", "done_on": SimEvent.LIVING_WORK_RECOVERED, "min_count": 1},
	{"id": &"whole", "title": "Make the world whole", "done_on": SimEvent.LIVING_WORLD_COMPLETE, "min_count": 1},
	{"id": &"user", "title": "Open the user tests (attention, target, configuration)", "done_on": SimEvent.LIVING_MILESTONE, "min_count": LivingScript.MILESTONE_COUNT},
]


## Objective list of a scenario (Scenario.ORIGIN_CHAMBER when unknown).
static func objectives_for(scenario: StringName) -> Array[Dictionary]:
	match scenario:
		Scenario.GENESIS:
			return GENESIS_OBJECTIVES
		Scenario.LIVING:
			return LIVING_OBJECTIVES
	return ORIGIN_CHAMBER_OBJECTIVES


## Mission title of a scenario (Scenario.ORIGIN_CHAMBER when unknown).
static func title_for(scenario: StringName) -> String:
	match scenario:
		Scenario.GENESIS:
			return GENESIS_TITLE
		Scenario.LIVING:
			return LIVING_TITLE
	return ORIGIN_CHAMBER_TITLE


## Returns the scenario's objectives with "count" and "done" fields derived from emitted events.
static func evaluate(emitted: Array[SimEvent], scenario: StringName = &"origin_chamber") -> Array[Dictionary]:
	var counts := {}
	for e in emitted:
		counts[e.type] = int(counts.get(e.type, 0)) + 1
	var out: Array[Dictionary] = []
	for o in objectives_for(scenario):
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
