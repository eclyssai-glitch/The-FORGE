class_name LivingScript
extends RefCounted
## Scripted demonstration of the MIKU LIVING CHARACTER prototype (Loop 5, docs/contracts/loop-05.md).
## Entirely fictional. The Simulation plays these events (work orders and their outcomes); MIKU's
## mind REACTS to them in real time (ADR-015: no seek in this scenario, reset = recompose).
## Times are seconds from session start, ascending.
##
## Segments (milestone `test` 1..7, one per prototype test):
##   1 LIFE           0.5 – 12   she is alive before any work (no events: life is her own)
##   2 PUPPET         12 – 31    the work asks for 1 hand, then 2, then 4
##   3 WORLD WORK     31 – 57    order on CALYX: GATHER, COMPRESS, MANTLE, CRUST in stages
##   4 FAILURE        57 – 89    SKY fails, an elegant retry fails again, she loses composure,
##                               tears the faulty sky down with 6 hands, rebuilds it, recovers;
##                               the world completes at 83
##   5 USER ATTENTION 89 – 101   window for the user to call her (cue: click on MIKU at 90)
##   6 WORLD TARGET   101 – 114  window to point at a world (cue: click on VESPER at 102)
##   7 CONFIGURATION  114 – 140  window to change a property (cues: "Miku, aumente sua altura"
##                               at 115, a SEMANTIC request with no provider at 130)
## USER_CUES are only used by automation (captures, recording tour) to inject REAL input at
## those moments; in play the user does it whenever they like.

const DURATION := 140.0

## Selectable worlds of the prototype: id, display name, side seen from the default framing and
## a default anchor (the animator's WorkWorld may lay them out differently; the interaction
## system computes left/right from what the camera shows).
const WORLDS: Array[Dictionary] = [
	{"id": &"world_vesper", "name": "VESPER", "side": &"left", "anchor": Vector3(-5.5, 1.8, 1.0)},
	{"id": &"world_calyx", "name": "CALYX", "side": &"center", "anchor": Vector3(0.0, 1.2, 3.0)},
	{"id": &"world_orrin", "name": "ORRIN", "side": &"right", "anchor": Vector3(5.5, 1.8, 1.0)},
]
## The world built by the scripted work order.
const WORK_WORLD := &"world_calyx"
const ORDER_ID := &"wo-calyx"
## Construction steps of the order, in order. SKY is the step that fails.
const STEPS: Array[String] = ["GATHER", "COMPRESS", "MANTLE", "CRUST", "SKY"]
const STEP_DETAILS: Array[String] = [
	"Matter is gathered from the dark into a loose cloud",
	"The cloud is compressed into a dense core",
	"A molten mantle is drawn around the core",
	"The mantle is cooled and pressed into a crust",
	"A thin sky is spun around the crust",
]
const FAILING_STEP := 4
## Counts (constant expressions for Mission; tests keep them equal to the arrays' sizes).
const STEP_COUNT := 5
const MILESTONE_COUNT := 7
const HAND_CUE_COUNT := 3
const FAIL_COUNT := 2

const MILESTONE_NAMES: Array[String] = [
	"LIFE", "PUPPET", "WORLD WORK", "FAILURE", "USER ATTENTION", "WORLD TARGET", "CONFIGURATION",
]
## Milestone i+1 at MILESTONE_TIMES[i].
const MILESTONE_TIMES: Array[float] = [0.5, 12.0, 31.0, 57.0, 89.0, 101.0, 114.0]
## PUPPET: hands requested [time, count].
const HAND_CUES: Array = [[13.0, 1], [19.0, 2], [25.0, 4]]
const T_ORDER := 31.5
## [time, step, attempt, hands]
const STEP_CUES: Array = [
	[33.0, 0, 1, 2], [39.0, 1, 1, 2], [45.0, 2, 1, 3], [51.0, 3, 1, 4],
	[57.5, 4, 1, 2], [64.5, 4, 2, 2], [75.0, 4, 3, 4],
]
## [time, attempt]
const FAIL_CUES: Array = [[61.0, 1], [68.0, 2]]
const T_DISMANTLE := 70.5
const DISMANTLE_HANDS := 6
const T_RECOVERED := 79.0
const T_WORLD_COMPLETE := 83.0

## Real user interactions injected by automation: [time, kind, argument].
## kind "click": a mouse click on the entity's pick body; "say": Enter, the text typed on the
## call line, Enter.
const USER_CUES: Array = [
	[90.0, "click", &"miku"],
	[102.0, "click", &"world_vesper"],
	[115.0, "say", "Miku, aumente sua altura"],
	[130.0, "say", "Miku, fique mais curiosa, mas menos impulsiva"],
]


