extends GutTest
## GENESIS HUD (Loop 4, phase B): the diegetic dialect of the HUD, shown while GENESIS is the active
## scenario. Mounting, smoke contract in both scenarios, scenario switches, the transport arc, the
## whispers, labels in space (with and without 3D nodes), the floating card, the mission verse,
## settings (quality, camera, bus volumes), H, mouse and keyboard hygiene, and palette discipline.

const HudScene := preload("res://scenes/hud.tscn")
const AutomationScript := preload("res://src/core/automation.gd")
const FADE_WAIT := Palette.T_BASE + 0.25

var hud: Hud
var host: SubViewport
var _prev_mode: SessionState.Mode
var _prev_cinematic: bool
var _volumes: Dictionary = {}


func before_each() -> void:
	_prev_mode = Session.mode
	_prev_cinematic = Session.cinematic
	for bus: StringName in [AudioDirector.BUS_MASTER, AudioDirector.BUS_AMBIENCE, AudioDirector.BUS_SFX]:
		_volumes[bus] = AudioDirector.get_bus_volume_db(bus)
	Session.set_mode(SessionState.Mode.FORGE)
	Session.select(&"")
	Session.hover(&"")
	Session.set_hud_visible(true)
	Simulation.set_scenario(Scenario.GENESIS)
	Simulation.reset()
	Simulation.set_speed(1.0)
	host = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_disable_input = true
	add_child_autofree(host)
	hud = HudScene.instantiate() as Hud
	host.add_child(hud)
	await wait_process_frames(2)


func after_each() -> void:
	Simulation.reset()
	Simulation.set_speed(1.0)
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	Session.select(&"")
	Session.hover(&"")
	Session.set_hud_visible(true)
	Session.set_mode(_prev_mode)
	Session.set_cinematic(_prev_cinematic)
	for bus: StringName in _volumes:
		AudioDirector.set_bus_volume_db(bus, _volumes[bus])


func _all_controls(n: Node, out: Array[Control]) -> Array[Control]:
	for c in n.get_children():
		if c is Control:
			out.append(c)
		_all_controls(c, out)
	return out


## A body of `id` in the host's 3D world (group entity_<id>) at `pos`, with a small sphere mesh.
func _body(id: StringName, pos: Vector3, radius := 1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	m.mesh = s
	m.position = pos
	m.add_to_group(Session.entity_group(id))
	host.add_child(m)
	return m


func _camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 50.0
	host.add_child(cam)
	cam.position = Vector3(0.0, 2.0, 16.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0))
	cam.make_current()
	return cam


# ------------------------------------------------------------------ mounting and contract

func test_genesis_hud_mounts_in_genesis() -> void:
	assert_true(hud.is_genesis())
	assert_not_null(hud.genesis)
	assert_true(hud.genesis.visible, "the GENESIS dialect is shown")
	assert_false(hud.chrome.visible, "the ORIGIN panels are not")
	assert_same(hud.active_chrome(), hud.genesis)
	assert_true(hud.badge.genesis, "the seal speaks GENESIS")
	assert_true(hud.badge.seal.visible)
	assert_false(hud.badge.marker.visible)
	for part: Control in [hud.genesis.modes, hud.genesis.transport, hud.genesis.settings, hud.genesis.labels, hud.genesis.whisper]:
		assert_true(part.is_visible_in_tree(), "%s shown" % part.name)
	assert_false(hud.genesis.card.visible, "no card without a selection")


func _check_smoke_contract(where: String) -> void:
	var transports := get_tree().get_nodes_in_group(Transport.GROUP)
	assert_eq(transports.size(), 1, "%s: exactly one ui_transport" % where)
	assert_same(transports[0], hud.active_transport(), "%s: the active dialect's transport" % where)
	var start := AutomationScript.find_ui_button(transports, "Start")
	var pause := AutomationScript.find_ui_button(transports, "Pause")
	var reset := AutomationScript.find_ui_button(transports, "Reset")
	assert_not_null(start, where)
	assert_not_null(pause, where)
	assert_not_null(reset, where)
	if start == null or pause == null or reset == null:
		return
	start.pressed.emit()
	assert_eq(Simulation.status, EventTimeline.Status.PLAYING, "%s: Start plays" % where)
	pause.pressed.emit()
	assert_eq(Simulation.status, EventTimeline.Status.PAUSED, "%s: Pause pauses" % where)
	reset.pressed.emit()
	assert_eq(Simulation.status, EventTimeline.Status.IDLE, "%s: Reset resets" % where)
	var badges := get_tree().get_nodes_in_group(DemoBadge.GROUP)
	assert_eq(badges.size(), 1, where)
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.OBSERVATORY, SessionState.Mode.FORGE]:
		Session.set_mode(m)
		await wait_process_frames(1)
		assert_true(AutomationScript.visible_demo_badge(badges), "%s: badge in %s" % [where, Session.mode_name()])


