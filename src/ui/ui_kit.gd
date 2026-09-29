class_name UiKit
extends RefCounted
## Small factories shared by the HUD components, so every control gets the same defaults:
## keyboard focus off (Space/R/1-3 always reach the global Shortcuts, a clicked button never keeps
## the keys), layout nodes never catch the mouse (orbit/picking stay free outside panels).


static func label(text: String, variation: StringName = &"", autowrap := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, variation: StringName = &"", toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func vbox(separation := -1) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if separation >= 0:
		v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := -1) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if separation >= 0:
		h.add_theme_constant_override("separation", separation)
	return h


static func separator() -> HSeparator:
	var s := HSeparator.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Expanding spacer inside a box container.
static func spacer() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Section header: caption on the left, optional dim data on the right. Returns [row, right label].
static func header(caption: String) -> Array:
	var row := hbox()
	row.add_child(label(caption, &"Caption"))
	row.add_child(spacer())
	var right := label("", &"DataDim")
	row.add_child(right)
	return [row, right]


## Panel that catches the mouse over its own rect only (clicks on it never reach the 3D picker).
static func panel(variation: StringName = &"HudPanel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## Fades `node` in/out (modulate alpha) over `duration`; hidden (no input) once faded out.
## Re-entrant: a running fade of the same node is replaced.
static func fade(node: CanvasItem, on: bool, duration: float) -> void:
	var old: Variant = node.get_meta(&"ui_fade") if node.has_meta(&"ui_fade") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	if not on and not node.visible:
		node.modulate.a = 0.0
		return
	if on and not node.visible:
		node.modulate.a = 0.0
		node.visible = true
	var target := 1.0 if on else 0.0
	if not node.is_inside_tree() or is_equal_approx(node.modulate.a, target):
		node.modulate.a = target
		node.visible = on
		return
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", target, duration)
	if not on:
		tw.tween_callback(node.hide)
	node.set_meta(&"ui_fade", tw)
