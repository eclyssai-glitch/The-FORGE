extends GutTest
## Native HUD (Loop 3): built from scenes/hud.tscn in headless and driven only through the
## autoloads. DEMO badge policy, transport contract, timeline, feed, inspector, mode panels,
## settings, mouse filters (the centre belongs to the world) and "nothing suggests a connection".

const HudScene := preload("res://scenes/hud.tscn")
const AutomationScript := preload("res://src/core/automation.gd")
const FADE_WAIT := Palette.T_BASE + 0.2

var hud: Hud
## The HUD lives in a SubViewport of a real window size (the headless root viewport is tiny).
var host: SubViewport
var _prev_mode: SessionState.Mode
var _prev_cinematic: bool


func before_each() -> void:
	_prev_mode = Session.mode
	_prev_cinematic = Session.cinematic
	Session.set_mode(SessionState.Mode.FORGE)
	Session.select(&"")
	Session.set_hud_visible(true)
	Simulation.reset()
	Simulation.set_speed(1.0)
	host = SubViewport.new()
	host.size = Vector2i(1280, 720)
	host.gui_disable_input = true
	add_child_autofree(host)
	hud = HudScene.instantiate() as Hud
	host.add_child(hud)
	await wait_process_frames(2)


func after_each() -> void:
	Simulation.reset()
	Simulation.set_speed(1.0)
	Session.select(&"")
	Session.set_hud_visible(true)
	Session.set_mode(_prev_mode)
	Session.set_cinematic(_prev_cinematic)


func _click(target: Control, at := Vector2(4, 4)) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	target._gui_input(mb)
	var up := mb.duplicate() as InputEventMouseButton
	up.pressed = false
	target._gui_input(up)


func _all_controls(n: Node, out: Array[Control]) -> Array[Control]:
	for c in n.get_children():
		if c is Control:
			out.append(c)
		_all_controls(c, out)
	return out


func test_demo_badge_always_visible() -> void:
	var badges := get_tree().get_nodes_in_group(DemoBadge.GROUP)
	assert_eq(badges.size(), 1)
	assert_true(AutomationScript.visible_demo_badge(badges), "visible, with DEMO in its text")
	assert_eq((badges[0] as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "never catches the mouse")
	Session.set_hud_visible(false)
	await wait_seconds(FADE_WAIT)
	assert_false(hud.chrome.visible, "H hides the rest of the HUD")
	assert_true(AutomationScript.visible_demo_badge(badges), "the badge survives H")
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.OBSERVATORY, SessionState.Mode.FORGE]:
		Session.set_mode(m)
		await wait_process_frames(1)
		assert_true(AutomationScript.visible_demo_badge(badges), "badge in %s" % Session.mode_name())
	Session.set_hud_visible(true)
	await wait_seconds(FADE_WAIT)
	assert_true(hud.chrome.visible)
	assert_almost_eq(hud.chrome.modulate.a, 1.0, 0.01)


func test_transport_contract_drives_simulation() -> void:
	var transports := get_tree().get_nodes_in_group(Transport.GROUP)
	assert_eq(transports.size(), 1)
	var start := AutomationScript.find_ui_button(transports, "Start")
	var pause := AutomationScript.find_ui_button(transports, "Pause")
	var reset := AutomationScript.find_ui_button(transports, "Reset")
	assert_not_null(start)
	assert_not_null(pause)
	assert_not_null(reset)
	for b: BaseButton in [start, pause, reset]:
		assert_eq(b.focus_mode, Control.FOCUS_NONE, "%s never keeps the keyboard" % b.name)
	assert_true(start.visible and not pause.visible, "idle: START in the play slot")
	start.pressed.emit()
	assert_eq(Simulation.status, EventTimeline.Status.PLAYING)
	await wait_process_frames(2)
	assert_true(pause.visible and not start.visible, "playing: PAUSE in the play slot")
	pause.pressed.emit()
	assert_eq(Simulation.status, EventTimeline.Status.PAUSED)
	assert_eq((start as Button).text, "RESUME")
	reset.pressed.emit()
	assert_eq(Simulation.status, EventTimeline.Status.IDLE)
	assert_eq(Simulation.time, 0.0)