func test_smoke_contract_in_both_scenarios() -> void:
	await _check_smoke_contract("GENESIS")
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	await wait_seconds(FADE_WAIT)
	await _check_smoke_contract("ORIGIN")
	Simulation.set_scenario(Scenario.GENESIS)
	await wait_seconds(FADE_WAIT)
	await _check_smoke_contract("GENESIS again")


func test_scenario_switch_swaps_the_dialect() -> void:
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	await wait_seconds(FADE_WAIT)
	assert_false(hud.is_genesis())
	assert_true(hud.chrome.visible)
	assert_false(hud.genesis.visible)
	assert_false(hud.badge.genesis)
	assert_true(hud.badge.marker.visible)
	var tl := hud.transport.timeline
	assert_eq(tl.marks.size(), TimelineBar.phase_marks(OriginChamberScript.build()).size(), "ORIGIN marks")
	assert_eq(hud.genesis.transport.marks.size(), OriginChamberScript.build().size(), "the arc follows too")
	Simulation.set_scenario(Scenario.GENESIS)
	await wait_seconds(FADE_WAIT)
	assert_true(hud.genesis.visible)
	assert_false(hud.chrome.visible)
	assert_eq(hud.genesis.transport.marks.size(), GenesisScript.build().size())
	assert_almost_eq(hud.genesis.transport.duration, GenesisScript.DURATION, 0.001)
	assert_eq(TimelineBar.phase_marks(GenesisScript.build(), Scenario.GENESIS).size(), GenesisState.Phase.size() - 1,
		"legacy marks replay GENESIS through its own state")


func test_scenario_switch_before_the_hud_exists() -> void:
	# The HUD of this suite was built in GENESIS; a HUD built in ORIGIN then switched also works.
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	var h2 := HudScene.instantiate() as Hud
	host.add_child(h2)
	await wait_process_frames(2)
	assert_false(h2.genesis.visible)
	Simulation.set_scenario(Scenario.GENESIS)
	await wait_seconds(FADE_WAIT)
	assert_true(h2.genesis.visible)
	assert_false(h2.chrome.visible)
	h2.queue_free()
	await wait_process_frames(1)


func test_h_hides_everything_but_the_seal() -> void:
	Session.set_hud_visible(false)
	await wait_seconds(FADE_WAIT)
	assert_false(hud.genesis.visible, "GENESIS HUD hidden")
	assert_false(hud.chrome.visible, "ORIGIN chrome stays hidden")
	var badges := get_tree().get_nodes_in_group(DemoBadge.GROUP)
	assert_true(AutomationScript.visible_demo_badge(badges), "the seal survives H")
	for c in _all_controls(hud.root, []):
		if c.is_visible_in_tree():
			assert_true(c == hud.badge or hud.badge.is_ancestor_of(c) or c == hud.root,
				"only the seal is visible: %s" % c.get_path())
	Session.set_hud_visible(true)
	await wait_seconds(FADE_WAIT)
	assert_true(hud.genesis.visible)
	assert_almost_eq(hud.genesis.modulate.a, 1.0, 0.01)


# ------------------------------------------------------------------ modes

func test_mode_words_and_parts() -> void:
	var g := hud.genesis
	assert_eq(g.modes.words.size(), 3)
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.OBSERVATORY, SessionState.Mode.FORGE]:
		Session.set_mode(m)
		await wait_seconds(FADE_WAIT)
		for i in 3:
			var want := Palette.UI_INK.a if i == m else Palette.UI_INK_FAINT.a
			assert_almost_eq(g.modes.words[i].self_modulate.a, want, 0.02, "word %d in %s" % [i, Session.mode_name()])
		var obs := m == SessionState.Mode.OBSERVATORY
		assert_eq(g.mission.visible, obs, "mission only in OBSERVATORY")
		assert_eq(g.legend.visible, obs, "legend only in OBSERVATORY")
	g.modes.words[SessionState.Mode.UNIVERSE].pressed.emit()
	assert_eq(Session.mode, SessionState.Mode.UNIVERSE, "words set the mode")


