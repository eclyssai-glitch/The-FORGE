extends GutTest
## LIVING scenario (Loop 5): script, state, mission and registry; Simulation without seek; world
## composition (animator modules by path, LivingInteraction, GENESIS environment, reset =
## recompose); diegetic input through Session (clicks, call line, placeholder) reaching the
## InteractionRouter. The player's MIKU configuration is snapshotted and restored around each test.

const WorldScene := preload("res://scenes/world.tscn")
const WorldScript := preload("res://src/world/world.gd")
const AutomationScript := preload("res://src/core/automation.gd")

var _store: MikuConfig
var _snap: Variant


func before_each() -> void:
	_store = MikuConfig.new()
	_store.reload()
	_snap = _store.snapshot()


func after_each() -> void:
	Session.close_call_line()
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	Simulation.reset()
	Simulation.set_speed(1.0)
	Session.select(&"")
	Session.hover(&"")
	_store.restore_snapshot(_snap)
	await wait_process_frames(2)


# ------------------------------------------------------------------ pure


func test_script_is_sorted_typed_and_complete() -> void:
	var events := LivingScript.build()
	var last := -1.0
	var ids := {}
	var seen := {}
	for e in events:
		assert_true(e.time >= last, "%s in order" % e.id)
		last = e.time
		assert_false(ids.has(e.id), "unique id %s" % e.id)
		ids[e.id] = true
		assert_has(SimEvent.LIVING_TYPES, e.type)
		seen[e.type] = true
	for t in SimEvent.LIVING_TYPES:
		assert_true(seen.has(t), "%s scripted" % t)
	assert_eq(events[-1].time, LivingScript.DURATION)
	assert_eq(LivingScript.STEP_COUNT, LivingScript.STEPS.size())
	assert_eq(LivingScript.MILESTONE_COUNT, LivingScript.MILESTONE_TIMES.size())
	assert_eq(LivingScript.MILESTONE_COUNT, LivingScript.MILESTONE_NAMES.size())
	assert_eq(LivingScript.HAND_CUE_COUNT, LivingScript.HAND_CUES.size())
	assert_eq(LivingScript.FAIL_COUNT, LivingScript.FAIL_CUES.size())
	assert_eq(LivingScript.world_ids(), [&"world_vesper", &"world_calyx", &"world_orrin"] as Array[StringName])
	assert_eq(LivingScript.world(&"world_vesper")["side"], &"left")


func test_user_cues_fall_in_their_test_windows() -> void:
	var windows := {"click_miku": 5, "click_world": 6, "say": 7}
	for c: Array in LivingScript.USER_CUES:
		var t := float(c[0])
		var test := 7
		if c[1] == "click":
			test = 5 if c[2] == &"miku" else 6
			if c[2] != &"miku":
				assert_true(LivingScript.world_ids().has(StringName(c[2])), "%s is a world" % c[2])
		assert_gt(t, LivingScript.milestone_time(test), "cue %s after its milestone" % [c])
		var next := LivingScript.milestone_time(test + 1) if test < 7 else LivingScript.DURATION
		assert_lt(t, next, "cue %s before the next segment" % [c])
	assert_eq(windows.size(), 3)
	var say := LivingScript.USER_CUES.filter(func(c: Array) -> bool: return c[1] == "say")
	assert_eq(LocalParser.parse(say[0][2], LivingScript.world_directory()).kind, Intent.Kind.CONFIG_PATCH)
	assert_eq(LocalParser.parse(say[1][2], LivingScript.world_directory()).kind, Intent.Kind.SEMANTIC)