func test_time_phase_and_speed() -> void:
	var tr: Transport = hud.transport
	assert_eq(Transport.time_text(3.25, 50.0), "T+03.2 / 50.0")
	assert_eq(Transport.speed_text(0.5), "0.5×")
	assert_eq(Transport.speed_text(4.0), "4×")
	Simulation.seek(30.5)
	await wait_seconds(Palette.T_UI_REFRESH * 2.0)
	assert_eq(tr.time_label.text, Transport.time_text(30.5, Simulation.duration()))
	assert_eq(tr.phase_label.text, Simulation.world.phase_name())
	tr.speed_buttons[2].pressed.emit()
	assert_eq(Simulation.timeline.speed, Transport.SPEEDS[2])
	tr.refresh()
	assert_true(tr.speed_buttons[2].button_pressed)
	assert_false(tr.speed_buttons[1].button_pressed)


func test_timeline_marks_and_seek() -> void:
	var marks := TimelineBar.phase_marks(OriginChamberScript.build())
	assert_gt(marks.size(), 5)
	assert_eq(float(marks[0]["time"]), 1.5)
	assert_eq(String(marks[0]["phase"]), "ACTIVATING")
	assert_eq(String(marks[-1]["phase"]), "COMPLETE")
	for i in range(1, marks.size()):
		assert_gt(float(marks[i]["time"]), float(marks[i - 1]["time"]), "marks ascending")
	var tl: TimelineBar = hud.transport.timeline
	assert_eq(tl.marks.size(), marks.size())
	assert_gt(tl.size.x, 100.0)
	assert_eq(tl.focus_mode, Control.FOCUS_NONE)
	assert_almost_eq(tl.time_at(tl.size.x * 0.5), Simulation.duration() * 0.5, 0.001)
	assert_eq(tl.time_at(-50.0), 0.0)
	assert_eq(tl.time_at(tl.size.x + 50.0), Simulation.duration())
	_click(tl, Vector2(tl.size.x * 0.4, 4))
	await wait_process_frames(2)
	assert_almost_eq(Simulation.time, Simulation.duration() * 0.4, 0.05, "click seeks")


func test_feed_follows_events_and_rebuilds() -> void:
	var feed: EventFeed = hud.feed
	assert_true(feed.idle_label.visible, "idle hint before the first event")
	Simulation.seek(20.0)
	await wait_process_frames(1)
	var emitted := Simulation.emitted_events()
	var labels := feed.shown_labels()
	assert_eq(labels.size(), mini(EventFeed.MAX_ROWS, emitted.size()))
	assert_eq(labels[-1], emitted[-1].label, "newest at the bottom")
	Simulation.start()
	Simulation._process(4.0)
	await wait_process_frames(1)
	assert_eq(feed.shown_labels()[-1], Simulation.emitted_events()[-1].label, "appends live events")
	assert_lte(feed.shown_labels().size(), EventFeed.MAX_ROWS)
	Simulation.reset()
	await wait_process_frames(1)
	assert_eq(feed.shown_labels().size(), 0, "reset rebuilds")


func test_inspector_selection_and_focus() -> void:
	var ins: Inspector = hud.inspector
	assert_false(ins.visible, "hidden without a selection")
	Simulation.seek(30.5)
	Session.select(&"layer_2")
	await wait_seconds(FADE_WAIT)
	assert_true(ins.visible)
	assert_eq(ins.title_label.text, String(EntityCatalog.info(&"layer_2")["title"]))
	assert_eq(ins.status_label.text, EntityCatalog.status(&"layer_2", Simulation.world))
	var related := Inspector.related_events(&"layer_2", Simulation.emitted_events())
	assert_eq(related.size(), 1)
	assert_eq(related[0].entity, &"layer_2")
	watch_signals(Session)
	ins.focus_button.pressed.emit()
	assert_signal_emitted_with_parameters(Session, "focus_requested", [&"layer_2"])
	assert_eq(Session.selected, &"layer_2", "focus keeps the selection")
	ins.clear_button.pressed.emit()
	assert_eq(Session.selected, &"")
	await wait_seconds(FADE_WAIT)
	assert_false(ins.visible)


