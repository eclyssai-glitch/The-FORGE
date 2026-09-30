class_name UiGlyphButton
extends Button
## A textless button that draws one UiGlyphs sign: soft pearl at rest, ink on hover/press. Never
## takes keyboard focus, keeps the mouse wheel (UiKit.button). Optional UI sound on press
## (`sound`, played through the audio director group; user interaction only).

var glyph: StringName
var radius := 5.0
var sound: StringName = &"ui_tick"


func _init(p_glyph: StringName = &"", p_name := "", p_radius := 5.0) -> void:
	glyph = p_glyph
	radius = p_radius
	if p_name != "":
		name = p_name
	theme_type_variation = &"GlyphButton"
	focus_mode = Control.FOCUS_NONE
	UiKit.catch_mouse(self)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(28, 28)
	pressed.connect(_on_pressed)


func set_glyph(g: StringName) -> void:
	if g != glyph:
		glyph = g
		queue_redraw()


func _draw() -> void:
	var col := Palette.UI_INK if (is_hovered() or button_pressed) else Palette.UI_INK_SOFT
	UiGlyphs.draw(self, glyph, (size * 0.5).floor() + Vector2(0.5, 0.5), radius, col)


func _on_pressed() -> void:
	UiKit.ui_sound(self, sound)
