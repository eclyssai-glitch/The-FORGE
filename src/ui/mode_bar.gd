class_name ModeBar
extends HBoxContainer
## UNIVERSE / FORGE / OBSERVATORY tabs, with the 1/2/3 shortcuts shown discreetly (mono, dim).
## Writes Session.set_mode; follows Session.mode_changed (keyboard or any other source).

var tabs: Array[Button] = []
var _group := ButtonGroup.new()


func _init() -> void:
	name = "ModeBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	for m in SessionState.MODE_NAMES.size():
		var key := UiKit.label(str(m + 1), &"DataDim")
		key.name = "Key%d" % (m + 1)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(key)
		var b := UiKit.button(SessionState.MODE_NAMES[m], &"ModeTab", true)
		b.name = SessionState.MODE_NAMES[m].capitalize()
		b.button_group = _group
		b.pressed.connect(Session.set_mode.bind(m as SessionState.Mode))
		add_child(b)
		tabs.append(b)
		if m < SessionState.MODE_NAMES.size() - 1:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(14, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(gap)


func _ready() -> void:
	Session.mode_changed.connect(_on_mode_changed)
	refresh()


func _on_mode_changed(_m: SessionState.Mode) -> void:
	refresh()


func refresh() -> void:
	for i in tabs.size():
		tabs[i].set_pressed_no_signal(i == Session.mode)
