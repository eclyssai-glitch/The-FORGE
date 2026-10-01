class_name UiCallLine
extends Control
## LIVING call line (docs/VISUAL_DIRECTION.md section 12): the user calls MIKU by writing to her.
## Diegetic, never a chat box: at rest only a short pearl hairline in the lower centre; Enter (or a
## click on the hairline) draws it out into a thin line of pearl ink that takes the typed words
## ("miku, …"); Enter sends them — the words rise from the line and dissolve into the scene while
## the line retracts; Esc (or an empty Enter) lets it go. Above the line a short whisper answers with
## what was understood ("→ altura", "não posso agora"), then dissolves. Pearl ink only, sine fades.
##
## Contract with the interaction system (game-engineer; the logic is theirs, this node only shows):
##   group   "living_call_line"        (GROUP; exactly one while the LIVING HUD exists)
##   signal  submitted(text: String)   stripped, non-empty, <= MAX_CHARS
##   signal  opened / closed           the user started / stopped calling (MIKU may notice)
##   method  show_feedback(kind: StringName, text: String)   kinds: FEEDBACK_KINDS (unknown -> &"heard")
##           &"recognized" intent understood -> "→ <text>" in soft ink
##           &"applied"    a change took effect -> "<text>" in full ink
##           &"refused"    cannot / will not now (no provider, needs an asset) -> "<text>" in faint ink
##           &"heard"      heard, nothing to do (or still thinking) -> "<text>" in faint ink
##   method  submit(text) — sends `text` exactly as if typed (automation / recordings); open(), close(),
##           is_open(), feedback_text().
## Keyboard: only while open does the field hold the keyboard focus (so Shortcuts and the camera keys
## stay quiet while typing); closed, nothing here takes focus. Enter opens only while the HUD is
## visible (H hides the line with the rest).

signal submitted(text: String)
signal opened
signal closed

const GROUP := &"living_call_line"
const MAX_CHARS := 120
const PLACEHOLDER := "miku, …"
const FEEDBACK_KINDS: Array[StringName] = [&"recognized", &"applied", &"refused", &"heard"]
const RECOGNIZED_PREFIX := "→ "
## Height (px) of the strip; the line sits LINE_INSET px above its bottom edge.
const STRIP_HEIGHT := 96.0
const LINE_INSET := 12.0
const FIELD_HEIGHT := 30.0
## How far (px) the sent words rise while they dissolve.
const SENT_RISE := 18.0

var field: LineEdit
var echo: Label
var sent: Label
## Hit area of the resting hairline (a click opens the line).
var hint: Control
## 0 = resting hairline .. 1 = open line (animated).
var open_amount := 0.0

var _open := false
var _open_tween: Tween
var _echo_tween: Tween
var _sent_tween: Tween
var _echo_kind: StringName = &""


func _init() -> void:
	name = "CallLine"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)

	echo = UiKit.label("", &"CallEcho")
	echo.name = "Echo"
	echo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	echo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	echo.modulate.a = 0.0
	add_child(echo)

	sent = UiKit.label("", &"CallSent")
	sent.name = "Sent"
	sent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sent.modulate.a = 0.0
	add_child(sent)

	field = LineEdit.new()
	field.name = "Field"
	field.theme_type_variation = &"CallField"
	field.placeholder_text = PLACEHOLDER
	field.max_length = MAX_CHARS
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.context_menu_enabled = false
	field.virtual_keyboard_enabled = false
	field.middle_mouse_paste_enabled = false
	field.caret_blink = false
	field.focus_mode = Control.FOCUS_CLICK
	UiKit.catch_mouse(field)
	field.visible = false
	field.modulate.a = 0.0
	field.text_submitted.connect(submit)
	field.gui_input.connect(_on_field_input)
	add_child(field)

	hint = Control.new()
	hint.name = "Hint"
	UiKit.catch_mouse(hint)
	hint.focus_mode = Control.FOCUS_NONE
	hint.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	hint.tooltip_text = ""
	hint.gui_input.connect(_on_hint_input)
	add_child(hint)

	resized.connect(_layout)


func _ready() -> void:
	_layout()


## True while the line is open (taking words).
func is_open() -> bool:
	return _open


## Draws the line out and gives it the keyboard. No-op if already open.
func open() -> void:
	if _open:
		return
	_open = true
	field.text = ""
	field.visible = true
	hint.visible = false
	if field.is_inside_tree():
		field.grab_focus()
	_animate_open(true)
	opened.emit()


## Lets the line go (text discarded) and releases the keyboard. No-op if closed.
func close() -> void:
	if not _open:
		return
	_open = false
	if field.has_focus():
		field.release_focus()
	field.text = ""
	hint.visible = true
	_animate_open(false)
	closed.emit()


## Sends `text` as if typed: emits `submitted` with the stripped text (empty text only closes) and
## lets the words rise from the line. Works open or closed.
func submit(text: String) -> void:
	var t := text.strip_edges().left(MAX_CHARS)
	if _open:
		close()
	if t == "":
		return
	_rise(t)
	submitted.emit(t)


