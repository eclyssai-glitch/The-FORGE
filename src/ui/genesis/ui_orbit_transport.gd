class_name UiOrbitTransport
extends Control
## GENESIS transport (group "ui_transport"; Start / Pause / Reset node names are the smoke contract).
##
## Collapsed, it is only a thin orbit arc across the lower centre with a dot for every scripted event
## and the playhead: the scene stays the hero. It reveals itself (sine, Palette.T_REVEAL) while the
## pointer is near the bottom edge (Palette.UI_REVEAL_ZONE px), while the demo is not playing (idle,
## paused, complete) and while the arc is dragged; it conceals itself (Palette.T_CONCEAL) a moment
## (T_REVEAL_LINGER) after none of that holds. Revealed: play/pause + reset glyphs at the left end of
## the arc; phase, clock and speed words at the right end; a soft night shade under the edge;
## hovering the arc names the nearest event. Press/drag on the arc seeks (Simulation.seek), at most
## once per frame. Nothing here takes keyboard focus. The strip itself never catches the mouse: only
## the arc and the (revealed) controls do, so picking stays free above them.

const GROUP := &"ui_transport"
const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]
## Distance (px) from the bottom edge of the strip to the ends of the arc.
const ARC_BOTTOM := 34.0
## Half height (px) of the arc's hit area around the curve.
const HIT_HALF := 12.0
const SEGMENTS := 96
## Gap (px) between the arc ends and the clusters.
const END_GAP := 18.0
## Pointer distance (px) to a mark that names it on hover.
const MARK_PICK := 10.0

var start_button: UiGlyphButton
var pause_button: UiGlyphButton
var reset_button: UiGlyphButton
var time_label: Label
var phase_label: Label
var speed_buttons: Array[Button] = []
## Hit area of the arc (press/drag seeks).
var track: Control
var left_cluster: HBoxContainer
var right_cluster: VBoxContainer
## 0 collapsed .. 1 revealed (animated).
var reveal := 0.0
## [{"time": float, "label": String}] — every scripted event of the active scenario.
var marks: Array[Dictionary] = []
var duration := 1.0

var _speed_group := ButtonGroup.new()
var _pointer_near := false
var _revealed := false
var _linger := 0.0
var _reveal_tween: Tween
var _dragging := false
var _pending := -1.0
var _hover_x := -1.0
var _drawn_time := -1.0
var _refresh_left := 0.0


func _init() -> void:
	name = "GenesisTransport"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)

	track = Control.new()
	track.name = "Arc"
	UiKit.catch_mouse(track)
	track.focus_mode = Control.FOCUS_NONE
	track.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	track.gui_input.connect(_on_track_input)
	track.mouse_exited.connect(_on_track_exited)
	add_child(track)

	left_cluster = UiKit.hbox(2)
	left_cluster.name = "Controls"
	add_child(left_cluster)
	reset_button = UiGlyphButton.new(&"reset", "Reset", 5.0)
	reset_button.pressed.connect(Simulation.reset)
	left_cluster.add_child(reset_button)
	start_button = UiGlyphButton.new(&"play", "Start", 5.5)
	start_button.pressed.connect(Simulation.start)
	left_cluster.add_child(start_button)
	pause_button = UiGlyphButton.new(&"pause", "Pause", 5.5)
	pause_button.pressed.connect(Simulation.pause)
	left_cluster.add_child(pause_button)

	right_cluster = UiKit.vbox(0)
	right_cluster.name = "Reading"
	add_child(right_cluster)
	phase_label = UiKit.label("", &"WordSoft")
	phase_label.name = "Phase"
	right_cluster.add_child(phase_label)
	var row := UiKit.hbox(10)
	right_cluster.add_child(row)
	time_label = UiKit.label("", &"Clock")
	time_label.name = "Time"
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(time_label)
	var speeds := UiKit.hbox(0)
	speeds.name = "Speed"
	row.add_child(speeds)
	for s in SPEEDS:
		var b := UiKit.button(speed_text(s), &"WordButton", true)
		b.name = "Speed_%s" % str(s).replace(".", "_")
		b.button_group = _speed_group
		b.pressed.connect(_on_speed.bind(s))
		speeds.add_child(b)
		speed_buttons.append(b)


