class_name Inspector
extends PanelContainer
## Details of Session.selected (hidden when nothing is selected): kind, title, derived status
## (EntityCatalog.status over Simulation.world), one-line summary, the emitted events that concern
## the entity, and FOCUS (Session.focus) / CLEAR (Session.select(&"")) actions.
## Visibility is driven by the HUD (wants_visible()) so mode fades and H stay consistent.

const MAX_EVENTS := 4

signal visibility_wanted(on: bool)

var kind_label: Label
var title_label: Label
var status_label: Label
var summary_label: Label
var events_box: VBoxContainer
var events_header: Label
var focus_button: Button
var clear_button: Button

var _id: StringName = &""


func _init() -> void:
	name = "Inspector"
	theme_type_variation = &"HudPanel"
	UiKit.catch_mouse(self)
	var v := UiKit.vbox(6)
	add_child(v)
	var head := UiKit.hbox()
	v.add_child(head)
	kind_label = UiKit.label("", &"Caption")
	kind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kind_label)
	clear_button = UiKit.button("×", &"Action")
	clear_button.name = "Clear"
	clear_button.add_theme_font_override("font", UiTheme.font_sans(400))
	clear_button.add_theme_font_size_override("font_size", Palette.SIZE_LABEL)
	clear_button.pressed.connect(Session.select.bind(&""))
	head.add_child(clear_button)
	title_label = UiKit.label("", &"Title", true)
	title_label.add_theme_font_size_override("font_size", Palette.SIZE_TITLE)
	v.add_child(title_label)
	var status_row := UiKit.hbox(10)
	v.add_child(status_row)
	status_row.add_child(UiKit.label("STATUS", &"Caption"))
	status_label = UiKit.label("", &"Data")
	status_label.name = "Status"
	status_row.add_child(status_label)
	summary_label = UiKit.label("", &"Body", true)
	v.add_child(summary_label)
	v.add_child(UiKit.separator())
	events_header = UiKit.label("EVENTS", &"Caption")
	v.add_child(events_header)
	events_box = UiKit.vbox(3)
	v.add_child(events_box)
	var actions := UiKit.hbox()
	actions.add_theme_constant_override("separation", 6)
	v.add_child(actions)
	focus_button = UiKit.button("FOCUS", &"TransportButton")
	focus_button.name = "Focus"
	focus_button.pressed.connect(_on_focus)
	actions.add_child(focus_button)


func _ready() -> void:
	Session.selection_changed.connect(_on_selection_changed)
	Simulation.event_emitted.connect(_on_event)
	Simulation.world_rebuilt.connect(refresh)
	_on_selection_changed(Session.selected)


func entity() -> StringName:
	return _id


## True when there is something to inspect.
func wants_visible() -> bool:
	return _id != &"" and not EntityCatalog.info(_id).is_empty()


func refresh() -> void:
	if not wants_visible():
		return
	var info := EntityCatalog.info(_id)
	kind_label.text = String(info["kind_name"])
	title_label.text = String(info["title"])
	status_label.text = EntityCatalog.status(_id, Simulation.world)
	summary_label.text = String(info["summary"])
	for c in events_box.get_children():
		events_box.remove_child(c)
		c.free()
	var related := related_events(_id, Simulation.emitted_events())
	for e in related.slice(maxi(related.size() - MAX_EVENTS, 0)):
		var h := UiKit.hbox(10)
		h.add_child(UiKit.label(e.format_time(), &"DataDim"))
		var l := UiKit.label(e.label, &"RowText")
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		events_box.add_child(h)
	if related.is_empty():
		events_box.add_child(UiKit.label("—", &"DataDim"))


## Emitted events that concern `id` (event.entity == id), in order.
static func related_events(id: StringName, emitted: Array[SimEvent]) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in emitted:
		if e.entity == id:
			out.append(e)
	return out


func _on_selection_changed(id: StringName) -> void:
	_id = id
	refresh()
	visibility_wanted.emit(wants_visible())


func _on_event(e: SimEvent) -> void:
	if wants_visible():
		# Status can change with any event (phase); the list only with related ones.
		if e.entity == _id:
			refresh()
		else:
			status_label.text = EntityCatalog.status(_id, Simulation.world)


func _on_focus() -> void:
	if _id != &"":
		Session.focus(_id)
