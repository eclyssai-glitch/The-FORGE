class_name EventFeed
extends PanelContainer
## The last few simulation events (time in mono + short label), newest at the bottom, older rows
## fading. Appends on Simulation.event_emitted and rebuilds on Simulation.world_rebuilt.

const MAX_ROWS := 5
## Row opacity from newest to oldest.
const FADE: Array[float] = [1.0, 0.72, 0.52, 0.38, 0.28]

var rows_box: VBoxContainer
var count_label: Label
var idle_label: Label


func _init() -> void:
	name = "EventFeed"
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiKit.vbox(6)
	add_child(v)
	var head := UiKit.header("EVENTS")
	v.add_child(head[0])
	count_label = head[1]
	rows_box = UiKit.vbox(3)
	rows_box.name = "Rows"
	v.add_child(rows_box)
	idle_label = UiKit.label("SPACE  START", &"DataDim")
	idle_label.name = "Idle"
	v.add_child(idle_label)


func _ready() -> void:
	Simulation.event_emitted.connect(_on_event)
	Simulation.world_rebuilt.connect(rebuild)
	rebuild()


func rebuild() -> void:
	for c in rows_box.get_children():
		rows_box.remove_child(c)
		c.free()
	var events := Simulation.emitted_events()
	for e in events.slice(maxi(events.size() - MAX_ROWS, 0)):
		rows_box.add_child(_row(e))
	_restyle(events.size())


## Labels currently shown (oldest first): used by tests.
func shown_labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for r in rows_box.get_children():
		out.append((r.get_child(1) as Label).text)
	return out


func _on_event(e: SimEvent) -> void:
	rows_box.add_child(_row(e))
	while rows_box.get_child_count() > MAX_ROWS:
		var old := rows_box.get_child(0)
		rows_box.remove_child(old)
		old.free()
	_restyle(Simulation.emitted_events().size())


func _restyle(total: int) -> void:
	var n := rows_box.get_child_count()
	for i in n:
		(rows_box.get_child(i) as CanvasItem).modulate.a = FADE[mini(n - 1 - i, FADE.size() - 1)]
	count_label.text = "%02d / %02d" % [total, Simulation.timeline.events.size()]
	idle_label.visible = n == 0
	rows_box.visible = n > 0


static func _row(e: SimEvent) -> HBoxContainer:
	var h := UiKit.hbox(10)
	h.name = String(e.id)
	h.add_child(UiKit.label(e.format_time(), &"DataDim"))
	var l := UiKit.label(e.label, &"RowText")
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h