func test_forge_rows_select() -> void:
	var list: EntityList = hud.forge_panel.list
	assert_eq(list.rows.size(), ForgePanel.ids().size())
	assert_has(ForgePanel.ids(), &"origin_core")
	assert_has(ForgePanel.ids(), &"verification_array")
	Simulation.seek(15.0)
	await wait_process_frames(1)
	assert_eq(list.row(&"layer_0").status_label.text, EntityCatalog.status(&"layer_0", Simulation.world))
	watch_signals(Session)
	_click(list.row(&"layer_3"))
	assert_eq(Session.selected, &"layer_3")
	assert_signal_not_emitted(Session, "focus_requested", "FORGE rows only select")
	assert_true(list.row(&"layer_3").is_selected())
	assert_false(list.row(&"layer_0").is_selected())


func test_universe_rows_select_and_focus() -> void:
	var list: EntityList = hud.universe_panel.list
	assert_eq(list.rows.size(), 4)
	watch_signals(Session)
	_click(list.row(&"seed_vesper"))
	assert_eq(Session.selected, &"seed_vesper")
	assert_signal_emitted_with_parameters(Session, "focus_requested", [&"seed_vesper"])


func test_observatory_mission_log_results() -> void:
	var obs: ObservatoryPanel = hud.observatory_panel
	Simulation.seek(37.0)
	await wait_process_frames(2)
	var emitted := Simulation.emitted_events()
	assert_eq(obs.done_count(), Mission.completed_count(Mission.evaluate(emitted)))
	assert_eq(obs.log_size(), emitted.size(), "complete log")
	assert_eq(obs.checks_header.text, "%d/%d" % [Simulation.world.checks.size(), OriginChamberScript.CHECKS.size()])
	assert_eq(ObservatoryPanel.layers_status(Simulation.world), "5/5 · FINISHED")
	assert_eq(ObservatoryPanel.layers_status(WorldState.new()), "PENDING")
	assert_not_null(obs.find_child("SimulatedData", true, false))
	assert_true((obs.find_child("SimulatedData", true, false) as Label).text.to_upper().contains("SIMULATED"))
	Simulation.reset()
	await wait_process_frames(2)
	assert_eq(obs.log_size(), 0)
	assert_eq(obs.done_count(), 0)


func test_mode_panels_cross_fade() -> void:
	var expect := {
		SessionState.Mode.UNIVERSE: [hud.universe_panel, hud.feed],
		SessionState.Mode.OBSERVATORY: [hud.observatory_panel],
		SessionState.Mode.FORGE: [hud.forge_panel, hud.feed],
	}
	var all: Array[Control] = [hud.forge_panel, hud.universe_panel, hud.observatory_panel, hud.feed]
	for m: SessionState.Mode in expect:
		Session.set_mode(m)
		await wait_seconds(FADE_WAIT)
		for p in all:
			assert_eq(p.visible, (expect[m] as Array).has(p), "%s in %s" % [p.name, Session.mode_name()])
		assert_true(hud.mode_bar.tabs[m].button_pressed, "active tab follows the mode")
	hud.mode_bar.tabs[SessionState.Mode.OBSERVATORY].pressed.emit()
	assert_eq(Session.mode, SessionState.Mode.OBSERVATORY, "tabs set the mode")


func test_observatory_sheet_takes_the_left_share() -> void:
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	await wait_seconds(FADE_WAIT)
	var vp := hud.root.get_viewport_rect().size
	var r := hud.observatory_panel.get_global_rect()
	assert_almost_eq(r.position.x, 0.0, 1.0)
	assert_almost_eq(r.end.x, vp.x * Palette.OBSERVATORY_PANEL_SHARE, 2.0)
	assert_lt(r.end.y, hud.transport.get_global_rect().position.y, "above the transport")


func test_centre_belongs_to_the_world() -> void:
	await _check_centre_free()
	host.size = Vector2i(1600, 900)
	await wait_process_frames(2)
	await _check_centre_free()