func _ready() -> void:
	Simulation.playback_changed.connect(_on_playback_changed)
	Simulation.world_rebuilt.connect(refresh)
	Simulation.scenario_changed.connect(_on_scenario_changed)
	resized.connect(_layout)
	left_cluster.resized.connect(_layout)
	right_cluster.resized.connect(_layout)
	rebuild_marks()
	_set_reveal(1.0 if wants_reveal() else 0.0)
	_revealed = wants_reveal()
	_layout()
	refresh()


static func speed_text(s: float) -> String:
	return "½×" if is_equal_approx(s, 0.5) else ("%d×" % int(s))


## "0:27 / 0:56"
static func clock_text(t: float, total: float) -> String:
	var a := int(floorf(maxf(t, 0.0)))
	var b := int(ceilf(maxf(total, 0.0)))
	return "%d:%02d / %d:%02d" % [floori(a / 60.0), a % 60, floori(b / 60.0), b % 60]


## Marks of `events`: one per scripted event, in time order.
static func event_marks(events: Array[SimEvent]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		out.append({"time": e.time, "label": e.label})
	return out


func rebuild_marks() -> void:
	duration = maxf(Simulation.duration(), 0.001)
	marks = event_marks(Simulation.timeline.events)
	queue_redraw()


## True while the transport should be revealed (pointer near the edge, not playing, dragging).
func wants_reveal() -> bool:
	return _pointer_near or _dragging or Simulation.status != EventTimeline.Status.PLAYING


func is_revealed() -> bool:
	return _revealed


# ------------------------------------------------------------------ geometry

## Left end, right end (x) and the y of both ends, in local px.
func arc_ends() -> Vector3:
	var half := size.x * Palette.UI_ARC_SHARE * 0.5
	return Vector3(size.x * 0.5 - half, size.x * 0.5 + half, size.y - ARC_BOTTOM)


## Point of the arc at u (0..1): a shallow orbit segment bowing upwards.
func arc_point(u: float) -> Vector2:
	var e := arc_ends()
	var x := lerpf(e.x, e.y, u)
	return Vector2(x, e.z - Palette.UI_ARC_SAG * 4.0 * u * (1.0 - u))


## Simulation time under local x (clamped to the arc).
func time_at(x: float) -> float:
	var e := arc_ends()
	return clampf((x - e.x) / maxf(e.y - e.x, 1.0), 0.0, 1.0) * duration


func _layout() -> void:
	var e := arc_ends()
	track.position = Vector2(e.x - 8.0, e.z - Palette.UI_ARC_SAG - HIT_HALF)
	track.size = Vector2(e.y - e.x + 16.0, Palette.UI_ARC_SAG + HIT_HALF * 2.0)
	var ls := left_cluster.get_combined_minimum_size()
	left_cluster.size = ls
	left_cluster.position = Vector2(e.x - END_GAP - ls.x, e.z - ls.y * 0.5).round()
	var rs := right_cluster.get_combined_minimum_size()
	right_cluster.size = rs
	right_cluster.position = Vector2(e.y + END_GAP, e.z - rs.y * 0.5 - 2.0).round()
	queue_redraw()


# ------------------------------------------------------------------ reveal

func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	var vp := get_viewport_rect().size
	_pointer_near = mm.position.y >= vp.y - float(Palette.UI_REVEAL_ZONE) and mm.position.y <= vp.y \
		and mm.position.x >= 0.0 and mm.position.x <= vp.x


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointer_near = false


func _process(delta: float) -> void:
	if _pending >= 0.0:
		Simulation.seek(_pending)
		_pending = -1.0
	var want := wants_reveal()
	if want:
		_linger = Palette.T_REVEAL_LINGER
	else:
		_linger -= delta
	var target := want or _linger > 0.0
	if target != _revealed:
		_revealed = target
		_animate_reveal(target)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = Palette.T_UI_REFRESH
		refresh()
	var t := Simulation.time
	var e := arc_ends()
	if absf(t - _drawn_time) * (e.y - e.x) / duration >= 0.5:
		queue_redraw()


func _animate_reveal(on: bool) -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	if not is_inside_tree():
		_set_reveal(1.0 if on else 0.0)
		return
	_reveal_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_reveal_tween.tween_method(_set_reveal, reveal, 1.0 if on else 0.0, Palette.T_REVEAL if on else Palette.T_CONCEAL)


func _set_reveal(v: float) -> void:
	reveal = v
	var shown := v > 0.01
	for c: Control in [left_cluster, right_cluster]:
		c.modulate.a = v
		c.visible = shown
	queue_redraw()


# ------------------------------------------------------------------ state

func refresh() -> void:
	var text := clock_text(Simulation.time, Simulation.duration())
	if time_label.text != text:
		time_label.text = text
	var phase := Simulation.state.phase_name()
	if phase_label.text != phase:
		phase_label.text = phase
	var speed := Simulation.timeline.speed
	for i in SPEEDS.size():
		speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], speed))
	_on_playback_changed(Simulation.status)


