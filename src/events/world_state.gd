class_name WorldState
extends RefCounted
## Pure reduction of simulation events into the state of the world.
## Every "*_at" field is the simulation time of the event, or -1.0 if not yet happened.
## Visual systems read these timestamps together with the current playhead, so
## pause, seek and reset are always consistent.

enum Phase { DORMANT, ACTIVATING, CORE_ONLINE, FRAGMENTS, BUILDING, FINISHING, VERIFYING, VERIFIED, FINAL, COMPLETE }

const PHASE_NAMES: Array[String] = [
	"DORMANT", "ACTIVATING", "CORE ONLINE", "FRAGMENTS", "BUILDING",
	"FINISHING", "VERIFYING", "VERIFIED", "FINAL FORM", "COMPLETE",
]

var phase: Phase = Phase.DORMANT
var session_at := -1.0
var core_activation_at := -1.0
var core_online_at := -1.0
var fragments_at := -1.0
var fragment_count := 0
var seeded_at := -1.0
var layer_times: PackedFloat64Array
var materials_at := -1.0
var lighting_at := -1.0
var verification_at := -1.0
## Ordered list of {"check": StringName, "at": float}.
var checks: Array[Dictionary] = []
var verified_at := -1.0
var finalized_at := -1.0
var completed_at := -1.0


func _init(layer_count: int = OriginChamberScript.LAYER_COUNT) -> void:
	layer_times = PackedFloat64Array()
	layer_times.resize(layer_count)
	layer_times.fill(-1.0)


static func derive(events: Array[SimEvent], layer_count: int = OriginChamberScript.LAYER_COUNT) -> WorldState:
	var w := WorldState.new(layer_count)
	for e in events:
		w.apply(e)
	return w


## Applies one event. Returns false for unknown types (which are ignored).
func apply(e: SimEvent) -> bool:
	match e.type:
		SimEvent.SESSION_OPENED:
			session_at = e.time
		SimEvent.CORE_ACTIVATION:
			core_activation_at = e.time
			phase = Phase.ACTIVATING
		SimEvent.CORE_ONLINE:
			core_online_at = e.time
			phase = Phase.CORE_ONLINE
		SimEvent.FRAGMENTS_EMITTED:
			fragments_at = e.time
			fragment_count = int(e.payload.get("count", 0))
			phase = Phase.FRAGMENTS
		SimEvent.STRUCTURE_SEEDED:
			seeded_at = e.time
			phase = Phase.BUILDING
		SimEvent.LAYER_ADDED:
			var i := int(e.payload.get("layer", -1))
			if i < 0 or i >= layer_times.size():
				push_warning("LAYER_ADDED with out-of-range layer %d" % i)
				return false
			layer_times[i] = e.time
			phase = Phase.BUILDING
		SimEvent.MATERIALS_APPLIED:
			materials_at = e.time
			phase = Phase.FINISHING
		SimEvent.LIGHTING_APPLIED:
			lighting_at = e.time
			phase = Phase.FINISHING
		SimEvent.VERIFICATION_STARTED:
			verification_at = e.time
			phase = Phase.VERIFYING
		SimEvent.CHECK_PASSED:
			checks.append({"check": e.payload.get("check", &""), "at": e.time})
		SimEvent.VERIFICATION_PASSED:
			verified_at = e.time
			phase = Phase.VERIFIED
		SimEvent.STRUCTURE_FINALIZED:
			finalized_at = e.time
			phase = Phase.FINAL
		SimEvent.SESSION_COMPLETED:
			completed_at = e.time
			phase = Phase.COMPLETE
		_:
			push_warning("Unknown simulation event type: %s" % e.type)
			return false
	return true


func layers_built() -> int:
	var n := 0
	for t in layer_times:
		if t >= 0.0:
			n += 1
	return n


func phase_name() -> String:
	return PHASE_NAMES[phase]


## Seconds elapsed since `at` at simulation time `now`; negative if not happened.
static func since(at: float, now: float) -> float:
	return now - at if at >= 0.0 else -1.0
