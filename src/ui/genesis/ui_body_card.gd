class_name UiBodyCard
extends PanelContainer
## GENESIS inspector: a small floating card beside the selected body (Session.selected): its sign and
## symbolic kind, the name, the derived status (Scenario.entity_status over Simulation.state), one
## sentence, and two quiet actions — FOCUS (Session.focus) and close (Session.select(&"")).
## Placement follows the body on screen (UiSpaceLabels.screen_anchor): beside its edge, on the side
## with room, eased towards the target so a drifting camera never makes it jitter; without a body on
## screen it rests at the right, a little above the middle. Visibility is driven by the owner through
## `visibility_wanted` (so mode fades and H stay consistent). Night veil + one pearl hairline.

signal visibility_wanted(on: bool)

const WIDTH := 252.0
## Gap (px) between the body's edge and the card.
const BODY_GAP := 64.0
## Easing rate (1/s) of the card towards its target position.
const FOLLOW := 5.0
## Screen band kept free at the top (mode words) and at the bottom (transport reveal zone).
const TOP_BAND := 72.0

var kind_label: Label
var title_label: Label
var status_label: Label
var summary_label: Label
var glyph: Control
var focus_button: Button
var close_button: UiGlyphButton
var labels: UiSpaceLabels

var _id: StringName = &""
var _placed := false


func _init() -> void:
	name = "BodyCard"
	theme_type_variation = &"Card"
	UiKit.catch_mouse(self)
	custom_minimum_size = Vector2(WIDTH, 0)
	var v := UiKit.vbox(6)
	add_child(v)
	var head := UiKit.hbox(8)
	v.add_child(head)
	glyph = Control.new()
	glyph.name = "Sign"
	glyph.custom_minimum_size = Vector2(12, 12)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.draw.connect(_draw_sign)
	head.add_child(glyph)
	kind_label = UiKit.label("", &"WordFaint")
	kind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kind_label)
	close_button = UiGlyphButton.new(&"close", "Clear", 4.0)
	close_button.custom_minimum_size = Vector2(20, 20)
	close_button.pressed.connect(Session.select.bind(&""))
	head.add_child(close_button)
	title_label = UiKit.label("", &"CardTitle", true)
	title_label.name = "Title"
	v.add_child(title_label)
	status_label = UiKit.label("", &"Clock")
	status_label.name = "Status"
	v.add_child(status_label)
	summary_label = UiKit.label("", &"Verse", true)
	summary_label.name = "Summary"
	v.add_child(summary_label)
	var actions := UiKit.hbox(0)
	v.add_child(actions)
	focus_button = UiKit.button("FOCUS", &"WordButton")
	focus_button.name = "Focus"
	focus_button.pressed.connect(_on_focus)
	actions.add_child(focus_button)


func _ready() -> void:
	Session.selection_changed.connect(_on_selection_changed)
	Simulation.event_emitted.connect(func(_e: SimEvent) -> void: refresh())
	Simulation.world_rebuilt.connect(refresh)
	Simulation.scenario_changed.connect(func(_s: StringName) -> void: _on_selection_changed(Session.selected))
	_on_selection_changed(Session.selected)


func entity() -> StringName:
	return _id


## True when the selection names an entity of the active scenario.
func wants_visible() -> bool:
	return _id != &"" and not Scenario.entity_info(Simulation.scenario, _id).is_empty()


func refresh() -> void:
	if not wants_visible():
		return
	var info := Scenario.entity_info(Simulation.scenario, _id)
	kind_label.text = UiSpaceLabels.kind_word(info)
	title_label.text = String(info["title"])
	status_label.text = Scenario.entity_status(Simulation.scenario, _id, Simulation.state).to_lower()
	summary_label.text = String(info["summary"])
	glyph.queue_redraw()


func _draw_sign() -> void:
	if not wants_visible():
		return
	var info := Scenario.entity_info(Simulation.scenario, _id)
	UiGlyphs.draw(glyph, UiGlyphs.kind_glyph(String(info.get("kind_name", ""))), glyph.size * 0.5, 4.5, Palette.UI_INK_SOFT)


## Where the card wants to be (top-left, px) for a viewport of `vp` and an anchor {"pos", "r"} ({}
## when the body is not on screen).
func target_position(vp: Vector2, anchor: Dictionary) -> Vector2:
	var s := Vector2(WIDTH, maxf(size.y, get_combined_minimum_size().y))
	var edge := float(Palette.UI_EDGE)
	var p: Vector2
	if anchor.is_empty():
		p = Vector2(vp.x - edge - s.x, vp.y * 0.36 - s.y * 0.5)
	else:
		var c: Vector2 = anchor["pos"]
		var off := float(anchor["r"]) + BODY_GAP
		var right := c.x + off + s.x <= vp.x - edge or c.x < vp.x * 0.5
		p = Vector2(c.x + off if right else c.x - off - s.x, c.y - s.y * 0.5)
	p.x = clampf(p.x, edge, vp.x - edge - s.x)
	p.y = clampf(p.y, TOP_BAND, maxf(TOP_BAND, vp.y - float(Palette.UI_REVEAL_ZONE) - s.y))
	return p


func _process(delta: float) -> void:
	if not visible:
		_placed = false
		return
	var anchor := labels.screen_anchor(_id) if labels else {}
	var target := target_position(get_viewport_rect().size, anchor)
	if not _placed:
		position = target
		_placed = true
	else:
		position = position.lerp(target, 1.0 - exp(-FOLLOW * delta))
	size = Vector2(WIDTH, 0.0)


func _on_selection_changed(id: StringName) -> void:
	_id = id
	if labels:
		labels.card_id = id if wants_visible() else &""
	_placed = _placed and wants_visible()
	refresh()
	visibility_wanted.emit(wants_visible())


func _on_focus() -> void:
	if _id != &"":
		UiKit.ui_sound(self, &"ui_select")
		Session.focus(_id)
