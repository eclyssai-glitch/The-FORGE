class_name ObservatoryPanel
extends PanelContainer
## OBSERVATORY: the left sheet (~38% of the width; the world stays alive on the right).
## Mission (Mission.evaluate over the emitted events: objectives with a done mark, progress %),
## verification results (each check with its time), entity statuses, the complete event log
## (scrollable, follows the newest event) and the "SIMULATED DATA" footer. Everything is derived
## from Simulation: appended on event_emitted, rebuilt on world_rebuilt.

const DONE_MARK := "✓"
const PENDING_MARK := "·"
## Entities in the status grid, with short names. &"layers" aggregates the five rings
## (layers_status); each ring has its own row in the FORGE panel.
const STATUS_ROWS: Array = [
	[&"origin_core", "CORE"], [&"fragment_field", "FRAGMENTS"], [&"layers", "LAYERS"],
	[&"verification_array", "VERIFICATION"],
]

var progress_label: Label
var progress_bar: ColorRect
var progress_track: Control
var objectives_box: VBoxContainer
var checks_grid: GridContainer
var checks_header: Label
var status_grid: GridContainer
var log_scroll: ScrollContainer
var log_box: VBoxContainer
var log_count: Label

var _objective_rows: Array[HBoxContainer] = []
var _check_rows: Array = []
var _status_labels: Dictionary = {}
var _progress := 0.0


func _init() -> void:
	name = "ObservatoryPanel"
	theme_type_variation = &"Sheet"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiKit.vbox(0)
	add_child(v)

	# --- Mission ---
	var head := UiKit.header("MISSION")
	v.add_child(head[0])
	progress_label = head[1]
	progress_label.theme_type_variation = &"Data"
	v.add_child(_gap(4))
	var title := UiKit.label(Mission.ORIGIN_CHAMBER_TITLE, &"Title", true)
	title.add_theme_font_size_override("font_size", Palette.SIZE_TITLE)
	v.add_child(title)
	v.add_child(_gap(8))
	progress_track = Control.new()
	progress_track.custom_minimum_size = Vector2(0, 2)
	progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_bg := ColorRect.new()
	track_bg.color = Palette.PANEL_LINE
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_track.add_child(track_bg)
	progress_bar = ColorRect.new()
	progress_bar.color = Palette.BONE
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.anchor_bottom = 1.0
	progress_track.add_child(progress_bar)
	progress_track.resized.connect(_layout_progress)
	v.add_child(progress_track)
	v.add_child(_gap(10))
	objectives_box = UiKit.vbox(3)
	objectives_box.name = "Objectives"
	v.add_child(objectives_box)
	for o in Mission.ORIGIN_CHAMBER_OBJECTIVES:
		var h := UiKit.hbox(10)
		h.name = String(o["id"])
		var mark := UiKit.label(PENDING_MARK, &"Title")
		mark.custom_minimum_size = Vector2(12, 0)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(mark)
		var t := UiKit.label(String(o["title"]), &"Body")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(UiKit.label("", &"DataDim"))
		objectives_box.add_child(h)
		_objective_rows.append(h)
	v.add_child(UiKit.separator())

	# --- Results: verification checks + entity statuses, side by side ---
	var results := UiKit.hbox(28)
	results.name = "Results"
	v.add_child(results)
	var checks_col := UiKit.vbox(6)
	checks_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_child(checks_col)
	var ch := UiKit.header("VERIFICATION")
	checks_col.add_child(ch[0])
	checks_header = ch[1]
	checks_grid = GridContainer.new()
	checks_grid.name = "Checks"
	checks_grid.columns = 3
	checks_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	checks_col.add_child(checks_grid)
	for c: StringName in OriginChamberScript.CHECKS:
		var n := UiKit.label(String(c).to_upper(), &"RowText")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var at := UiKit.label("", &"DataDim")
		var st := UiKit.label("", &"DataDim")
		checks_grid.add_child(n)
		checks_grid.add_child(at)
		checks_grid.add_child(st)
		_check_rows.append([c, n, at, st])
	var status_col := UiKit.vbox(6)
	status_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_child(status_col)
	status_col.add_child(UiKit.header("ENTITIES")[0])
	status_grid = GridContainer.new()
	status_grid.name = "Statuses"
	status_grid.columns = 2
	status_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_col.add_child(status_grid)
	for r: Array in STATUS_ROWS:
		var n := UiKit.label(String(r[1]), &"RowText")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := UiKit.label("", &"DataDim")
		status_grid.add_child(n)
		status_grid.add_child(st)
		_status_labels[r[0]] = st
	v.add_child(UiKit.separator())

	# --- Complete event log ---
	var lh := UiKit.header("EVENT LOG")
	v.add_child(lh[0])
	log_count = lh[1]
	v.add_child(_gap(6))
	log_scroll = ScrollContainer.new()
	log_scroll.name = "Log"
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.custom_minimum_size = Vector2(0, 72)
	log_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	log_scroll.focus_mode = Control.FOCUS_NONE
	v.add_child(log_scroll)
	log_box = UiKit.vbox(6)
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_box)
	v.add_child(UiKit.separator())

	# --- Footer ---
	var foot := UiKit.hbox()
	v.add_child(foot)
	var sim := UiKit.label("SIMULATED DATA", &"Caption")
	sim.name = "SimulatedData"
	foot.add_child(sim)
	foot.add_child(UiKit.spacer())
	foot.add_child(UiKit.label("LOCAL · DETERMINISTIC", &"DataDim"))