# ------------------------------------------------------------------ transport

func test_transport_reveals_when_not_playing_and_conceals_while_playing() -> void:
	var tr := hud.genesis.transport
	assert_true(tr.wants_reveal(), "idle: revealed")
	assert_true(tr.is_revealed())
	assert_true(tr.left_cluster.visible)
	Simulation.start()
	await wait_seconds(Palette.T_REVEAL_LINGER + Palette.T_CONCEAL + 0.4)
	assert_false(tr.wants_reveal(), "playing, pointer away")
	assert_false(tr.is_revealed())
	assert_almost_eq(tr.reveal, 0.0, 0.01, "collapsed to the arc")
	assert_false(tr.left_cluster.visible, "hidden controls never catch the mouse")
	assert_true(tr.visible, "the arc itself stays")
	Simulation.pause()
	await wait_seconds(Palette.T_REVEAL + 0.3)
	assert_true(tr.is_revealed(), "paused: revealed again")
	assert_almost_eq(tr.reveal, 1.0, 0.01)


func test_transport_pointer_near_the_edge_reveals() -> void:
	var tr := hud.genesis.transport
	Simulation.start()
	await wait_seconds(Palette.T_REVEAL_LINGER + Palette.T_CONCEAL + 0.4)
	assert_false(tr.is_revealed())
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(800, 900 - 20)
	tr._input(mm)
	await wait_process_frames(2)
	assert_true(tr.is_revealed(), "pointer in the reveal zone")
	mm.position = Vector2(800, 300)
	tr._input(mm)
	await wait_seconds(Palette.T_REVEAL_LINGER + Palette.T_CONCEAL + 0.4)
	assert_false(tr.is_revealed(), "pointer away: conceals after the linger")


func test_transport_arc_geometry_marks_and_texts() -> void:
	var tr := hud.genesis.transport
	assert_eq(tr.marks.size(), GenesisScript.build().size(), "one mark per scripted event")
	assert_eq(UiOrbitTransport.clock_text(27.4, 56.0), "0:27 / 0:56")
	assert_eq(UiOrbitTransport.clock_text(75.0, 90.0), "1:15 / 1:30")
	assert_eq(UiOrbitTransport.speed_text(0.5), "½×")
	assert_eq(UiOrbitTransport.speed_text(2.0), "2×")
	var e := tr.arc_ends()
	assert_almost_eq(e.y - e.x, tr.size.x * Palette.UI_ARC_SHARE, 1.0, "arc spans its share")
	assert_lt(tr.arc_point(0.5).y, tr.arc_point(0.0).y, "the arc bows upwards")
	assert_almost_eq(tr.arc_point(0.0).y, tr.arc_point(1.0).y, 0.01)
	assert_almost_eq(tr.time_at(e.x), 0.0, 0.001)
	assert_almost_eq(tr.time_at((e.x + e.y) * 0.5), Simulation.duration() * 0.5, 0.01)
	assert_almost_eq(tr.time_at(e.y + 100.0), Simulation.duration(), 0.001)
	var i := tr.mark_near(tr.arc_point(GenesisScript.T_RING / Simulation.duration()).x)
	assert_eq(String(tr.marks[i]["label"]), "A RING OF SKILLS")
	Simulation.seek(33.0)
	await wait_seconds(Palette.T_UI_REFRESH * 2.0)
	assert_eq(tr.phase_label.text, Simulation.state.phase_name())
	assert_eq(tr.time_label.text, UiOrbitTransport.clock_text(33.0, Simulation.duration()))
	tr.speed_buttons[2].pressed.emit()
	assert_eq(Simulation.timeline.speed, UiOrbitTransport.SPEEDS[2])


func test_transport_track_seeks() -> void:
	var tr := hud.genesis.transport
	var e := tr.arc_ends()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(lerpf(e.x, e.y, 0.25) - tr.track.position.x, 10)
	tr.track.gui_input.emit(mb)
	var up := mb.duplicate() as InputEventMouseButton
	up.pressed = false
	tr.track.gui_input.emit(up)
	await wait_process_frames(2)
	assert_almost_eq(Simulation.time, Simulation.duration() * 0.25, 0.1, "click on the arc seeks")


# ------------------------------------------------------------------ whispers