func test_state_derivation_and_mission() -> void:
	var events := LivingScript.build()
	var tl := EventTimeline.new(events)
	var s0 := LivingState.derive(tl.seek(0.2))
	assert_eq(s0.phase, LivingState.Phase.STILL)
	assert_eq(s0.phase_index(), 0)
	var s1 := LivingState.derive(tl.seek(26.0))
	assert_eq(s1.phase, LivingState.Phase.PUPPET)
	assert_eq(s1.hands, 4)
	var s2 := LivingState.derive(tl.seek(46.0))
	assert_eq(s2.phase, LivingState.Phase.WORLD_WORK)
	assert_eq(s2.step_name, "MANTLE")
	assert_eq(s2.steps_done(), 2)
	var s3 := LivingState.derive(tl.seek(69.0))
	assert_eq(s3.phase, LivingState.Phase.FAILURE)
	assert_eq(s3.failures, 2)
	assert_true(s3.is_failing())
	assert_eq(LivingCatalog.status(&"world_calyx", s3), "FAILING")
	assert_eq(LivingCatalog.status(&"miku", s3), "STRAINED")
	var s4 := LivingState.derive(tl.seek(72.0))
	assert_eq(s4.hands, LivingScript.DISMANTLE_HANDS)
	var all := LivingState.derive(tl.seek(tl.duration))
	assert_true(all.is_complete())
	assert_eq(all.phase_name(), "COMPLETE")
	assert_eq(all.steps_done(), LivingScript.STEP_COUNT)
	assert_false(all.is_failing())
	assert_eq(LivingCatalog.status(&"world_calyx", all), "WHOLE")
	assert_eq(LivingCatalog.status(&"world_orrin", all), "WAITING")
	var mission := Mission.evaluate(tl.seek(tl.duration), Scenario.LIVING)
	assert_eq(Mission.completed_count(mission), mission.size())
	assert_eq(Mission.title_for(Scenario.LIVING), Mission.LIVING_TITLE)
	var early := Mission.evaluate(tl.seek(30.0), Scenario.LIVING)
	assert_lt(Mission.completed_count(early), early.size())


func test_registry() -> void:
	assert_true(Scenario.is_valid(&"living"))
	assert_false(Scenario.supports_seek(Scenario.LIVING))
	assert_eq(Scenario.title(Scenario.LIVING), "MIKU · LIVING PROTOTYPE")
	assert_eq(Scenario.types(Scenario.LIVING), SimEvent.LIVING_TYPES)
	assert_true(Scenario.new_state(Scenario.LIVING) is LivingState)
	assert_eq(Scenario.entity_ids(Scenario.LIVING), LivingCatalog.all_ids())
	assert_eq(Scenario.entity_info(Scenario.LIVING, &"world_orrin")["title"], "ORRIN")
	assert_eq(Scenario.entity_info(Scenario.LIVING, &"nope"), {})
	var s := Scenario.derive(Scenario.LIVING, LivingScript.build())
	assert_eq(Scenario.entity_status(Scenario.LIVING, &"world_calyx", s), "WHOLE")
	assert_eq(Scenario.entity_status(Scenario.GENESIS, &"miku", s), "UNKNOWN", "state mismatch")
	assert_eq(AutomationScript.captures_for(Scenario.LIVING), AutomationScript.CAPTURES_LIVING)
	var last := 0.0
	for c: Array in AutomationScript.CAPTURES_LIVING:
		assert_gt(float(c[1]), last, "%s in time order (played, not sought)" % c[0])
		last = float(c[1])
	assert_lt(last, LivingScript.DURATION)


# ------------------------------------------------------------------ Simulation


func test_simulation_plays_living_without_seek() -> void:
	assert_true(Simulation.set_scenario(Scenario.LIVING))
	assert_eq(Simulation.state, Simulation.living)
	assert_eq(Simulation.duration(), LivingScript.DURATION)
	Simulation.start()
	for i in 700:
		Simulation._process(0.1)
	assert_almost_eq(Simulation.time, 70.0, 1e-6)
	assert_eq(Simulation.living.failures, 2)
	Simulation.pause()
	Simulation.seek(10.0)
	assert_almost_eq(Simulation.time, 70.0, 1e-6, "seek refused")
	assert_eq(Simulation.living.failures, 2, "state untouched")
	Simulation.start()
	for i in 800:
		Simulation._process(0.1)
	assert_eq(Simulation.status, EventTimeline.Status.COMPLETE)
	assert_true(Simulation.state.is_complete())
	assert_eq(Simulation.genesis.phase, GenesisState.Phase.STILL, "other states rest")
	Simulation.reset()
	assert_eq(Simulation.state.phase_index(), 0)
	assert_eq(Simulation.scenario, Scenario.LIVING)


