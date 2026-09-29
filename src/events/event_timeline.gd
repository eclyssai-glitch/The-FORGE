class_name EventTimeline
extends RefCounted
## Deterministic playback of a scripted event list. Pure logic: no nodes, no clocks.
## The owner calls advance(delta) every frame; emitted events are returned in order.

enum Status { IDLE, PLAYING, PAUSED, COMPLETE }

var events: Array[SimEvent] = []
var duration: float = 0.0
var playhead: float = 0.0
## Number of events already emitted (events[0 .. cursor-1]).
var cursor: int = 0
var status: Status = Status.IDLE
var speed: float = 1.0:
	set(value):
		speed = maxf(value, 0.0)


func _init(p_events: Array[SimEvent]) -> void:
	events = p_events.duplicate()
	events.sort_custom(func(a: SimEvent, b: SimEvent) -> bool: return a.time < b.time)
	duration = events[-1].time if not events.is_empty() else 0.0


## Starts from the beginning when idle or complete; resumes when paused.
func start() -> void:
	match status:
		Status.PLAYING:
			return
		Status.PAUSED:
			status = Status.PLAYING
		_:
			_rewind()
			status = Status.PLAYING


func pause() -> void:
	if status == Status.PLAYING:
		status = Status.PAUSED


func resume() -> void:
	if status == Status.PAUSED:
		status = Status.PLAYING


func reset() -> void:
	_rewind()
	status = Status.IDLE


## Moves the playhead. Returns every event at or before `t`, so the caller can
## rebuild derived state from scratch. Playback status is kept (a COMPLETE
## timeline sought backwards becomes PAUSED).
func seek(t: float) -> Array[SimEvent]:
	playhead = clampf(t, 0.0, duration)
	cursor = 0
	while cursor < events.size() and events[cursor].time <= playhead:
		cursor += 1
	if playhead >= duration and cursor == events.size():
		status = Status.COMPLETE
	elif status == Status.COMPLETE or status == Status.IDLE:
		status = Status.PAUSED
	return emitted()


## Advances the playhead by `delta` seconds (scaled by speed) while playing.
func advance(delta: float) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	if status != Status.PLAYING:
		return out
	playhead = minf(playhead + maxf(delta, 0.0) * speed, duration)
	while cursor < events.size() and events[cursor].time <= playhead:
		out.append(events[cursor])
		cursor += 1
	if cursor == events.size() and playhead >= duration:
		status = Status.COMPLETE
	return out


func emitted() -> Array[SimEvent]:
	return events.slice(0, cursor)


func progress() -> float:
	return playhead / duration if duration > 0.0 else 0.0


func _rewind() -> void:
	playhead = 0.0
	cursor = 0
