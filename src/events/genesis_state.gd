class_name GenesisState
extends ScenarioState
## Pure reduction of GENESIS simulation events into the state of the world (same pattern as
## WorldState). Every "*_at" field is the simulation time of the event, or -1.0 if not yet
## happened; visuals read them with Simulation.time (e.g. `progress(ring_at, now, 2.0)`), so
## pause, seek and reset are always consistent. `session_at`, `completed_at`, `since()` and
## `progress()` come from ScenarioState.

enum Phase { STILL, AWAKENING, SUMMONING, GATHERING, SEEDED, FORMING, MOONS, RING, BELT, WEAVING, STABLE, COMPLETE }

const PHASE_NAMES: Array[String] = [
	"STILLNESS", "AWAKENING", "THE HANDS", "GATHERING", "SEEDED", "FORMING",
	"MOONRISE", "RING OF SKILLS", "MEMORY BELT", "WEAVING", "STABLE", "COMPLETE",
]

var phase: Phase = Phase.STILL
var awaken_at := -1.0
var hands_at := -1.0
var dust_at := -1.0
var seeded_at := -1.0
## Time of each planet layer (0 mantle, 1 crust, 2 atmosphere), -1.0 until formed.
var planet_layer_times: PackedFloat64Array
## Time each documentation moon formed, -1.0 until formed.
var moon_times: PackedFloat64Array
## Moon names from the MOON_FORMED payloads ("" until formed).
var moon_names: PackedStringArray
var ring_at := -1.0
var belt_at := -1.0
var links_at := -1.0
## Number of relational threads woven (LINKS_WOVEN payload "count").
var link_count := 0
var stable_at := -1.0
## Name of the forming world (PLANET_SEEDED / PLANET_STABLE payload "name"), "" until seeded.
var planet_name := ""


func _init() -> void:
	planet_layer_times = PackedFloat64Array()
	planet_layer_times.resize(GenesisScript.LAYER_COUNT)
	planet_layer_times.fill(-1.0)
	moon_times = PackedFloat64Array()
	moon_times.resize(GenesisScript.MOON_COUNT)
	moon_times.fill(-1.0)
	moon_names = PackedStringArray()
	moon_names.resize(GenesisScript.MOON_COUNT)


static func derive(events: Array[SimEvent]) -> GenesisState:
	var g := GenesisState.new()
	for e in events:
		g.apply(e)
	return g


## Applies one event. Returns false for unknown types or out-of-range payloads (ignored).
func apply(e: SimEvent) -> bool:
	match e.type:
		SimEvent.SESSION_OPENED:
			session_at = e.time
		SimEvent.MIKU_AWAKEN:
			awaken_at = e.time
			phase = Phase.AWAKENING
		SimEvent.HANDS_SUMMONED:
			hands_at = e.time
			phase = Phase.SUMMONING
		SimEvent.DUST_GATHERED:
			dust_at = e.time
			phase = Phase.GATHERING
		SimEvent.PLANET_SEEDED:
			seeded_at = e.time
			planet_name = String(e.payload.get("name", planet_name))
			phase = Phase.SEEDED
		SimEvent.PLANET_LAYER:
			var i := int(e.payload.get("layer", -1))
			if i < 0 or i >= planet_layer_times.size():
				push_warning("PLANET_LAYER with out-of-range layer %d" % i)
				return false
			planet_layer_times[i] = e.time
			phase = Phase.FORMING
		SimEvent.MOON_FORMED:
			var m := int(e.payload.get("index", -1))
			if m < 0 or m >= moon_times.size():
				push_warning("MOON_FORMED with out-of-range index %d" % m)
				return false
			moon_times[m] = e.time
			moon_names[m] = String(e.payload.get("name", ""))
			phase = Phase.MOONS
		SimEvent.RING_FORMED:
			ring_at = e.time
			phase = Phase.RING
		SimEvent.BELT_FORMED:
			belt_at = e.time
			phase = Phase.BELT
		SimEvent.LINKS_WOVEN:
			links_at = e.time
			link_count = int(e.payload.get("count", 0))
			phase = Phase.WEAVING
		SimEvent.PLANET_STABLE:
			stable_at = e.time
			planet_name = String(e.payload.get("name", planet_name))
			phase = Phase.STABLE
		SimEvent.SESSION_COMPLETED:
			completed_at = e.time
			phase = Phase.COMPLETE
		_:
			push_warning("Unknown GENESIS event type: %s" % e.type)
			return false
	return true


func phase_name() -> String:
	return PHASE_NAMES[phase]


func phase_index() -> int:
	return phase


func layers_formed() -> int:
	return _count_set(planet_layer_times)


func moons_formed() -> int:
	return _count_set(moon_times)


## Time layer `i` formed, or -1.0 (also for an out-of-range index).
func layer_at(i: int) -> float:
	return planet_layer_times[i] if i >= 0 and i < planet_layer_times.size() else -1.0


## Time moon `i` formed, or -1.0 (also for an out-of-range index).
func moon_at(i: int) -> float:
	return moon_times[i] if i >= 0 and i < moon_times.size() else -1.0


## Smooth 0..1 growth of layer `i` at `now` over `ramp` seconds.
func layer_progress(i: int, now: float, ramp: float) -> float:
	return progress(layer_at(i), now, ramp)


## Smooth 0..1 growth of moon `i` at `now` over `ramp` seconds.
func moon_progress(i: int, now: float, ramp: float) -> float:
	return progress(moon_at(i), now, ramp)


## Overall formation of the world at `now`, 0..1: 0 before seeding, rises through the three
## layers (each eases in over `ramp` seconds) and reaches 1 only once the planet is stable.
## Seeded alone counts as the first step. Monotonic in `now` for a fixed state.
func formation(now: float, ramp: float) -> float:
	if seeded_at < 0.0 or now < seeded_at:
		return 0.0
	var steps := float(GenesisScript.LAYER_COUNT + 2)
	var f := progress(seeded_at, now, ramp)
	for i in planet_layer_times.size():
		f += layer_progress(i, now, ramp)
	f += progress(stable_at, now, ramp)
	return clampf(f / steps, 0.0, 1.0)


static func _count_set(times: PackedFloat64Array) -> int:
	var n := 0
	for t in times:
		if t >= 0.0:
			n += 1
	return n