## Whispers what MIKU understood above the line (see the header for the kinds).
func show_feedback(kind: StringName, text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	var k: StringName = kind if FEEDBACK_KINDS.has(kind) else &"heard"
	if k == &"recognized" and not t.begins_with(RECOGNIZED_PREFIX.strip_edges()):
		t = RECOGNIZED_PREFIX + t
	_echo_kind = k
	echo.add_theme_color_override(&"font_color", feedback_ink(k))
	if _echo_tween and _echo_tween.is_valid():
		_echo_tween.kill()
	if not is_inside_tree():
		echo.text = t
		echo.modulate.a = 1.0
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if echo.modulate.a > 0.0:
		tw.tween_property(echo, "modulate:a", 0.0, Palette.T_WHISPER_HANDOFF * echo.modulate.a)
	tw.tween_callback(func() -> void: echo.text = t)
	tw.tween_property(echo, "modulate:a", 1.0, Palette.T_CALL_ECHO_IN)
	tw.tween_interval(Palette.T_CALL_ECHO_HOLD)
	tw.tween_property(echo, "modulate:a", 0.0, Palette.T_CALL_ECHO_OUT)
	_echo_tween = tw


## Text of the feedback whisper showing or about to show ("" when silent).
func feedback_text() -> String:
	if echo.modulate.a <= 0.0 and not (_echo_tween and _echo_tween.is_valid() and _echo_tween.is_running()):
		return ""
	return echo.text


## Kind of the last feedback (&"" before any).
func feedback_kind() -> StringName:
	return _echo_kind


## Ink of a feedback kind: understood and done read clearer than refused or merely heard.
static func feedback_ink(kind: StringName) -> Color:
	match kind:
		&"applied":
			return Palette.UI_INK
		&"recognized":
			return Palette.UI_INK_SOFT
	return Palette.UI_INK_FAINT


## Called when the LIVING HUD hides (H, scenario change): the line lets go, the whispers dissolve.
func on_hidden() -> void:
	close()
	if _echo_tween and _echo_tween.is_valid():
		_echo_tween.kill()
	echo.modulate.a = 0.0


## Width (px) of the drawn line for an open amount.
static func line_width(amount: float) -> float:
	return lerpf(Palette.UI_CALL_REST, Palette.UI_CALL_WIDTH, clampf(amount, 0.0, 1.0))


## Y (local px) of the line.
func line_y() -> float:
	return size.y - LINE_INSET


# ------------------------------------------------------------------ input

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _open or not is_visible_in_tree():
		return
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		open()
		get_viewport().set_input_as_handled()


func _on_field_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and k.keycode == KEY_ESCAPE:
		close()
		field.accept_event()


func _on_hint_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		hint.accept_event()
		open()


# ------------------------------------------------------------------ motion and drawing

func _animate_open(on: bool) -> void:
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	var target := 1.0 if on else 0.0
	if not is_inside_tree():
		_set_open_amount(target)
		field.visible = on
		return
	_open_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_open_tween.tween_method(_set_open_amount, open_amount, target, Palette.T_CALL_OPEN if on else Palette.T_CALL_CLOSE)
	if not on:
		_open_tween.tween_callback(func() -> void: field.visible = _open)


func _set_open_amount(v: float) -> void:
	open_amount = v
	field.modulate.a = v
	queue_redraw()


## The sent words leave the line: they rise a little and dissolve into the scene.
func _rise(text: String) -> void:
	if _sent_tween and _sent_tween.is_valid():
		_sent_tween.kill()
	sent.text = text
	var y0 := field.position.y
	sent.position.y = y0
	if not is_inside_tree():
		sent.modulate.a = 0.0
		return
	sent.modulate.a = 1.0
	_sent_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sent_tween.tween_property(sent, "position:y", y0 - SENT_RISE, Palette.T_CALL_CLOSE * 1.6)
	_sent_tween.tween_property(sent, "modulate:a", 0.0, Palette.T_CALL_CLOSE * 1.6).set_ease(Tween.EASE_IN_OUT)


func _layout() -> void:
	var w := Palette.UI_CALL_WIDTH
	var x := (size.x - w) * 0.5
	var ly := line_y()
	field.position = Vector2(x, ly - FIELD_HEIGHT - 2.0).round()
	field.size = Vector2(w, FIELD_HEIGHT)
	sent.position = field.position
	sent.size = field.size
	echo.position = Vector2(x, ly - FIELD_HEIGHT - Palette.UI_CALL_ECHO_GAP - 2.0).round()
	echo.size = Vector2(w, FIELD_HEIGHT)
	var hw := Palette.UI_CALL_REST + 24.0
	hint.position = Vector2((size.x - hw) * 0.5, ly - 10.0).round()
	hint.size = Vector2(hw, 18.0)
	queue_redraw()


func _draw() -> void:
	var w := line_width(open_amount)
	var cx := size.x * 0.5
	var y := line_y() + 0.5
	var ink := Palette.UI_THREAD_FAINT.lerp(Palette.UI_THREAD, open_amount)
	var clear := ink
	clear.a = 0.0
	# A thread, not a rule: it fades out at both ends.
	var pts := PackedVector2Array([Vector2(cx - w * 0.5, y), Vector2(cx - w * 0.3, y), Vector2(cx + w * 0.3, y), Vector2(cx + w * 0.5, y)])
	draw_polyline_colors(pts, PackedColorArray([clear, ink, ink, clear]), 1.0, true)