func test_whisper_rises_and_dissolves() -> void:
	var w := hud.genesis.whisper
	assert_eq(w.current_text(), "")
	Simulation.seek(GenesisScript.T_RING - 0.05)
	Simulation.start()
	Simulation._process(0.1)
	await wait_process_frames(1)
	assert_eq(w.current_text(), "A RING OF SKILLS", "the event's poetic label")
	assert_eq(w.lines.size(), 2, "two lines at most: no feed")
	Simulation.pause()
	Simulation.seek(10.0)
	await wait_seconds(Palette.T_FAST * 2.0 + 0.3)
	for l in w.lines:
		assert_almost_eq(l.modulate.a, 0.0, 0.01, "seek dissolves the whisper")
	w.whisper("FIRST")
	w.whisper("SECOND")
	assert_eq(w.current_text(), "SECOND", "a newer event cross-fades over the older")


func test_whispers_hand_off_one_at_a_time() -> void:
	# Critic r1: "SESSION OPENED" and "MIKU AWAKENS" crossed into "SESSIONWOPENED" (two lines drawn
	# over each other). The older line dissolves first; the newer one rises only once it is dark.
	var w := hud.genesis.whisper
	w.dissolve()
	await wait_seconds(Palette.T_FAST * 2.0 + 0.1)
	w.whisper("FIRST")
	await wait_seconds(Palette.T_WHISPER_IN + 0.2)
	assert_eq(w.current_text(), "FIRST")
	w.whisper("SECOND")
	assert_eq(w.current_text(), "SECOND", "the newer event is the current one at once")
	var t0 := Time.get_ticks_msec()
	var overlap := 0.0
	var second_seen := false
	while Time.get_ticks_msec() - t0 < int((Palette.T_WHISPER_HANDOFF + Palette.T_WHISPER_IN) * 1000.0):
		await wait_process_frames(1)
		overlap = maxf(overlap, minf(w.lines[0].modulate.a, w.lines[1].modulate.a))
		for l in w.lines:
			if l.modulate.a > 0.02 and l.text == "SECOND":
				second_seen = true
			if l.text == "FIRST" and l.modulate.a > 0.02:
				assert_false(second_seen, "FIRST never shows again once SECOND rose")
	assert_lt(overlap, 0.03, "never two whispers on screen at once")
	assert_true(second_seen, "the newer whisper rose")


# ------------------------------------------------------------------ labels in space

func test_labels_without_nodes_or_camera_do_nothing() -> void:
	var labels := hud.genesis.labels
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	Simulation.seek(Simulation.duration())
	labels.update_labels(1.0)
	assert_eq(labels.shown_ids().size(), 0, "no 3D modules yet: no labels")
	assert_true(labels.screen_anchor(&"planet_forming").is_empty())
	_camera()
	labels.update_labels(1.0)
	await wait_process_frames(2)
	assert_eq(labels.shown_ids().size(), 0, "a camera but no bodies: still nothing")
	assert_null(UiSpaceLabels.entity_anchor(get_tree(), &"planet_forming"))


func test_labels_follow_bodies_by_mode() -> void:
	var labels := hud.genesis.labels
	labels.camera_override = _camera()
	_body(&"planet_forming", Vector3(0, 1, 0), 1.6)
	_body(&"moon_0", Vector3(3.5, 1.2, 0.5), 0.35)
	_body(&"miku", Vector3(0, 4, -2), 1.0)
	var belt := Node3D.new()
	belt.add_to_group(Session.entity_group(&"belt_memory"))
	host.add_child(belt)
	Simulation.seek(Simulation.duration())
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	labels.update_labels(Palette.T_LABEL + 0.1)
	var shown := labels.shown_ids()
	for id: StringName in [&"planet_forming", &"moon_0", &"miku"]:
		assert_has(shown, id, "OBSERVATORY labels every body: %s" % id)
	assert_does_not_have(shown, &"belt_memory", "a belt without label_anchor sits on MIKU: no label")
	var a := labels.screen_anchor(&"planet_forming")
	assert_false(a.is_empty())
	assert_almost_eq((a["pos"] as Vector2).x, 800.0, 40.0, "projected near the centre")
	assert_gt(float(a["r"]), 5.0, "a radius in px from the mesh")
	belt.set_meta(UiSpaceLabels.META_ANCHOR, Vector3(-3.0, 0.0, 0.0))
	labels.update_labels(Palette.T_LABEL + 0.1)
	assert_has(labels.shown_ids(), &"belt_memory", "with a label_anchor it is labelled")
	# FORGE: only hover / selection.
	Session.set_mode(SessionState.Mode.FORGE)
	labels.update_labels(Palette.T_LABEL + 0.1)
	assert_eq(labels.shown_ids().size(), 0, "FORGE: nothing without focus")
	Session.hover(&"moon_0")
	labels.update_labels(Palette.T_LABEL * 0.5)
	assert_between(labels.label_progress(&"moon_0"), 0.3, 0.7, "fades in (no pop)")
	labels.update_labels(Palette.T_LABEL)
	assert_eq(labels.shown_ids(), [&"moon_0"] as Array[StringName], "FORGE: the hovered body")
	Session.hover(&"")
	# Not formed yet: no label even in OBSERVATORY.
	Simulation.seek(1.0)
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	labels.update_labels(Palette.T_LABEL * 2.0)
	assert_does_not_have(labels.shown_ids(), &"moon_0", "an unformed moon is not named")
	assert_has(labels.shown_ids(), &"miku")
	await wait_process_frames(2)  # _draw runs with real labels without errors