func _on_playback_changed(status: EventTimeline.Status) -> void:
	var playing := status == EventTimeline.Status.PLAYING
	start_button.visible = not playing
	pause_button.visible = playing


func _on_scenario_changed(_id: StringName) -> void:
	rebuild_marks()
	refresh()


func _on_speed(s: float) -> void:
	UiKit.ui_sound(self, &"ui_tick")
	Simulation.set_speed(s)
	refresh()


# ------------------------------------------------------------------ seek

func _on_track_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			_pending = time_at(mb.position.x + track.position.x)
		track.accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm:
		_hover_x = mm.position.x + track.position.x
		if _dragging:
			_pending = time_at(_hover_x)
		queue_redraw()
		track.accept_event()


func _on_track_exited() -> void:
	_hover_x = -1.0
	queue_redraw()


## Index of the mark nearest to local x within MARK_PICK px, or -1.
func mark_near(x: float) -> int:
	var best := -1
	var best_d := MARK_PICK
	for i in marks.size():
		var d := absf(arc_point(float(marks[i]["time"]) / duration).x - x)
		if d <= best_d:
			best_d = d
			best = i
	return best


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var t := Simulation.time
	_drawn_time = t
	if reveal > 0.01:
		var shade := Palette.UI_SHADE
		shade.a *= reveal
		var clear := Palette.UI_SHADE
		clear.a = 0.0
		draw_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x, 0), Vector2(0, 0)]),
			PackedColorArray([shade, shade, clear, clear]))
	var track_col := Palette.UI_THREAD_FAINT.lerp(Palette.UI_THREAD, reveal)
	var done_col := Palette.UI_THREAD.lerp(Palette.UI_INK_SOFT, reveal)
	var u_now := clampf(t / duration, 0.0, 1.0)
	var all := PackedVector2Array()
	var done := PackedVector2Array()
	for i in SEGMENTS + 1:
		var u := float(i) / float(SEGMENTS)
		var p := arc_point(u)
		all.append(p)
		if u <= u_now:
			done.append(p)
	done.append(arc_point(u_now))
	draw_polyline(all, track_col, 1.0, true)
	if done.size() >= 2:
		draw_polyline(done, done_col, 1.0, true)
	var mr := lerpf(1.3, 2.0, reveal)
	for m in marks:
		var mt := float(m["time"])
		var col := done_col if mt <= t else track_col.lerp(Palette.UI_INK_FAINT, reveal)
		draw_circle(arc_point(mt / duration), mr, col, true, -1.0, true)
	var head := arc_point(u_now)
	var head_col := Palette.UI_INK_SOFT.lerp(Palette.UI_INK, reveal)
	draw_arc(head, lerpf(2.6, 4.2, reveal), 0.0, TAU, 20, head_col, 1.0, true)
	draw_circle(head, 1.2, head_col, true, -1.0, true)
	if _hover_x >= 0.0 and reveal > 0.3 and not _dragging:
		var i := mark_near(_hover_x)
		if i >= 0:
			var p := arc_point(float(marks[i]["time"]) / duration)
			var font := get_theme_font(&"font", &"WordSoft")
			var fs := get_theme_font_size(&"font_size", &"WordSoft")
			var text := String(marks[i]["label"])
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var col := Palette.UI_INK_SOFT
			col.a *= reveal
			draw_line(p + Vector2(0, -4), p + Vector2(0, -14), Palette.UI_THREAD, 1.0, true)
			draw_string_outline(font, p + Vector2(-w * 0.5, -20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Palette.UI_SHADE)
			draw_string(font, p + Vector2(-w * 0.5, -20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
