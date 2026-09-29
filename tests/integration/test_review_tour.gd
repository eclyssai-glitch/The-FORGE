extends GutTest
## Review tour (tools/review): the scene loads headless on top of the real main scene, every HUD
## control the script clicks exists, the step list is monotonic in game time and stays inside the
## demo (PAUSE before the end), and the phase captions follow the scripted events.

const TourScene := preload("res://tools/review/review_tour.tscn")
const TourScript := preload("res://tools/review/review_tour.gd")

var _prev_mode: SessionState.Mode


func before_each() -> void:
	_prev_mode = Session.mode
	Simulation.reset()


func after_each() -> void:
	Simulation.reset()
	Session.select(&"")
	Session.set_mode(_prev_mode)


func _tour() -> Node:
	var tour: Node = TourScene.instantiate()
	tour.set(&"autorun", false)
	add_child_autofree(tour)
	return tour


func test_steps_are_monotonic_and_well_formed() -> void:
	var steps: Array[Dictionary] = TourScript.steps()
	assert_gt(steps.size(), 20)
	var last := -1.0
	var known: Array[StringName] = [&"card", &"card_hide", &"caption", &"caption_clear", &"phase_captions",
		&"key", &"move", &"click", &"drag_timeline", &"orbit", &"quit"]
	for s in steps:
		var t := float(s["t"])
		assert_true(t >= last, "step at %.2f after %.2f" % [t, last])
		last = t
		assert_has(known, StringName(s["do"]), "known action %s" % s["do"])
		if s.has("target"):
			assert_has(TourScript.TARGETS, StringName(s["target"]), "known target %s" % s["target"])
		if s["do"] == &"caption":
			assert_ne(String(s["text"]), "", "caption text")
	assert_eq(steps.back()["do"], &"quit", "the tour ends with quit")
	var total := float(steps.back()["t"])
	assert_between(total, 125.0, 165.0, "about 2 min 10 s – 2 min 45 s")


func test_pause_happens_before_the_demo_ends() -> void:
	var start_t := -1.0
	var pause_t := -1.0
	for s in TourScript.steps():
		if s["do"] == &"click" and s["target"] == &"start" and start_t < 0.0:
			start_t = float(s["t"])
		if s["do"] == &"click" and s["target"] == &"pause":
			pause_t = float(s["t"])
	assert_gt(start_t, 0.0)
	assert_gt(pause_t, start_t)
	var at := pause_t - start_t
	assert_lt(at, Simulation.duration() - 0.5, "PAUSE exists only while playing")
	assert_gt(at, 45.0, "the final form (T+45) was shown before pausing")


func test_phase_captions_cover_the_six_phases_once() -> void:
	var hits: Array[StringName] = []
	for e in OriginChamberScript.build():
		if not TourScript.phase_caption(e).is_empty():
			hits.append(e.type)
	assert_eq(hits, [SimEvent.CORE_ACTIVATION, SimEvent.FRAGMENTS_EMITTED, SimEvent.LAYER_ADDED,
		SimEvent.MATERIALS_APPLIED, SimEvent.VERIFICATION_STARTED, SimEvent.STRUCTURE_FINALIZED] as Array[StringName])


func test_tour_loads_and_finds_every_control() -> void:
	var tour := _tour()
	await wait_process_frames(3)
	assert_not_null(tour.get(&"main"), "main scene instanced")
	assert_not_null(tour.get(&"hud"), "HUD found")
	for id: StringName in TourScript.TARGETS:
		var c: Control = tour.call(&"target_control", id)
		assert_not_null(c, "control for %s" % id)
	assert_true(tour.call(&"target_control", &"start") is Button)
	assert_true(tour.call(&"target_control", &"timeline") is TimelineBar)
	assert_true(tour.call(&"target_control", &"row_layer_iii") is ListRow)
	assert_true(tour.call(&"target_control", &"row_seed_aurel") is ListRow)
	assert_eq(String((tour.call(&"target_control", &"speed_2") as Button).text), Transport.speed_text(2.0))
	assert_eq(String((tour.call(&"target_control", &"tab_forge") as Button).text), "FORGE")
	# Overlay: above the HUD and the entry fade; nothing in it catches the mouse.
	var layer := tour.get_node(^"ReviewOverlay") as CanvasLayer
	assert_gt(layer.layer, (tour.get(&"hud") as CanvasLayer).layer)
	assert_gt(layer.layer, 100)
	for c in layer.find_children("*", "Control", true, false):
		assert_eq((c as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % c.name)


## Headless builds have no window input callback (Input.parse_input_event never reaches the GUI)
## and a 64×64 root viewport, so the tour runs in a 1600×900 SubViewport and its own press/release
## events are pushed to it. This checks that the tour's coordinates land on the real controls
## (the recording exercises Input.parse_input_event itself).
func test_tour_click_events_hit_the_real_controls() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	add_child_autofree(vp)
	var tour: Node = TourScene.instantiate()
	tour.set(&"autorun", false)
	vp.add_child(tour)
	await wait_process_frames(3)
	Session.set_mode(SessionState.Mode.UNIVERSE)
	await wait_process_frames(2)
	_click(vp, tour, &"tab_forge")
	await wait_process_frames(1)
	assert_eq(Session.mode, SessionState.Mode.FORGE, "a click at the FORGE tab centre switches mode")
	await wait_seconds(0.5)  # the UNIVERSE panel fades out (Palette.T_FAST) before the FORGE rows are free
	_click(vp, tour, &"row_layer_iii")
	await wait_process_frames(1)
	assert_eq(Session.selected, &"layer_2", "a click at the LAYER III row selects it")
	await wait_seconds(0.8)  # the inspector fades in (Palette.T_BASE)
	watch_signals(Session)
	_click(vp, tour, &"focus")
	await wait_process_frames(1)
	assert_signal_emitted_with_parameters(Session, "focus_requested", [&"layer_2"])
	_click(vp, tour, &"start")
	await wait_process_frames(2)
	assert_eq(Simulation.status, EventTimeline.Status.PLAYING, "a click at START starts the demo")
	_click(vp, tour, &"pause")
	await wait_process_frames(1)
	assert_eq(Simulation.status, EventTimeline.Status.PAUSED, "a click at PAUSE pauses it")


func _click(vp: SubViewport, tour: Node, id: StringName) -> void:
	var p: Vector2 = tour.call(&"target_point", id)
	vp.push_input(tour.call(&"_button_event", p, true))
	vp.push_input(tour.call(&"_button_event", p, false))
