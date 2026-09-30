class_name UiMissionVerse
extends VBoxContainer
## GENESIS mission (OBSERVATORY): a minimal poem instead of a checklist. The mission's name (the part
## of Mission.title_for after the dash) in spaced capitals, then one line per objective of
## Mission.evaluate: the objective under way in full ink with an open ring, the fulfilled ones soft
## with a small filled dot, the ones still to come faint with a tiny dot. No counts, no percentages.
## Rebuilt on event_emitted / world_rebuilt / scenario_changed. Never catches the mouse.

var title_label: Label
var lines_box: VBoxContainer
## Per objective row: [HBoxContainer, sign Control, Label].
var _rows: Array = []
## State per row: 0 to come, 1 under way, 2 fulfilled.
var _states: PackedInt32Array = []


func _init() -> void:
	name = "MissionVerse"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 10)
	title_label = UiKit.label("", &"WordSoft")
	title_label.name = "Title"
	add_child(title_label)
	lines_box = UiKit.vbox(5)
	lines_box.name = "Objectives"
	add_child(lines_box)


func _ready() -> void:
	Simulation.event_emitted.connect(func(_e: SimEvent) -> void: refresh())
	Simulation.world_rebuilt.connect(refresh)
	Simulation.scenario_changed.connect(func(_s: StringName) -> void: rebuild())
	rebuild()


## The mission's poetic name: the title after its dash ("GENESIS — A WORLD IS BORN" -> "A WORLD IS BORN").
static func verse_title(title: String) -> String:
	var parts := title.split("—", false, 1)
	return parts[parts.size() - 1].strip_edges()


## 0 to come, 1 under way (the first objective not fulfilled), 2 fulfilled, per objective.
static func states_of(objectives: Array[Dictionary]) -> PackedInt32Array:
	var out := PackedInt32Array()
	var current_given := false
	for o in objectives:
		if o["done"]:
			out.append(2)
		elif not current_given:
			out.append(1)
			current_given = true
		else:
			out.append(0)
	return out


func rebuild() -> void:
	for c in lines_box.get_children():
		lines_box.remove_child(c)
		c.free()
	_rows.clear()
	title_label.text = verse_title(Mission.title_for(Simulation.scenario))
	for o in Mission.objectives_for(Simulation.scenario):
		var h := UiKit.hbox(10)
		h.name = String(o["id"])
		var sign := Control.new()
		sign.custom_minimum_size = Vector2(10, 10)
		sign.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var index := _rows.size()
		sign.draw.connect(_draw_sign.bind(sign, index))
		h.add_child(sign)
		var l := UiKit.label(String(o["title"]), &"Verse")
		h.add_child(l)
		lines_box.add_child(h)
		_rows.append([h, sign, l])
	_states = PackedInt32Array()
	refresh()


func refresh() -> void:
	var objectives := Mission.evaluate(Simulation.emitted_events(), Simulation.scenario)
	var states := states_of(objectives)
	if states == _states:
		return
	_states = states
	for i in mini(states.size(), _rows.size()):
		var l: Label = _rows[i][2]
		var col: Color = [Palette.UI_INK_FAINT, Palette.UI_INK, Palette.UI_INK_SOFT][states[i]]
		l.add_theme_color_override("font_color", col)
		(_rows[i][1] as Control).queue_redraw()


## Number of objectives fulfilled (tests).
func done_count() -> int:
	return _states.count(2)


func _draw_sign(sign: Control, i: int) -> void:
	if i >= _states.size():
		return
	var c := sign.size * 0.5
	match _states[i]:
		2:
			sign.draw_circle(c, 2.2, Palette.UI_INK_SOFT, true, -1.0, true)
		1:
			sign.draw_arc(c, 3.6, 0.0, TAU, 20, Palette.UI_INK, 1.0, true)
		_:
			sign.draw_circle(c, 1.2, Palette.UI_INK_FAINT, true, -1.0, true)
