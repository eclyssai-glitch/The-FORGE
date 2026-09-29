extends GutTest
## Autoload behaviour: Simulation playback API, Quality session override, CLI parsing.

const MainScript := preload("res://src/core/main.gd")


func after_each() -> void:
	Simulation.set_scenario(Scenario.DEFAULT)
	Simulation.reset()
	Simulation.set_speed(1.0)


func test_default_scenario_is_origin_chamber() -> void:
	assert_eq(Simulation.scenario, Scenario.ORIGIN_CHAMBER)
	assert_eq(Simulation.SCENARIOS, Scenario.IDS)
	assert_eq(Simulation.state, Simulation.world)
	assert_not_null(Simulation.genesis)
	assert_eq(Simulation.genesis.phase, GenesisState.Phase.STILL, "inactive scenario rests")
	assert_eq(Simulation.duration(), OriginChamberScript.build()[-1].time)


func test_set_scenario_swaps_timeline_and_world() -> void:
	Simulation.set_speed(2.0)
	Simulation.seek(20.0)
	watch_signals(Simulation)
	assert_true(Simulation.set_scenario(Scenario.GENESIS))
	assert_signal_emitted_with_parameters(Simulation, "scenario_changed", [Scenario.GENESIS])
	assert_signal_emitted(Simulation, "world_rebuilt")
	assert_signal_emitted(Simulation, "playback_changed")
	assert_eq(Simulation.scenario, Scenario.GENESIS)
	assert_eq(Simulation.state, Simulation.genesis)
	assert_eq(Simulation.world.phase, WorldState.Phase.DORMANT, "ORIGIN state rests while GENESIS plays")
	assert_eq(Simulation.time, 0.0)
	assert_eq(Simulation.status, EventTimeline.Status.IDLE)
	assert_eq(Simulation.duration(), GenesisScript.DURATION)
	assert_eq(Simulation.emitted_events().size(), 0)
	assert_eq(Simulation.timeline.speed, 2.0, "playback speed survives the switch")
	# Selecting the active scenario again is a no-op.
	Simulation.seek(10.0)
	assert_true(Simulation.set_scenario(Scenario.GENESIS))
	assert_eq(Simulation.time, 10.0)
	assert_signal_emit_count(Simulation, "scenario_changed", 1)
	# Unknown ids change nothing.
	assert_false(Simulation.set_scenario(&"nope"))
	assert_eq(Simulation.scenario, Scenario.GENESIS)
	assert_push_warning_count(1)
	# And back.
	assert_true(Simulation.set_scenario(Scenario.ORIGIN_CHAMBER))
	assert_eq(Simulation.state, Simulation.world)
	assert_eq(Simulation.genesis.phase, GenesisState.Phase.STILL)
	assert_eq(Simulation.duration(), OriginChamberScript.build()[-1].time)


func test_genesis_playback_seek_and_reset_are_consistent() -> void:
	Simulation.set_scenario(Scenario.GENESIS)
	var received: Array[SimEvent] = []
	var on_event := func(e: SimEvent) -> void: received.append(e)
	Simulation.event_emitted.connect(on_event)
	Simulation.start()
	for i in 300:
		Simulation._process(0.1)
	assert_almost_eq(Simulation.time, 30.0, 1e-6)
	var live := Simulation.genesis
	assert_eq(live.layers_formed(), 2)
	Simulation.seek(Simulation.time)
	var derived := Simulation.genesis
	assert_ne(derived, live, "seek rebuilds the state")
	assert_eq(derived.phase, live.phase)
	assert_eq(derived.planet_layer_times, live.planet_layer_times)
	assert_eq(derived.seeded_at, live.seeded_at)
	assert_eq(Simulation.emitted_events().size(), received.size())
	Simulation.seek(12.0)
	assert_eq(Simulation.genesis.phase, GenesisState.Phase.SUMMONING)
	assert_eq(Simulation.genesis.dust_at, -1.0)
	Simulation.start()
	for i in 600:
		Simulation._process(0.1)
	assert_eq(Simulation.status, EventTimeline.Status.COMPLETE)
	assert_true(Simulation.state.is_complete())
	assert_eq(Simulation.state.phase_name(), "COMPLETE")
	assert_eq(Simulation.world.phase, WorldState.Phase.DORMANT, "GENESIS events never reach the ORIGIN state")
	var mission := Mission.evaluate(Simulation.emitted_events(), Simulation.scenario)
	assert_eq(Mission.completed_count(mission), mission.size())
	Simulation.reset()
	assert_eq(Simulation.time, 0.0)
	assert_eq(Simulation.state.phase_index(), 0)
	assert_eq(Simulation.scenario, Scenario.GENESIS, "reset keeps the scenario")
	assert_eq(Simulation.state, Simulation.genesis)
	Simulation.event_emitted.disconnect(on_event)