func _check_centre_free() -> void:
	assert_eq(hud.root.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.chrome.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	Session.select(&"layer_1")
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.FORGE, SessionState.Mode.OBSERVATORY]:
		Session.set_mode(m)
		await wait_seconds(FADE_WAIT)
		var vp := hud.root.get_viewport_rect().size
		# Centre of the world: the viewport centre, or the centre of the free area right of the sheet.
		var centre := vp * 0.5
		if m == SessionState.Mode.OBSERVATORY:
			centre.x = vp.x * (1.0 + Palette.OBSERVATORY_PANEL_SHARE) * 0.5
		var blockers: Array[String] = []
		for c in _all_controls(hud.root, []):
			if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and c.get_global_rect().has_point(centre):
				blockers.append(String(c.get_path()))
		assert_eq(blockers.size(), 0, "%s: nothing catches the mouse at the world centre: %s" % [Session.mode_name(), blockers])


func test_settings_quality_and_cinematic() -> void:
	var s: SettingsMenu = hud.settings
	assert_false(s.is_open())
	s.toggle_button.toggled.emit(true)
	await wait_seconds(Palette.T_FAST + 0.2)
	assert_true(s.is_open())
	assert_eq(SettingsMenu.QUALITY_CHOICES.size(), QualityProfiles.LEVEL_NAMES.size() + 1)
	for i in QualityProfiles.LEVEL_NAMES.size():
		assert_eq(SettingsMenu.QUALITY_CHOICES[i + 1], QualityProfiles.LEVEL_NAMES[i])
	assert_eq(SettingsMenu.current_choice(), 0 if Quality.auto else int(Quality.level) + 1)
	assert_true(s.quality_buttons[SettingsMenu.current_choice()].button_pressed)
	var before := Session.cinematic
	s.cinematic_button.toggled.emit(not before)
	assert_eq(Session.cinematic, not before)
	assert_eq(s.cinematic_button.text, "ON" if Session.cinematic else "OFF")
	Session.set_cinematic(before)
	assert_eq(s.cinematic_button.button_pressed, before, "follows cinematic_changed (V)")
	Session.set_hud_visible(false)
	await wait_process_frames(1)
	assert_false(s.panel.visible and s.panel.modulate.a > 0.99, "hiding the HUD closes the menu")


func test_no_button_takes_keyboard_focus() -> void:
	for c in _all_controls(hud.root, []):
		if c is BaseButton or c is TimelineBar or c is ListRow:
			assert_eq(c.focus_mode, Control.FOCUS_NONE, "%s leaves the keys to Shortcuts" % c.get_path())


func test_nothing_suggests_a_real_connection() -> void:
	Simulation.seek(Simulation.duration())
	Session.select(&"origin_chamber")
	await wait_process_frames(2)
	var forbidden := ["CONNECT", "SERVER", "CLOUD", "LOGIN", "ACCOUNT", "SYNC", "NETWORK", "UPLOAD", "API "]
	for c in _all_controls(hud.root, []):
		var t: Variant = c.get(&"text")
		if not (t is String):
			continue
		var up := (t as String).to_upper()
		for w: String in forbidden:
			assert_false(up.contains(w), "%s: \"%s\" contains %s" % [c.get_path(), t, w])


func test_inspector_docks_away_from_the_subject() -> void:
	Session.select(&"origin_core")
	await wait_seconds(FADE_WAIT)
	var top_rect := hud.inspector.get_global_rect()
	assert_lt(top_rect.position.y, 120.0, "top-right in FORGE")
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	await wait_seconds(FADE_WAIT)
	var r := hud.inspector.get_global_rect()
	assert_true(hud.inspector.visible)
	assert_almost_eq(r.end.y, hud.transport.get_global_rect().position.y - Palette.UI_GAP, 1.0,
		"bottom-right, just above the transport, in OBSERVATORY")
	assert_false(r.intersects(hud.observatory_panel.get_global_rect()), "never over the sheet")
	Session.set_mode(SessionState.Mode.FORGE)
	await wait_seconds(FADE_WAIT)
	assert_almost_eq(hud.inspector.get_global_rect().position.y, top_rect.position.y, 1.0)