func test_label_placement_avoids_bodies_and_labels() -> void:
	var vp := Vector2(1600, 900)
	var block := Vector2(120, 30)
	var placed: Array[Rect2] = []
	var discs: Array[Rect2] = []
	var own := Rect2(Vector2(990, 390), Vector2(20, 20))
	discs.append(own)
	var lay := UiSpaceLabels.place_label(Vector2(1000, 400), 10.0, block, 15.0, vp, placed, discs, own)
	assert_eq(float(lay["side"]), 1.0, "outward (right of centre)")
	var natural: Rect2 = lay["rect"]
	placed.append(natural)
	var lay2 := UiSpaceLabels.place_label(Vector2(1000, 400), 10.0, block, 15.0, vp, placed, discs, own)
	assert_false((lay2["rect"] as Rect2).intersects(natural.grow(2.0)), "a second label moves away")
	var near_edge := UiSpaceLabels.place_label(Vector2(1590, 400), 10.0, block, 15.0, vp, [] as Array[Rect2], [] as Array[Rect2], Rect2())
	assert_eq(float(near_edge["side"]), -1.0, "flips inside the screen")


# ------------------------------------------------------------------ floating card

func test_card_follows_selection() -> void:
	var card := hud.genesis.card
	Simulation.seek(33.0)
	Session.select(&"planet_forming")
	await wait_seconds(FADE_WAIT)
	assert_true(card.visible)
	assert_eq(card.title_label.text, GenesisScript.PLANET_NAME)
	assert_eq(card.status_label.text, Scenario.entity_status(Scenario.GENESIS, &"planet_forming", Simulation.state).to_lower())
	assert_eq(card.kind_label.text, "subagent")
	assert_eq(hud.genesis.labels.card_id, &"planet_forming", "its label yields to the card")
	var vp := Vector2(1600, 900)
	var r := card.get_global_rect()
	assert_true(Rect2(Vector2.ZERO, vp).encloses(r), "on screen without a body (docked)")
	watch_signals(Session)
	card.focus_button.pressed.emit()
	assert_signal_emitted_with_parameters(Session, "focus_requested", [&"planet_forming"])
	card.close_button.pressed.emit()
	assert_eq(Session.selected, &"")
	await wait_seconds(FADE_WAIT)
	assert_false(card.visible)
	Session.select(&"layer_2")
	await wait_process_frames(1)
	assert_false(card.wants_visible(), "an ORIGIN id means nothing in GENESIS")


func test_card_sits_beside_its_body() -> void:
	var card := hud.genesis.card
	var vp := Vector2(1600, 900)
	await wait_process_frames(1)
	var left := card.target_position(vp, {"pos": Vector2(500, 450), "r": 40.0})
	assert_gt(left.x, 500.0 + 40.0, "right of a body on the left")
	var right := card.target_position(vp, {"pos": Vector2(1450, 450), "r": 40.0})
	assert_lt(right.x + UiBodyCard.WIDTH, 1450.0 - 40.0, "left of a body near the right edge")
	var low := card.target_position(vp, {"pos": Vector2(800, 890), "r": 10.0})
	assert_lte(low.y, vp.y - float(Palette.UI_REVEAL_ZONE), "never inside the transport zone")


# ------------------------------------------------------------------ mission

