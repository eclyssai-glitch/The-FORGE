class_name UiHairlineSlider
extends Range
## A 0..1 slider drawn as a pearl hairline with a small ring (GENESIS settings: volumes). Press/drag
## sets the value; never takes keyboard focus (Space/H/1-3 keep reaching the global shortcuts);
## keeps the mouse wheel. A soft UI tick on release (user interaction only).

var _dragging := false
var _hover := false


func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.01
	focus_mode = Control.FOCUS_NONE
	UiKit.catch_mouse(self)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(120, 18)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_changed.connect(func(_v: float) -> void: queue_redraw())
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


## Value under local x.
func value_at(x: float) -> float:
	var inset := 4.0
	return clampf((x - inset) / maxf(size.x - inset * 2.0, 1.0), 0.0, 1.0) * (max_value - min_value) + min_value


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			value = value_at(mb.position.x)
		elif _dragging:
			_dragging = false
			UiKit.ui_sound(self, &"ui_tick")
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		value = value_at(mm.position.x)
		accept_event()


func _draw() -> void:
	var inset := 4.0
	var y := floorf(size.y * 0.5) + 0.5
	var u := (value - min_value) / maxf(max_value - min_value, 1e-6)
	var x := inset + u * (size.x - inset * 2.0)
	draw_line(Vector2(inset, y), Vector2(size.x - inset, y), Palette.UI_THREAD, 1.0, true)
	draw_line(Vector2(inset, y), Vector2(x, y), Palette.UI_INK_SOFT, 1.0, true)
	var ink := Palette.UI_INK if (_hover or _dragging) else Palette.UI_INK_SOFT
	draw_arc(Vector2(x, y), 3.5, 0.0, TAU, 16, ink, 1.0, true)