func _ready() -> void:
	Simulation.event_emitted.connect(_on_event)
	Simulation.world_rebuilt.connect(rebuild)
	rebuild()


## Rebuilds everything from Simulation (after seek/reset).
func rebuild() -> void:
	for c in log_box.get_children():
		log_box.remove_child(c)
		c.free()
	for e in Simulation.emitted_events():
		log_box.add_child(_log_row(e))
	_refresh_state()
	_scroll_to_end.call_deferred()


## Mission objectives currently marked done (tests).
func done_count() -> int:
	var n := 0
	for h in _objective_rows:
		if (h.get_child(0) as Label).text == DONE_MARK:
			n += 1
	return n


func log_size() -> int:
	return log_box.get_child_count()


func _on_event(e: SimEvent) -> void:
	log_box.add_child(_log_row(e))
	_refresh_state()
	_scroll_to_end.call_deferred()


func _refresh_state() -> void:
	var emitted := Simulation.emitted_events()
	var objectives := Mission.evaluate(emitted)
	for i in objectives.size():
		var o := objectives[i]
		var h := _objective_rows[i]
		var done := bool(o["done"])
		(h.get_child(0) as Label).text = DONE_MARK if done else PENDING_MARK
		(h.get_child(1) as Label).modulate.a = 1.0 if done else 0.7
		var min_count := int(o["min_count"])
		(h.get_child(2) as Label).text = "%d/%d" % [mini(int(o["count"]), min_count), min_count] if min_count > 1 else ""
	var done_n := Mission.completed_count(objectives)
	_progress = float(done_n) / maxf(objectives.size(), 1)
	progress_label.text = "%d/%d  ·  %d%%" % [done_n, objectives.size(), roundi(_progress * 100.0)]
	_layout_progress()

	var w := Simulation.world
	var passed := {}
	for c in w.checks:
		passed[c["check"]] = float(c["at"])
	for row: Array in _check_rows:
		var ok := passed.has(row[0])
		(row[2] as Label).text = ("T+%04.1f" % passed[row[0]]) if ok else "—"
		(row[3] as Label).text = "PASSED" if ok else ("RUNNING" if w.verification_at >= 0.0 and w.verified_at < 0.0 else "—")
		(row[3] as Label).theme_type_variation = &"Data" if ok else &"DataDim"
		(row[3] as Label).add_theme_font_size_override("font_size", Palette.SIZE_SMALL)
		(row[1] as Label).modulate.a = 1.0 if ok else 0.55
	checks_header.text = "%d/%d" % [w.checks.size(), OriginChamberScript.CHECKS.size()]
	for id: StringName in _status_labels:
		(_status_labels[id] as Label).text = layers_status(w) if id == &"layers" else EntityCatalog.status(id, w)
	log_count.text = "%02d / %02d" % [emitted.size(), Simulation.timeline.events.size()]


## "3/5 · RAW": rings built and the status of the newest built ring; "PENDING" before the first.
static func layers_status(w: WorldState) -> String:
	var built := w.layers_built()
	if built == 0:
		return "PENDING"
	var st := EntityCatalog.status(OriginChamberScript.layer_entity(built - 1), w)
	return "%d/%d · %s" % [built, OriginChamberScript.LAYER_COUNT, st]


func _layout_progress() -> void:
	progress_bar.offset_left = 0.0
	progress_bar.offset_right = progress_track.size.x * _progress
	progress_bar.offset_top = 0.0
	progress_bar.offset_bottom = 0.0


func _scroll_to_end() -> void:
	if log_box.get_child_count() == 0 or not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var bar := log_scroll.get_v_scroll_bar()
	log_scroll.scroll_vertical = int(bar.max_value)


static func _log_row(e: SimEvent) -> HBoxContainer:
	var h := UiKit.hbox(12)
	h.name = String(e.id)
	var t := UiKit.label(e.format_time(), &"DataDim")
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(t)
	var col := UiKit.vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(UiKit.label(e.label, &"RowText"))
	var d := UiKit.label(e.detail, &"Body", true)
	d.add_theme_font_size_override("font_size", Palette.SIZE_SMALL)
	col.add_child(d)
	return h


static func _gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