func test_mission_verse() -> void:
	var mv := hud.genesis.mission
	assert_eq(UiMissionVerse.verse_title(Mission.GENESIS_TITLE), "A WORLD IS BORN")
	assert_eq(UiMissionVerse.verse_title("PLAIN"), "PLAIN")
	assert_eq(mv.title_label.text, "A WORLD IS BORN")
	assert_eq(mv.lines_box.get_child_count(), Mission.GENESIS_OBJECTIVES.size())
	var fresh := Mission.evaluate([] as Array[SimEvent], Scenario.GENESIS)
	var st := UiMissionVerse.states_of(fresh)
	assert_eq(st[0], 1, "the first objective is under way")
	assert_eq(st.count(1), 1, "only one under way")
	Simulation.seek(41.0)
	await wait_process_frames(1)
	var ev := Mission.evaluate(Simulation.emitted_events(), Scenario.GENESIS)
	assert_eq(mv.done_count(), Mission.completed_count(ev))
	for c in _all_controls(mv, []):
		var t: Variant = c.get(&"text")
		if t is String:
			assert_false((t as String).contains("%"), "no percentages")
			assert_false((t as String).contains("/"), "no counters")


# ------------------------------------------------------------------ settings

func test_settings_quality_camera_and_volumes() -> void:
	var s := hud.genesis.settings
	assert_false(s.is_open())
	s.toggle_button.toggled.emit(true)
	await wait_seconds(FADE_WAIT)
	assert_true(s.is_open())
	assert_true(s.quality_buttons[UiQuietSettings.current_choice()].button_pressed)
	var before := Session.cinematic
	s.cinematic_button.toggled.emit(not before)
	assert_eq(Session.cinematic, not before)
	Session.set_cinematic(before)
	assert_eq(s.cinematic_button.button_pressed, before, "follows cinematic_changed")
	assert_almost_eq(UiQuietSettings.volume_to_slider(0.0), 1.0, 0.001)
	assert_almost_eq(UiQuietSettings.slider_to_volume(1.0), 0.0, 0.001)
	assert_eq(UiQuietSettings.slider_to_volume(0.0), UiQuietSettings.SILENT_DB)
	assert_eq(UiQuietSettings.volume_to_slider(UiQuietSettings.SILENT_DB), 0.0)
	assert_almost_eq(UiQuietSettings.volume_to_slider(UiQuietSettings.slider_to_volume(0.5)), 0.5, 0.001)
	if AudioServer.get_bus_index(AudioDirector.BUS_AMBIENCE) >= 0:
		var sl: Range = s.sliders[AudioDirector.BUS_AMBIENCE]
		sl.value = 0.5
		assert_almost_eq(AudioDirector.get_bus_volume_db(AudioDirector.BUS_AMBIENCE), linear_to_db(0.5), 0.05,
			"the slider drives the Ambience bus")
	for sl: Range in s.sliders.values():
		assert_eq((sl as Control).focus_mode, Control.FOCUS_NONE, "sliders leave the keys to Shortcuts")
	Session.set_hud_visible(false)
	await wait_seconds(Palette.T_FAST + 0.2)
	assert_false(s.card.visible, "hiding the HUD closes the card")
	assert_false(s.toggle_button.button_pressed)


# ------------------------------------------------------------------ hygiene