func test_call_line_shortcut_only_in_living() -> void:
	assert_true(InputMap.has_action(&"call_line"))
	assert_false(Shortcuts.apply(&"call_line"), "not in ORIGIN")
	assert_false(Session.call_line_open)
	Simulation.set_scenario(Scenario.LIVING)
	watch_signals(Session)
	assert_true(Shortcuts.apply(&"call_line"))
	assert_true(Session.call_line_open)
	assert_signal_emitted_with_parameters(Session, "call_line_changed", [true])
	assert_false(Session.submit_call("   "), "empty only closes")
	assert_false(Session.call_line_open)
	Session.open_call_line()
	assert_true(Session.submit_call("Miku!"))
	assert_signal_emitted_with_parameters(Session, "call_submitted", ["Miku!"])
	Session.click(&"miku")
	Session.click(&"miku")
	assert_signal_emit_count(Session, "entity_clicked", 2, "every click, even on the selected entity")
	assert_eq(Session.selected, &"miku")


# ------------------------------------------------------------------ world


func test_world_composes_living_and_recomposes_on_reset() -> void:
	var world: WorldScript = WorldScene.instantiate()
	add_child_autofree(world)
	Simulation.set_scenario(Scenario.LIVING)
	assert_eq(world.scenario, Scenario.LIVING)
	var names: Array[String] = []
	for m in WorldScript.LIVING_MODULES:
		names.append(String(m[0]))
		var present := world.get_node_or_null(NodePath(m[0])) != null
		assert_eq(present, ResourceLoader.exists(m[1]), "%s present iff its script exists" % m[0])
		assert_eq(world.missing_modules().has(String(m[0])), not ResourceLoader.exists(m[1]))
	assert_eq(names, ["LivingLightRig", "Miku", "HandPool", "IntentThreads", "WorkWorld", "CausalParticles",
		"LivingInteraction"] as Array[String])
	assert_eq(WorldScript.expected_module_names(Scenario.LIVING), names + ["AudioDirector", "CameraDirector"])
	assert_true(world.uses_nebula_environment(), "GENESIS sky reused")
	assert_eq(world.environment.sky.sky_material, world.genesis_sky)
	assert_null(world.universe)
	var li := world.get_node_or_null(^"LivingInteraction") as LivingInteraction
	assert_not_null(li)
	assert_true(li.is_in_group(LivingInteraction.GROUP))
	assert_eq(li.is_bound(), ResourceLoader.exists("res://src/miku/miku.gd"), "bound iff MIKU exists")
	# Reset recomposes (fresh character); seek does nothing.
	Simulation.reset()
	var li2 := world.get_node_or_null(^"LivingInteraction")
	assert_not_null(li2)
	assert_ne(li2, li, "recomposed")
	assert_eq(world.scenario, Scenario.LIVING)
	# Back to ORIGIN: the living modules leave.
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	assert_null(world.get_node_or_null(^"LivingInteraction"))
	assert_eq(get_tree().get_nodes_in_group(LivingInteraction.GROUP).filter(
		func(n: Node) -> bool: return n.is_inside_tree()).size(), 0)


func test_diegetic_input_reaches_the_router() -> void:
	var world: WorldScript = WorldScene.instantiate()
	add_child_autofree(world)
	Simulation.set_scenario(Scenario.LIVING)
	var li := world.get_node_or_null(^"LivingInteraction") as LivingInteraction
	li.config.reset()
	li.router.set_executor(ActionExecutor.new())  # null body: plans finish at once
	var reports: Array[Dictionary] = []
	var on_report := func(r: Dictionary) -> void: reports.append(r)
	Session.interaction_reported.connect(on_report)
	Session.click(&"miku")
	Session.click(&"world_orrin")
	Session.click(&"nothing_here")
	assert_eq(reports.size(), 2)
	assert_eq(reports[0]["status"], InteractionRouter.ST_ATTENTION)
	assert_eq(reports[1]["status"], InteractionRouter.ST_WORLD)
	assert_eq(reports[1]["target"], &"world_orrin")
	# Enter -> placeholder call line (no UI node of the group) -> submit.
	assert_true(Shortcuts.apply(&"call_line"))
	assert_not_null(li.call_line, "placeholder created")
	assert_true(li.call_line.is_open())
	li.call_line.line.text = "Miku, aumente sua altura"
	li.call_line.line.text_submitted.emit(li.call_line.line.text)
	assert_false(Session.call_line_open, "submitting closes the line")
	assert_false(li.call_line.is_open())
	assert_eq(reports.size(), 3)
	assert_eq(reports[2]["status"], InteractionRouter.ST_APPLIED)
	assert_almost_eq(float(li.config.get_value("appearance.height")), 1.03, 1e-6)
	assert_true(li.config.has_user_file())
	Session.submit_call("Miku, fique mais curiosa, mas menos impulsiva")
	assert_eq(reports[3]["status"], InteractionRouter.ST_PROVIDER_UNAVAILABLE)
	Session.interaction_reported.disconnect(on_report)


