extends Node
## Autoload "Simulation": owns the demo clock, the event timeline and the derived world.
## The only producer of simulation events. Everything else listens to its signals
## or reads `world` + `time` — nothing else mutates simulation state.

signal event_emitted(event: SimEvent)
## Emitted after seek/reset: listeners must rebuild from `world` and `log()`.
signal world_rebuilt
signal playback_changed(status: EventTimeline.Status)

## DEMO MODE is the only mode that exists in this version.
const DEMO_MODE := true

var timeline: EventTimeline
var world: WorldState


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	timeline = EventTimeline.new(OriginChamberScript.build())
	world = WorldState.new()


func _process(delta: float) -> void:
	var before := timeline.status
	var emitted := timeline.advance(delta)
	for e in emitted:
		world.apply(e)
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
	world = WorldState.new()
	world_rebuilt.emit()
	playback_changed.emit(timeline.status)


func seek(t: float) -> void:
	world = WorldState.derive(timeline.seek(t))
	world_rebuilt.emit()
	playback_changed.emit(timeline.status)


func set_speed(s: float) -> void:
	timeline.speed = clampf(s, 0.25, 8.0)


func emitted_events() -> Array[SimEvent]:
	return timeline.emitted()


func duration() -> float:
	return timeline.duration