func test_centre_belongs_to_the_world() -> void:
	Session.select(&"planet_forming")
	for m: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.FORGE, SessionState.Mode.OBSERVATORY]:
		Session.set_mode(m)
		await wait_seconds(FADE_WAIT)
		var centre := hud.root.get_viewport_rect().size * 0.5
		var blockers: Array[String] = []
		for c in _all_controls(hud.genesis, []):
			if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and c.get_global_rect().has_point(centre):
				blockers.append(String(c.get_path()))
		assert_eq(blockers.size(), 0, "%s: nothing catches the mouse at the centre: %s" % [Session.mode_name(), blockers])
	assert_eq(hud.genesis.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.genesis.transport.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the strip lets picking through")
	assert_eq(hud.genesis.labels.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_keyboard_and_wheel_hygiene() -> void:
	var catchers := 0
	for c in _all_controls(hud.genesis, []):
		if c is BaseButton or c is Range:
			assert_eq(c.focus_mode, Control.FOCUS_NONE, "%s leaves the keys to Shortcuts" % c.get_path())
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			catchers += 1
			assert_false(c.mouse_force_pass_scroll_events, "%s lets the wheel through" % c.get_path())
	assert_gt(catchers, 10)


func test_nothing_suggests_a_real_connection() -> void:
	Simulation.seek(Simulation.duration())
	Session.select(&"relations")
	hud.genesis.settings.set_open(true)
	await wait_process_frames(2)
	var forbidden := ["CONNECT", "SERVER", "CLOUD", "LOGIN", "ACCOUNT", "SYNC", "NETWORK", "UPLOAD", "API "]
	for c in _all_controls(hud.root, []):
		var t: Variant = c.get(&"text")
		if not (t is String):
			continue
		var up := (t as String).to_upper()
		for w: String in forbidden:
			assert_false(up.contains(w), "%s: \"%s\" contains %s" % [c.get_path(), t, w])


func test_ui_v2_palette_discipline() -> void:
	for c: Color in [Palette.UI_INK, Palette.UI_INK_SOFT, Palette.UI_INK_FAINT, Palette.UI_THREAD, Palette.UI_THREAD_FAINT]:
		assert_almost_eq(c.r, Palette.PEARL.r, 0.003, "pearl ink")
		assert_almost_eq(c.g, Palette.PEARL.g, 0.003)
		assert_almost_eq(c.b, Palette.PEARL.b, 0.003)
		assert_lt(c.a, 1.0, "ink is never opaque")
	for c: Color in [Palette.UI_VEIL, Palette.UI_SHADE]:
		assert_almost_eq(c.r, Palette.SPACE_DEEP.r, 0.003, "night veil")
		assert_almost_eq(c.g, Palette.SPACE_DEEP.g, 0.003)
		assert_almost_eq(c.b, Palette.SPACE_DEEP.b, 0.003)
	assert_gt(Palette.UI_INK.a, Palette.UI_INK_SOFT.a)
	assert_gt(Palette.UI_INK_SOFT.a, Palette.UI_INK_FAINT.a)
	assert_gt(Palette.UI_INK_FAINT.a, Palette.UI_THREAD.a)
	assert_gt(Palette.UI_THREAD.a, Palette.UI_THREAD_FAINT.a)
	var t := UiTheme.get_theme()
	for v in ["Whisper", "Word", "WordSoft", "WordFaint", "Note", "NoteFaint", "Verse", "CardTitle", "Clock", "SealText"]:
		assert_eq(t.get_type_variation_base(v), &"Label", v)
		assert_between(t.get_font_size("font_size", v), 11, 15, "%s legible" % v)
	for v in ["WordButton", "ModeWord", "GlyphButton"]:
		assert_eq(t.get_type_variation_base(v), &"Button", v)
	assert_eq(t.get_type_variation_base(&"WordLink"), &"WordButton")
	for v in ["Card", "Seal"]:
		assert_eq(t.get_type_variation_base(v), &"PanelContainer", v)
	# The UI creates nothing: no GOLD (nor v1 EMBER/PALE) anywhere in the theme.
	for type in t.get_color_type_list():
		for n in t.get_color_list(type):
			var col := t.get_color(n, type)
			for bad: Color in [Palette.GOLD, Palette.MAGMA, Palette.GOLD_DEEP, Palette.EMBER, Palette.PALE]:
				assert_false(Color(col, 1.0).is_equal_approx(bad), "%s/%s is an energy colour" % [type, n])
	for type in t.get_stylebox_type_list():
		for n in t.get_stylebox_list(type):
			var sb := t.get_stylebox(n, type) as StyleBoxFlat
			if sb == null:
				continue
			for col: Color in [sb.bg_color, sb.border_color]:
				assert_false(Color(col, 1.0).is_equal_approx(Palette.GOLD), "%s/%s stylebox is GOLD" % [type, n])


func test_glyphs_draw_every_sign() -> void:
	var probe := Control.new()
	probe.size = Vector2(40, 40)
	host.add_child(probe)
	probe.draw.connect(func() -> void:
		for g: StringName in UiGlyphs.ALL:
			UiGlyphs.draw(probe, g, Vector2(20, 20), 5.0, Palette.UI_INK))
	probe.queue_redraw()
	await wait_process_frames(2)
	for k: String in GenesisCatalog.KIND_NAMES:
		assert_ne(UiGlyphs.kind_glyph(k), &"", "a sign for %s" % k)
		assert_ne(UiSpaceLabels.kind_word({"kind_name": k}), "", "a word for %s" % k)
	probe.queue_free()
