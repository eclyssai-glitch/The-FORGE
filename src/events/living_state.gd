class_name LivingState
extends ScenarioState
## Pure reduction of the LIVING scenario's events (Loop 5): which test segment is on, how many
## hands the work asks for, where the work order stands, its failures and recovery. Every
## "*_at" field is the simulation time of the event, or -1.0.
## Unlike GENESIS, the character is NOT a function of this state + time (ADR-015): MIKU's mind
## reacts to the events as they are emitted and keeps its own real-time state. This state is
## what the scenario-agnostic readers (UI phase, mission, smoke) and the work world read.

enum Phase { STILL, LIFE, PUPPET, WORLD_WORK, FAILURE, ATTENTION, TARGET, CONFIGURATION, COMPLETE }

const PHASE_NAMES: Array[String] = [
	"STILLNESS", "LIFE", "PUPPET", "WORLD WORK", "FAILURE", "USER ATTENTION", "WORLD TARGET",
	"CONFIGURATION", "COMPLETE",
]

var phase: Phase = Phase.STILL
## Start time of each test segment (index test-1), -1.0 until it starts.
var milestone_times: PackedFloat64Array
## Current test segment (1..7), 0 before the first.
var test := 0
## Hands the work asks for (LIVING_HANDS / work steps / dismantle), and when it last changed.
var hands := 0
var hands_at := -1.0
## Work order.
var order_at := -1.0
var order_world: StringName = &""
var order_steps: PackedStringArray
## Step in progress (-1 none), its name, attempt and start time.
var step := -1
var step_name := ""
var attempt := 0
var step_at := -1.0
## Last start time of each step (index = step), -1.0 until started.
var step_times: PackedFloat64Array
var failures := 0
var failed_at := -1.0
var dismantled_at := -1.0
var recovered_at := -1.0
var world_complete_at := -1.0


func _init() -> void:
	milestone_times = PackedFloat64Array()
	milestone_times.resize(LivingScript.MILESTONE_TIMES.size())
	milestone_times.fill(-1.0)
	step_times = PackedFloat64Array()
	step_times.resize(LivingScript.STEPS.size())
	step_times.fill(-1.0)
	order_steps = PackedStringArray()


static func derive(events: Array[SimEvent]) -> LivingState:
	var s := LivingState.new()
	for e in events:
		s.apply(e)
	return s


func apply(e: SimEvent) -> bool:
	match e.type:
		SimEvent.SESSION_OPENED:
			session_at = e.time
		SimEvent.LIVING_MILESTONE:
			var t := int(e.payload.get("test", 0))
			if t < 1 or t > milestone_times.size():
				push_warning("living.milestone with out-of-range test %d" % t)
				return false
			milestone_times[t - 1] = e.time
			test = t
			phase = t as Phase
		SimEvent.LIVING_HANDS:
			hands = maxi(int(e.payload.get("count", 0)), 0)
			hands_at = e.time
		SimEvent.LIVING_WORK_ORDER:
			order_at = e.time
			order_world = StringName(e.payload.get("world", &""))
			order_steps = PackedStringArray(e.payload.get("steps", []))
		SimEvent.LIVING_WORK_STEP:
			var i := int(e.payload.get("step", -1))
			if i < 0 or i >= step_times.size():
				push_warning("living.work_step with out-of-range step %d" % i)
				return false
			step = i
			step_name = String(e.payload.get("name", ""))
			attempt = int(e.payload.get("attempt", 1))
			step_at = e.time
			step_times[i] = e.time
			hands = int(e.payload.get("hands", hands))
			hands_at = e.time
		SimEvent.LIVING_WORK_FAILED:
			failures += 1
			failed_at = e.time
		SimEvent.LIVING_WORK_DISMANTLED:
			dismantled_at = e.time
			hands = int(e.payload.get("hands", hands))
			hands_at = e.time
		SimEvent.LIVING_WORK_RECOVERED:
			recovered_at = e.time
		SimEvent.LIVING_WORLD_COMPLETE:
			world_complete_at = e.time
		SimEvent.SESSION_COMPLETED:
			completed_at = e.time
			phase = Phase.COMPLETE
		_:
			push_warning("Unknown LIVING event type: %s" % e.type)
			return false
	return true


func phase_name() -> String:
	return PHASE_NAMES[phase]


func phase_index() -> int:
	return phase


## True between a failure and the recovery that answers it.
func is_failing() -> bool:
	return failed_at >= 0.0 and recovered_at < failed_at


## Steps of the order finished: every step before the one in progress, plus the last one once
## the world is complete. The failing step counts only once it recovered.
func steps_done() -> int:
	if world_complete_at >= 0.0:
		return LivingScript.STEPS.size()
	if step < 0:
		return 0
	if step == LivingScript.FAILING_STEP and recovered_at >= 0.0:
		return step + 1
	return step


## Time milestone `t` (1..7) started, or -1.0.
func milestone_at(t: int) -> float:
	return milestone_times[t - 1] if t >= 1 and t <= milestone_times.size() else -1.0