static func build() -> Array[SimEvent]:
	var e: Array[SimEvent] = []
	var n := 0
	e.append(SimEvent.new(_id(n), 0.0, SimEvent.SESSION_OPENED, "SESSION OPENED",
		"Demo session opened. All events in this session are simulated.", &"miku"))
	n += 1
	for i in MILESTONE_TIMES.size():
		e.append(SimEvent.new(_id(n), MILESTONE_TIMES[i], SimEvent.LIVING_MILESTONE,
			"TEST %d · %s" % [i + 1, MILESTONE_NAMES[i]], "Prototype test %d (%s) begins." % [i + 1,
			MILESTONE_NAMES[i].to_lower()], &"miku", {"test": i + 1, "name": MILESTONE_NAMES[i]}))
		n += 1
	for c: Array in HAND_CUES:
		e.append(SimEvent.new(_id(n), c[0], SimEvent.LIVING_HANDS,
			"%d HAND%s" % [c[1], "" if c[1] == 1 else "S"], "The work calls for %d puppet hand%s." % [c[1],
			"" if c[1] == 1 else "s"], &"miku", {"count": c[1], "world": WORK_WORLD}))
		n += 1
	e.append(SimEvent.new(_id(n), T_ORDER, SimEvent.LIVING_WORK_ORDER, "WORK ORDER · CALYX",
		"Work order %s: build the world CALYX in %d steps." % [ORDER_ID, STEPS.size()], WORK_WORLD,
		{"order": ORDER_ID, "world": WORK_WORLD, "steps": STEPS}))
	n += 1
	for c: Array in STEP_CUES:
		var step: int = c[1]
		var attempt: int = c[2]
		e.append(SimEvent.new(_id(n), c[0], SimEvent.LIVING_WORK_STEP,
			STEPS[step] if attempt == 1 else "%s · ATTEMPT %d" % [STEPS[step], attempt],
			"%s (step %d of %d)." % [STEP_DETAILS[step], step + 1, STEPS.size()], WORK_WORLD,
			{"order": ORDER_ID, "world": WORK_WORLD, "step": step, "name": STEPS[step], "attempt": attempt,
				"hands": c[3]}))
		n += 1
	for c: Array in FAIL_CUES:
		e.append(SimEvent.new(_id(n), c[0], SimEvent.LIVING_WORK_FAILED,
			"%s FAILS" % STEPS[FAILING_STEP] if c[1] == 1 else "%s FAILS AGAIN" % STEPS[FAILING_STEP],
			"The sky tears open around the crust (attempt %d)." % c[1], WORK_WORLD,
			{"order": ORDER_ID, "world": WORK_WORLD, "step": FAILING_STEP, "name": STEPS[FAILING_STEP],
				"attempt": c[1]}))
		n += 1
	e.append(SimEvent.new(_id(n), T_DISMANTLE, SimEvent.LIVING_WORK_DISMANTLED, "TORN DOWN",
		"The faulty sky is torn down by %d hands." % DISMANTLE_HANDS, WORK_WORLD,
		{"order": ORDER_ID, "world": WORK_WORLD, "step": FAILING_STEP, "name": STEPS[FAILING_STEP],
			"hands": DISMANTLE_HANDS}))
	n += 1
	e.append(SimEvent.new(_id(n), T_RECOVERED, SimEvent.LIVING_WORK_RECOVERED, "THE SKY HOLDS",
		"The rebuilt sky holds.", WORK_WORLD,
		{"order": ORDER_ID, "world": WORK_WORLD, "step": FAILING_STEP, "name": STEPS[FAILING_STEP]}))
	n += 1
	e.append(SimEvent.new(_id(n), T_WORLD_COMPLETE, SimEvent.LIVING_WORLD_COMPLETE, "CALYX IS WHOLE",
		"The world CALYX is complete.", WORK_WORLD,
		{"order": ORDER_ID, "world": WORK_WORLD, "name": "CALYX"}))
	n += 1
	e.append(SimEvent.new(_id(n), DURATION, SimEvent.SESSION_COMPLETED, "SESSION COMPLETE",
		"Demo session complete. Nothing was sent or received.", &"miku"))
	e.sort_custom(func(a: SimEvent, b: SimEvent) -> bool: return a.time < b.time)
	# Ids follow the time order.
	var out: Array[SimEvent] = []
	for i in e.size():
		var x := e[i]
		out.append(SimEvent.new(_id(i), x.time, x.type, x.label, x.detail, x.entity, x.payload))
	return out


## World row of `id` ({} if unknown).
static func world(id: StringName) -> Dictionary:
	for w in WORLDS:
		if w["id"] == id:
			return w
	return {}


static func world_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for w in WORLDS:
		out.append(w["id"])
	return out


## Worlds as the parser/router expect them ([{"id", "name", "side"}]).
static func world_directory() -> Array:
	var out: Array = []
	for w in WORLDS:
		out.append({"id": w["id"], "name": w["name"], "side": w["side"]})
	return out


## Time milestone `test` (1..7) starts, or -1.0.
static func milestone_time(test: int) -> float:
	return MILESTONE_TIMES[test - 1] if test >= 1 and test <= MILESTONE_TIMES.size() else -1.0


static func _id(n: int) -> StringName:
	return StringName("lv-%03d" % n)
