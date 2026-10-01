class_name UiWhisper
extends Control
## "Whispers" of the GENESIS events: when an event is emitted its poetic label rises in thin, widely
## spaced capitals just above the lower edge, rests and dissolves (Palette.T_WHISPER_IN / _HOLD /
## _OUT, sine). No feed, no list, no timestamps: one line at a time. A newer event hands off
## sequentially: whatever is showing dissolves first (Palette.T_WHISPER_HANDOFF from full ink,
## shorter when it is already fading) and only then does the new line rise — two words are never
## drawn over each other. Seek/reset (world_rebuilt) dissolves whatever is showing: the past is
## never replayed as text. Never catches the mouse.

## Height (px) of the whisper line box; the owner places the control.
const LINE_HEIGHT := 28.0

var lines: Array[Label] = []
var _current := 0
var _tweens: Array = [null, null]
## Text each line shows or is about to show (a line waiting for the hand-off keeps its old text on
## screen until it is dark).
var _texts: Array[String] = ["", ""]


func _init() -> void:
	name = "Whisper"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var l := UiKit.label("", &"Whisper")
		l.name = "Line%d" % i
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.modulate.a = 0.0
		add_child(l)
		lines.append(l)


func _ready() -> void:
	Simulation.event_emitted.connect(_on_event)
	Simulation.world_rebuilt.connect(dissolve)


## Text of the line currently rising, resting or waiting to rise ("" when silent).
func current_text() -> String:
	var l := lines[_current]
	return _texts[_current] if l.modulate.a > 0.0 or _is_running(_current) else ""


## Whispers `text`: whatever is showing dissolves first, then this line rises.
func whisper(text: String) -> void:
	if text.strip_edges() == "":
		return
	# The new line takes the dimmer of the two; both dissolve before it rises.
	var next := 0 if lines[0].modulate.a <= lines[1].modulate.a else 1
	var other := 1 - next
	var other_out := lines[other].modulate.a * Palette.T_WHISPER_HANDOFF
	var next_out := lines[next].modulate.a * Palette.T_WHISPER_HANDOFF
	_fade_out(other, other_out)
	_current = next
	_texts[next] = text
	_kill(next)
	var l := lines[next]
	if not is_inside_tree():
		l.text = text
		l.modulate.a = 1.0
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if next_out > 0.0:
		tw.tween_property(l, "modulate:a", 0.0, next_out)
	tw.tween_callback(func() -> void: l.text = text)
	var wait := maxf(other_out - next_out, 0.0)
	if wait > 0.0:
		tw.tween_interval(wait)
	tw.tween_property(l, "modulate:a", 1.0, Palette.T_WHISPER_IN)
	tw.tween_interval(Palette.T_WHISPER_HOLD)
	tw.tween_property(l, "modulate:a", 0.0, Palette.T_WHISPER_OUT)
	_tweens[next] = tw


## Both lines dissolve quickly (seek, reset, scenario change).
func dissolve() -> void:
	for i in 2:
		_fade_out(i, Palette.T_FAST * 2.0)


func _fade_out(i: int, duration: float) -> void:
	_kill(i)
	var l := lines[i]
	if l.modulate.a <= 0.0 or duration <= 0.0 or not is_inside_tree():
		l.modulate.a = 0.0
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(l, "modulate:a", 0.0, duration)
	_tweens[i] = tw


func _kill(i: int) -> void:
	if _is_running(i):
		(_tweens[i] as Tween).kill()
	_tweens[i] = null


func _is_running(i: int) -> bool:
	var tw: Variant = _tweens[i]
	return tw is Tween and (tw as Tween).is_valid() and (tw as Tween).is_running()


func _on_event(e: SimEvent) -> void:
	if is_visible_in_tree():
		whisper(e.label)
