extends Node
## Autoload "Simulation": owns the demo clock, the event timeline and the derived world.
## The only producer of simulation events. Everything else listens to its signals
## or reads the derived state + `time` — nothing else mutates simulation state.
## One scenario plays at a time (`scenario`, `set_scenario()`; see Scenario): its events feed
## `world` (ORIGIN CHAMBER) or `genesis` (GENESIS); `state` is whichever is active.

signal event_emitted(event: SimEvent)
## Emitted after seek/reset/set_scenario: listeners must rebuild from the state and `emitted_events()`.
signal world_rebuilt
signal playback_changed(status: EventTimeline.Status)
## Emitted by set_scenario() when the active scenario changes (before world_rebuilt).
signal scenario_changed(id: StringName)

## DEMO MODE is the only mode that exists in this version.
const DEMO_MODE := true
## Playable scenarios (ids from Scenario).
const SCENARIOS: Array[StringName] = Scenario.IDS

## Active scenario id (Scenario.DEFAULT at startup; `--scenario=<id>` on the command line).
var scenario: StringName = Scenario.DEFAULT
var timeline: EventTimeline
## ORIGIN CHAMBER state. Fed only while ORIGIN CHAMBER is the active scenario; otherwise it
## stays fresh (DORMANT), so ORIGIN visuals and UI keep compiling and simply rest.
var world: WorldState
## GENESIS state. Fed only while GENESIS is the active scenario; otherwise it stays fresh (STILL).
## GENESIS visuals read `Simulation.genesis` + `Simulation.time`.
var genesis: GenesisState

## State of the active scenario (`world` or `genesis`), for scenario-agnostic readers
## (phase name, completion, Scenario.entity_status).
var state: ScenarioState:
	get:
		return genesis if scenario == Scenario.GENESIS else world


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# `--scenario=<id>` is applied here (autoloads are ready before the main scene), so the
	# world composes the requested scenario directly. Unknown ids are warned about and ignored.
	var requested := scenario_from_args(OS.get_cmdline_user_args())
	if requested != &"":
		if Scenario.is_valid(requested):
			scenario = requested
		else:
			push_warning("Simulation: unknown scenario %s" % requested)
	timeline = EventTimeline.new(Scenario.build_events(scenario))
	_fresh_states()


## Scenario id given as `--scenario=<id>` among user arguments (lower-cased), or &"".
static func scenario_from_args(args: PackedStringArray) -> StringName:
	for a in args:
		if a.begins_with("--scenario="):
			return StringName(a.substr(11).to_lower())
	return &""


## Switches the active scenario: new timeline (IDLE at 0, playback speed kept) and a fresh
## world, then scenario_changed + world_rebuilt + playback_changed. Selecting the active
## scenario again changes nothing. Returns false (and changes nothing) for an unknown id.
func set_scenario(id: StringName) -> bool:
	if not Scenario.is_valid(id):
		push_warning("Simulation: unknown scenario %s" % id)
		return false
	if id == scenario and timeline != null:
		return true
	var speed := timeline.speed if timeline != null else 1.0
	scenario = id
	timeline = EventTimeline.new(Scenario.build_events(id))
	timeline.speed = speed
	_fresh_states()
	scenario_changed.emit(id)
	world_rebuilt.emit()
	playback_changed.emit(timeline.status)
	return true


func _process(delta: float) -> void:
	var before := timeline.status
	var emitted := timeline.advance(delta)
	var active := state
	for e in emitted:
		active.apply(e)
		event_emitted.emit(e)
	if timeline.status != before:
		playback_changed.emit(timeline.status)


## Simulation time in seconds (the playhead).
var time: float:
	get:
		return timeline.playhead


var status: EventTimeline.Status:
	get:
		return timeline.status


func start() -> void:
	var was := timeline.status
	if was == EventTimeline.Status.COMPLETE:
		reset()
	timeline.start()
	playback_changed.emit(timeline.status)


func pause() -> void:
	timeline.pause()
	playback_changed.emit(timeline.status)


func toggle() -> void:
	if timeline.status == EventTimeline.Status.PLAYING:
		pause()
	else:
		start()


func reset() -> void:
	timeline.reset()
	_fresh_states()
	world_rebuilt.emit()
	playback_changed.emit(timeline.status)


func seek(t: float) -> void:
	_fresh_states()
	var events := timeline.seek(t)
	if scenario == Scenario.GENESIS:
		genesis = GenesisState.derive(events)
	else:
		world = WorldState.derive(events)
	world_rebuilt.emit()
	playback_changed.emit(timeline.status)


func set_speed(s: float) -> void:
	timeline.speed = clampf(s, 0.25, 8.0)


func emitted_events() -> Array[SimEvent]:
	return timeline.emitted()


func duration() -> float:
	return timeline.duration


## Both scenario states back to "nothing happened".
func _fresh_states() -> void:
	world = WorldState.new()
	genesis = GenesisState.new()