func test_ui_call_line_replaces_the_placeholder() -> void:
	var world: WorldScript = WorldScene.instantiate()
	add_child_autofree(world)
	var ui := Control.new()
	ui.add_to_group(LivingInteraction.CALL_LINE_UI_GROUP)
	add_child_autofree(ui)
	Simulation.set_scenario(Scenario.LIVING)
	var li := world.get_node_or_null(^"LivingInteraction") as LivingInteraction
	Session.open_call_line()
	assert_null(li.call_line, "the UI shows the line; no placeholder")


func test_world_directory_sides_without_camera_fall_back_to_catalog() -> void:
	var li := LivingInteraction.new()
	add_child_autofree(li)
	var dir := li.world_directory()
	assert_eq(dir.size(), 3)
	assert_eq(dir[0]["side"], &"left")


func test_session_interaction_started_precedes_the_result() -> void:
	var world: WorldScript = WorldScene.instantiate()
	add_child_autofree(world)
	Simulation.set_scenario(Scenario.LIVING)
	var li := world.get_node_or_null(^"LivingInteraction") as LivingInteraction
	li.config.reset()
	var body := ActionExecutor.new()
	body.simulated_duration = 0.5  # actions take time: the result comes later
	li.router.set_executor(body)
	var log: Array = []
	var on_start := func(r: Dictionary) -> void: log.append(["started", r])
	var on_report := func(r: Dictionary) -> void: log.append(["reported", r])
	Session.interaction_started.connect(on_start)
	Session.interaction_reported.connect(on_report)
	Session.submit_call("Miku, aumente sua altura")
	assert_eq(log.size(), 1, "recognised at once, nothing finished yet")
	var st: Dictionary = log[0][1]
	assert_eq(st["status"], InteractionRouter.ST_STARTED)
	assert_eq(String(st["source"]), "text")
	assert_gt(int(st["request_id"]), 0)
	assert_eq(st["plan"].size(), 10)
	for i in 40:
		li.router.tick(0.5)
	assert_eq(log.size(), 2)
	var rep: Dictionary = log[1][1]
	assert_eq(log[1][0], "reported")
	assert_eq(rep["id"], st["id"])
	assert_eq(rep["request_id"], st["request_id"])
	assert_eq(rep["source"], st["source"])
	assert_eq(rep["status"], InteractionRouter.ST_APPLIED)
	assert_almost_eq(float(rep["estimate"]), 5.0, 1e-6)
	# Recomposition (reset) cancels the running plan on the body; nothing applied.
	Session.click(&"world_orrin")
	var rid := li.router.active_request_id()
	assert_gt(rid, int(st["request_id"]))
	Simulation.reset()
	assert_has(body.calls, [&"cancel", rid])
	assert_eq(String(log.back()[1]["status"]), InteractionRouter.ST_CANCELLED)
	Session.interaction_started.disconnect(on_start)
	Session.interaction_reported.disconnect(on_report)


func test_smoke_living_budget_is_derived() -> void:
	var world: WorldScript = WorldScene.instantiate()
	add_child_autofree(world)
	Simulation.set_scenario(Scenario.LIVING)
	var b := AutomationScript.living_budget(world)
	assert_eq((b["requests"] as Array).size(), AutomationScript.SMOKE_LIVING_REQUESTS.size())
	assert_almost_eq(float(b["roteiro"]), LivingScript.DURATION / AutomationScript.SMOKE_SPEED, 1e-6)
	assert_gt(float(b["plans"]), 0.0, "MIKU's estimates (or nominal durations)")
	assert_almost_eq(float(b["total"]), float(b["roteiro"]) + float(b["plans"]) + float(b["margin"]), 1e-6)
	assert_gt(float(b["deadline"]), float(b["total"]), "the hang guard is the worst case, above the budget")
	var sum := 0.0
	for r: Dictionary in b["requests"]:
		sum += float(r["estimate"])
		assert_gt((r["plan"] as Array).size(), 0)
	assert_almost_eq(sum, float(b["plans"]), 1e-6)
