class_name ListRow
extends PanelContainer
## One clickable row of a HUD list: name on the left, status (mono, dim) on the right.
## Hover and selection are BONE washes with a hairline marker at the left edge (never EMBER/PALE).
## Emits `pressed` on a left click; the owner decides what it means (Session.select / focus).

signal pressed

var id: StringName
var name_label: Label
var status_label: Label

var _hover := false
var _selected := false


func _init(p_id: StringName = &"", title: String = "") -> void:
	id = p_id
	name = "Row_" + String(p_id)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	var h := UiKit.hbox(10)
	add_child(h)
	name_label = UiKit.label(title, &"RowText")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name_label)
	status_label = UiKit.label("", &"DataDim")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(status_label)
	mouse_entered.connect(func() -> void: _hover = true; _restyle())
	mouse_exited.connect(func() -> void: _hover = false; _restyle())
	_restyle()


func set_status(text: String) -> void:
	if status_label.text != text:
		status_label.text = text


func set_selected(on: bool) -> void:
	if on == _selected:
		return
	_selected = on
	_restyle()


func is_selected() -> bool:
	return _selected


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		accept_event()
		pressed.emit()


func _restyle() -> void:
	var state := &"selected" if _selected else (&"hover" if _hover else &"normal")
	add_theme_stylebox_override("panel", UiTheme.row_style(state))
	status_label.theme_type_variation = &"Data" if _selected else &"DataDim"
	status_label.add_theme_font_size_override("font_size", Palette.SIZE_SMALL)