func test_simulation_start_pause_reset_and_seek() -> void:
	var events: Array[SimEvent] = []
	var on_event := func(e: SimEvent) -> void: events.append(e)
	Simulation.event_emitted.connect(on_event)
	Simulation.start()
	assert_eq(Simulation.status, EventTimeline.Status.PLAYING)
	Simulation._process(5.0)
	assert_gt(events.size(), 0, "events emitted while playing")
	Simulation.pause()
	var t := Simulation.time
	Simulation._process(5.0)
	assert_eq(Simulation.time, t, "paused simulation does not advance")
	Simulation.seek(30.0)
	assert_eq(Simulation.world.layers_built(), OriginChamberScript.LAYER_COUNT)
	assert_eq(Simulation.world.phase, WorldState.Phase.FINISHING)
	Simulation.reset()
	assert_eq(Simulation.time, 0.0)
	assert_eq(Simulation.world.phase, WorldState.Phase.DORMANT)
	Simulation.event_emitted.disconnect(on_event)


func test_simulation_start_after_complete_restarts() -> void:
	Simulation.seek(Simulation.duration())
	assert_eq(Simulation.status, EventTimeline.Status.COMPLETE)
	Simulation.start()
	assert_eq(Simulation.status, EventTimeline.Status.PLAYING)
	assert_eq(Simulation.time, 0.0)


func test_simulation_speed_is_clamped() -> void:
	Simulation.set_speed(100.0)
	assert_eq(Simulation.timeline.speed, 8.0)
	Simulation.set_speed(-3.0)
	assert_eq(Simulation.timeline.speed, 0.25)


func test_quality_session_override_is_not_persisted() -> void:
	var before := FileAccess.get_file_as_string(Quality.SETTINGS_PATH)
	var prev_level := Quality.level
	var prev_auto := Quality.auto
	Quality.override_for_session(QualityProfiles.Level.ULTRA)
	assert_eq(Quality.profile["name"], "ULTRA")
	assert_eq(FileAccess.get_file_as_string(Quality.SETTINGS_PATH), before, "settings file untouched")
	Quality.auto = prev_auto
	Quality.override_for_session(prev_level)
	Quality.auto = prev_auto


func test_auto_threshold_respects_refresh_rate() -> void:
	assert_eq(QualityProfiles.auto_min_fps(60.0), QualityProfiles.AUTO_MIN_FPS)
	assert_almost_eq(QualityProfiles.auto_min_fps(30.0), 22.5, 0.001)
	assert_eq(QualityProfiles.auto_min_fps(-1.0), QualityProfiles.AUTO_MIN_FPS)


func test_session_mode_and_selection_signals() -> void:
	watch_signals(Session)
	var prev := Session.mode
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	Session.select(&"origin_core")
	Session.select(&"origin_core")
	assert_signal_emit_count(Session, "mode_changed", 1)
	assert_signal_emit_count(Session, "selection_changed", 1)
	Session.set_mode(prev)
	Session.select(&"")


func test_parse_args() -> void:
	var a := MainScript._parse_args(PackedStringArray(["--smoke-test", "--capture=docs/x", "--quality=high", "--scenario=genesis", "stray"]))
	assert_eq(a["smoke-test"], true)
	assert_eq(a["scenario"], "genesis")
	assert_eq(a["capture"], "docs/x")
	assert_eq(a["quality"], "high")
	assert_false(a.has("stray"))


func test_catalog_rejects_malformed_layer_ids() -> void:
	assert_eq(EntityCatalog.layer_index(&"layer_2"), 2)
	assert_eq(EntityCatalog.layer_index(&"layer_"), -1)
	assert_eq(EntityCatalog.layer_index(&"layer_abc"), -1)
	assert_eq(EntityCatalog.layer_index(&"layer_99"), -1)
	assert_true(EntityCatalog.info(&"layer_abc").is_empty())
