class_name EntityList
extends VBoxContainer
## A list of ListRows for catalog entities: status from EntityCatalog.status(id, Simulation.world),
## selection marker from Session.selected. Clicking a row selects it (and, with `focus_on_click`,
## asks the camera to frame it). Refreshes on events and on world_rebuilt only.

var rows: Dictionary = {}
var focus_on_click := false


func _init(ids: Array[StringName] = [], titles: Dictionary = {}, p_focus_on_click := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 1)
	focus_on_click = p_focus_on_click
	for id in ids:
		var title := String(titles.get(id, EntityCatalog.info(id).get("title", String(id))))
		var r := ListRow.new(id, title)
		r.pressed.connect(_on_row_pressed.bind(id))
		add_child(r)
		rows[id] = r


func _ready() -> void:
	Session.selection_changed.connect(_on_selection_changed)
	Simulation.event_emitted.connect(_on_event)
	Simulation.world_rebuilt.connect(refresh)
	refresh()


func refresh() -> void:
	for id: StringName in rows:
		var r: ListRow = rows[id]
		r.set_status(EntityCatalog.status(id, Simulation.world))
		r.set_selected(id == Session.selected)


func row(id: StringName) -> ListRow:
	return rows.get(id)


func _on_row_pressed(id: StringName) -> void:
	Session.select(id)
	if focus_on_click:
		Session.focus(id)


func _on_selection_changed(_id: StringName) -> void:
	refresh()


func _on_event(_e: SimEvent) -> void:
	refresh()
