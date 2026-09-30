class_name TimelineBar
extends Control
## Draggable demo timeline: a hairline track, the elapsed part in BONE, a tick at every phase
## change of the scripted events (derived by replaying them through WorldState), and the playhead.
## Press/drag seeks (`Simulation.seek`), at most once per frame. Keyboard focus is never taken.

const TRACK_H := 2.0
const TICK_H := 9.0
const HEAD_W := 2.0
const HEAD_H := 14.0

## [{"time": float, "phase": String}] — phase-change points of the scripted timeline.
var marks: Array[Dictionary] = []
var duration := 1.0

var _dragging := false
var _pending := -1.0
var _hover_x := -1.0
var _drawn_time := -1.0


func _init() -> void:
	name = "Timeline"
	UiKit.catch_mouse(self)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(160, 24)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	rebuild_marks()
	mouse_exited.connect(_on_mouse_exited)
	Simulation.scenario_changed.connect(func(_id: StringName) -> void: rebuild_marks())


## Duration and phase marks of the active scenario's timeline.
func rebuild_marks() -> void:
	duration = maxf(Simulation.duration(), 0.001)
	marks = phase_marks(Simulation.timeline.events, Simulation.scenario)
	queue_redraw()


## Phase-change points of `events` (sorted by time): replays them through a fresh state of
## `scenario` and records each time the phase changes. Pure: used by the bar and by tests.
static func phase_marks(events: Array[SimEvent], scenario: StringName = Scenario.ORIGIN_CHAMBER) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := Scenario.new_state(scenario)
	var last := w.phase_index()
	for e in events:
		w.apply(e)
		if w.phase_index() != last:
			out.append({"time": e.time, "phase": w.phase_name()})
			last = w.phase_index()
	return out


## Simulation time under local x (clamped to the track).
func time_at(x: float) -> float:
	var w := maxf(size.x, 1.0)
	return clampf(x / w, 0.0, 1.0) * duration


func x_at(t: float) -> float:
	return clampf(t / duration, 0.0, 1.0) * size.x


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			_pending = time_at(mb.position.x)
			set_process(true)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm:
		_hover_x = mm.position.x
		if _dragging:
			_pending = time_at(mm.position.x)
			set_process(true)
		queue_redraw()
		accept_event()


func _on_mouse_exited() -> void:
	_hover_x = -1.0
	queue_redraw()


func _process(_delta: float) -> void:
	if _pending >= 0.0:
		Simulation.seek(_pending)
		_pending = -1.0
	# Redraw only when the playhead moved at least ~half a pixel (cheap, but not every frame).
	var t := Simulation.time
	if absf(t - _drawn_time) * size.x / duration >= 0.5:
		queue_redraw()


func _draw() -> void:
	var t := Simulation.time
	_drawn_time = t
	var mid := floorf(size.y * 0.5)
	var head := x_at(t)
	draw_rect(Rect2(0, mid - TRACK_H * 0.5, size.x, TRACK_H), Palette.PANEL_LINE)
	draw_rect(Rect2(0, mid - TRACK_H * 0.5, head, TRACK_H), Palette.TEXT_DIM)
	for m in marks:
		var mx := floorf(x_at(float(m["time"])))
		var passed := float(m["time"]) <= t
		draw_rect(Rect2(mx, mid - TICK_H * 0.5, 1.0, TICK_H), Palette.BONE if passed else Palette.SLATE)
	if _hover_x >= 0.0 and not _dragging:
		draw_rect(Rect2(floorf(_hover_x), mid - TICK_H * 0.5, 1.0, TICK_H), Palette.LINE_STRONG)
	draw_rect(Rect2(floorf(head - HEAD_W * 0.5), mid - HEAD_H * 0.5, HEAD_W, HEAD_H), Palette.BONE)
