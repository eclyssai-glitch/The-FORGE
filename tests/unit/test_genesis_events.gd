extends GutTest
## Owner: game-engineer (Loop 4). GENESIS scenario: script invariants, GenesisState reduction,
## seek/derive consistency, mission, entity catalog and the Scenario registry.

var events: Array[SimEvent]


func before_each() -> void:
	events = GenesisScript.build()


func test_script_is_sorted_unique_and_within_duration() -> void:
	var ids := {}
	var last := -1.0
	for e in events:
		assert_true(e.time >= last, "event %s out of order" % e.id)
		assert_between(e.time, 0.0, GenesisScript.DURATION, "event %s inside the session" % e.id)
		last = e.time
		assert_false(ids.has(e.id), "duplicate id %s" % e.id)
		ids[e.id] = true
	assert_eq(events[0].type, SimEvent.SESSION_OPENED)
	assert_eq(events[0].time, 0.0)
	assert_eq(events[-1].type, SimEvent.SESSION_COMPLETED)
	assert_eq(events[-1].time, GenesisScript.DURATION)
	assert_eq(EventTimeline.new(events).duration, GenesisScript.DURATION)


func test_script_is_deterministic() -> void:
	var again := GenesisScript.build()
	assert_eq(again.size(), events.size())
	for i in events.size():
		assert_eq(again[i].id, events[i].id)
		assert_eq(again[i].time, events[i].time)
		assert_eq(again[i].type, events[i].type)
		assert_eq(again[i].label, events[i].label)
		assert_eq(again[i].detail, events[i].detail)
		assert_eq(again[i].entity, events[i].entity)
		assert_eq(again[i].payload, events[i].payload)


func test_script_uses_only_genesis_types_and_covers_all() -> void:
	var seen := {}
	for e in events:
		assert_has(SimEvent.GENESIS_TYPES, e.type, "unknown type %s" % e.type)
		seen[e.type] = true
	for t in SimEvent.GENESIS_TYPES:
		assert_true(seen.has(t), "type %s never scripted" % t)


func test_script_follows_the_contract_sequence() -> void:
	var order: Array[StringName] = [
		SimEvent.SESSION_OPENED, SimEvent.MIKU_AWAKEN, SimEvent.HANDS_SUMMONED, SimEvent.DUST_GATHERED,
		SimEvent.PLANET_SEEDED, SimEvent.PLANET_LAYER, SimEvent.PLANET_LAYER, SimEvent.PLANET_LAYER,
		SimEvent.MOON_FORMED, SimEvent.MOON_FORMED, SimEvent.RING_FORMED, SimEvent.BELT_FORMED,
		SimEvent.LINKS_WOVEN, SimEvent.PLANET_STABLE, SimEvent.SESSION_COMPLETED,
	]
	var types: Array[StringName] = []
	for e in events:
		types.append(e.type)
	assert_eq(types, order)


func test_payloads_follow_the_contract() -> void:
	var layers := []
	var moons := []
	for e in events:
		match e.type:
			SimEvent.PLANET_LAYER:
				layers.append(e.payload["layer"])
			SimEvent.MOON_FORMED:
				moons.append(e.payload["index"])
				assert_eq(e.payload["name"], GenesisScript.MOON_NAMES[e.payload["index"]])
				assert_eq(e.entity, GenesisScript.moon_entity(e.payload["index"]))
			SimEvent.PLANET_STABLE, SimEvent.PLANET_SEEDED:
				assert_eq(e.payload["name"], GenesisScript.PLANET_NAME)
			SimEvent.LINKS_WOVEN:
				assert_eq(e.payload["count"], GenesisScript.LINKS.size())
		assert_true(e.payload.is_read_only())
	assert_eq(layers, range(GenesisScript.LAYER_COUNT))
	assert_eq(moons, range(GenesisScript.MOON_COUNT))


func test_pacing_is_contemplative() -> void:
	# Breathing room: no two consecutive steps closer than 2.5 s, and roughly 56 s in total.
	for i in range(1, events.size()):
		assert_gte(events[i].time - events[i - 1].time, 2.5, "%s follows %s too closely" % [events[i].id, events[i - 1].id])
	assert_between(GenesisScript.DURATION, 50.0, 62.0)


func test_labels_are_short_uppercase_and_text_is_fictional() -> void:
	var forbidden := ["api", "http", "openai", "anthropic", "claude", "gpt", "korium", "server", "provider",
		"online", "connect", "network", "cloud", "login", "account"]
	for e in events:
		assert_eq(e.label, e.label.to_upper(), "label of %s is uppercase" % e.id)
		assert_lte(e.label.length(), 24, "label of %s is short" % e.id)
		assert_false(e.detail.is_empty(), "%s has a factual detail" % e.id)
		var text := (e.label + " " + e.detail).to_lower()
		for word in forbidden:
			assert_false(text.contains(word), "event %s mentions '%s'" % [e.id, word])
	for id in GenesisCatalog.all_ids():
		var row := GenesisCatalog.info(id)
		var text := (String(row["title"]) + " " + String(row["summary"])).to_lower()
		for word in forbidden:
			assert_false(text.contains(word), "entity %s mentions '%s'" % [id, word])


func test_every_event_is_applied_and_state_completes() -> void:
	var g := GenesisState.new()
	assert_eq(g.phase, GenesisState.Phase.STILL)
	assert_eq(g.phase_index(), 0)
	for e in events:
		assert_true(g.apply(e), "genesis ignored %s" % e.type)
	assert_eq(g.phase, GenesisState.Phase.COMPLETE)
	assert_eq(g.phase_name(), "COMPLETE")
	assert_true(g.is_complete())
	assert_eq(g.layers_formed(), GenesisScript.LAYER_COUNT)
	assert_eq(g.moons_formed(), GenesisScript.MOON_COUNT)
	assert_eq(g.planet_name, GenesisScript.PLANET_NAME)
	assert_eq(g.moon_names, PackedStringArray(GenesisScript.MOON_NAMES))
	assert_eq(g.link_count, GenesisScript.LINKS.size())
	for f in [g.session_at, g.awaken_at, g.hands_at, g.dust_at, g.seeded_at, g.ring_at, g.belt_at,
			g.links_at, g.stable_at, g.completed_at]:
		assert_gte(f, 0.0)
	assert_eq(g.planet_layer_times[2], GenesisScript.LAYER_TIMES[2])
	assert_eq(g.moon_times[1], GenesisScript.MOON_TIMES[1])


func test_fresh_state_has_nothing_happened() -> void:
	var g := GenesisState.new()
	for f in [g.session_at, g.awaken_at, g.hands_at, g.dust_at, g.seeded_at, g.ring_at, g.belt_at,
			g.links_at, g.stable_at, g.completed_at]:
		assert_eq(f, -1.0)
	assert_eq(g.planet_layer_times.size(), 3)
	assert_eq(g.moon_times.size(), 2)
	assert_eq(Array(g.planet_layer_times), [-1.0, -1.0, -1.0])
	assert_eq(Array(g.moon_times), [-1.0, -1.0])
	assert_eq(g.layer_at(7), -1.0)
	assert_eq(g.moon_at(-1), -1.0)
	assert_false(g.is_complete())


func test_phases_advance_in_order() -> void:
	var g := GenesisState.new()
	var last := 0
	for e in events:
		g.apply(e)
		assert_gte(g.phase_index(), last, "phase never goes back (%s)" % e.id)
		last = g.phase_index()
	assert_eq(GenesisState.PHASE_NAMES.size(), GenesisState.Phase.size())


func test_seek_derive_equals_sequential_apply_at_many_times() -> void:
	for t in [0.1, 2.9, 3.0, 12.0, 18.0, 24.5, 32.0, 38.0, 44.0, 49.9, 53.0, 55.0, GenesisScript.DURATION]:
		var tl := EventTimeline.new(events)
		tl.start()
		var incremental := GenesisState.new()
		var steps := int(round(t / 0.1))
		for i in steps:
			for e in tl.advance(0.1):
				incremental.apply(e)
		var derived := GenesisState.derive(EventTimeline.new(events).seek(tl.playhead))
		_assert_same_state(derived, incremental, "t=%.1f" % t)


func test_seek_backwards_leaves_no_future_state() -> void:
	var tl := EventTimeline.new(events)
	GenesisState.derive(tl.seek(tl.duration))
	var g := GenesisState.derive(tl.seek(28.0))
	assert_eq(g.layers_formed(), 2)
	assert_eq(g.moons_formed(), 0)
	assert_eq(g.ring_at, -1.0)
	assert_eq(g.stable_at, -1.0)
	assert_eq(g.completed_at, -1.0)
	assert_eq(g.phase, GenesisState.Phase.FORMING)


func test_ignores_unknown_and_out_of_range_events() -> void:
	var g := GenesisState.new()
	assert_false(g.apply(SimEvent.new(&"x", 0.0, &"not.a.type", "", "")))
	assert_false(g.apply(SimEvent.new(&"y", 0.0, SimEvent.PLANET_LAYER, "", "", &"", {"layer": 3})))
	assert_false(g.apply(SimEvent.new(&"z", 0.0, SimEvent.MOON_FORMED, "", "", &"", {"index": 2})))
	assert_false(g.apply(SimEvent.new(&"w", 0.0, SimEvent.CORE_ONLINE, "", "")), "ORIGIN types are not GENESIS")
	assert_eq(g.layers_formed(), 0)
	assert_eq(g.moons_formed(), 0)
	assert_push_warning_count(4)


func test_progress_helpers_are_smooth_and_bounded() -> void:
	assert_eq(GenesisState.progress(-1.0, 10.0, 2.0), 0.0, "not happened")
	assert_eq(GenesisState.progress(5.0, 4.0, 2.0), 0.0, "before the event")
	assert_eq(GenesisState.progress(5.0, 5.0, 2.0), 0.0)
	assert_almost_eq(GenesisState.progress(5.0, 6.0, 2.0), 0.5, 1e-6)
	assert_eq(GenesisState.progress(5.0, 9.0, 2.0), 1.0)
	assert_eq(GenesisState.progress(5.0, 5.0, 0.0), 1.0, "zero ramp is a step")
	assert_eq(GenesisState.since(-1.0, 3.0), -1.0)
	assert_eq(GenesisState.since(2.0, 3.5), 1.5)
	var g := GenesisState.derive(events)
	var last := 0.0
	var t := 0.0
	while t <= GenesisScript.DURATION + 3.0:
		var f := g.formation(t, 2.0)
		assert_between(f, 0.0, 1.0)
		assert_gte(f, last - 1e-9, "formation is monotonic (t=%.2f)" % t)
		last = f
		t += 0.25
	assert_eq(g.formation(GenesisScript.T_SEEDED - 0.1, 2.0), 0.0)
	assert_eq(g.formation(GenesisScript.T_STABLE + 2.0, 2.0), 1.0)
	assert_lt(g.formation(GenesisScript.T_STABLE - 0.1, 2.0), 1.0, "only a stable world is fully formed")
	assert_eq(g.layer_progress(0, GenesisScript.LAYER_TIMES[0] + 5.0, 2.0), 1.0)
	assert_eq(g.moon_progress(1, GenesisScript.MOON_TIMES[1] - 0.5, 2.0), 0.0)


func test_mission_tracks_events_and_completes_at_the_end() -> void:
	var tl := EventTimeline.new(events)
	var none := Mission.evaluate(tl.seek(0.5), Scenario.GENESIS)
	assert_eq(none.size(), Mission.GENESIS_OBJECTIVES.size())
	assert_eq(Mission.completed_count(none), 0)
	var mid := Mission.evaluate(tl.seek(30.0), Scenario.GENESIS)
	assert_eq(Mission.completed_count(mid), 4, "awaken, hands, dust, seed done at t=30 (layers 2/3)")
	var all := Mission.evaluate(tl.seek(tl.duration), Scenario.GENESIS)
	assert_eq(Mission.completed_count(all), all.size())
	assert_eq(Mission.title_for(Scenario.GENESIS), Mission.GENESIS_TITLE)
	assert_eq(Mission.objectives_for(Scenario.ORIGIN_CHAMBER), Mission.ORIGIN_CHAMBER_OBJECTIVES)
	for o in Mission.GENESIS_OBJECTIVES:
		assert_has(SimEvent.GENESIS_TYPES, o["done_on"])


func test_catalog_covers_contract_ids_and_every_event_entity() -> void:
	var contract: Array[StringName] = [&"miku", &"hand_left", &"hand_right", &"planet_forming", &"moon_0",
		&"moon_1", &"ring_skill", &"belt_memory", &"planet_far_0", &"planet_far_1", &"relations"]
	assert_eq(GenesisCatalog.all_ids(), contract)
	for id in contract:
		var row := GenesisCatalog.info(id)
		assert_false(row.is_empty(), "missing info for %s" % id)
		assert_eq(row["id"], id)
		for key in ["title", "kind_name", "body", "summary"]:
			assert_false(String(row[key]).is_empty(), "%s.%s" % [id, key])
	for e in events:
		assert_has(contract, e.entity, "event %s names a catalog entity" % e.id)
		for h in e.payload.get("hands", []):
			assert_has(contract, h)
	for link in GenesisScript.LINKS:
		assert_has(contract, link[0])
		assert_has(contract, link[1])
	assert_true(GenesisCatalog.info(&"nope").is_empty())
	assert_eq(GenesisCatalog.status(&"nope", GenesisState.new()), "UNKNOWN")


func test_catalog_symbolism() -> void:
	assert_eq(GenesisCatalog.info(&"planet_forming")["kind"], GenesisCatalog.Kind.SUBAGENT)
	assert_eq(GenesisCatalog.info(&"planet_far_1")["kind"], GenesisCatalog.Kind.SUBAGENT)
	assert_eq(GenesisCatalog.info(&"moon_0")["kind"], GenesisCatalog.Kind.DOCUMENTATION)
	assert_eq(GenesisCatalog.info(&"ring_skill")["kind"], GenesisCatalog.Kind.SKILL)
	assert_eq(GenesisCatalog.info(&"belt_memory")["kind"], GenesisCatalog.Kind.MEMORY)
	assert_eq(GenesisCatalog.info(&"relations")["kind"], GenesisCatalog.Kind.RELATION)
	assert_eq(GenesisCatalog.KIND_NAMES.size(), GenesisCatalog.Kind.size())


func test_catalog_statuses_progress_with_the_state() -> void:
	var tl := EventTimeline.new(events)
	var g0 := GenesisState.derive(tl.seek(0.0))
	assert_eq(GenesisCatalog.status(&"miku", g0), "ASLEEP")
	assert_eq(GenesisCatalog.status(&"hand_left", g0), "IN THE MIST")
	assert_eq(GenesisCatalog.status(&"planet_forming", g0), "UNFORMED")
	assert_eq(GenesisCatalog.status(&"relations", g0), "UNWOVEN")
	var g1 := GenesisState.derive(tl.seek(28.0))
	assert_eq(GenesisCatalog.status(&"miku", g1), "CONDUCTING")
	assert_eq(GenesisCatalog.status(&"hand_right", g1), "SHAPING")
	assert_eq(GenesisCatalog.status(&"planet_forming", g1), "CRUST · 2/3")
	assert_eq(GenesisCatalog.status(&"moon_0", g1), "UNFORMED")
	var g2 := GenesisState.derive(tl.seek(tl.duration))
	assert_eq(GenesisCatalog.status(&"miku", g2), "SERENE")
	assert_eq(GenesisCatalog.status(&"planet_forming", g2), "STABLE")
	assert_eq(GenesisCatalog.status(&"moon_1", g2), "LINKED")
	assert_eq(GenesisCatalog.status(&"ring_skill", g2), "%d SKILLS" % GenesisScript.SKILLS.size())
	assert_eq(GenesisCatalog.status(&"planet_far_0", g2), "LINKED")
	assert_eq(GenesisCatalog.status(&"relations", g2), "%d THREADS" % GenesisScript.LINKS.size())
	for id in GenesisCatalog.all_ids():
		assert_ne(GenesisCatalog.status(id, g2), "UNKNOWN", id)


func test_scenario_registry() -> void:
	assert_eq(Scenario.IDS.size(), 2)
	assert_eq(Scenario.IDS[0], Scenario.ORIGIN_CHAMBER)
	assert_eq(Scenario.IDS[1], Scenario.GENESIS)
	assert_eq(Scenario.DEFAULT, Scenario.ORIGIN_CHAMBER)
	assert_true(Scenario.is_valid(&"genesis"))
	assert_false(Scenario.is_valid(&"nope"))
	assert_eq(Scenario.build_events(&"nope").size(), 0)
	assert_eq(Scenario.build_events(Scenario.GENESIS).size(), events.size())
	assert_true(Scenario.new_state(Scenario.GENESIS) is GenesisState)
	assert_true(Scenario.new_state(Scenario.ORIGIN_CHAMBER) is WorldState)
	assert_true(Scenario.derive(Scenario.GENESIS, events).is_complete())
	assert_true(Scenario.derive(Scenario.ORIGIN_CHAMBER, OriginChamberScript.build()).is_complete())
	assert_eq(Scenario.types(Scenario.GENESIS), SimEvent.GENESIS_TYPES)
	assert_eq(Scenario.entity_ids(Scenario.GENESIS), GenesisCatalog.all_ids())
	assert_eq(Scenario.entity_ids(Scenario.ORIGIN_CHAMBER), EntityCatalog.all_ids())
	assert_eq(Scenario.entity_info(Scenario.GENESIS, &"miku")["title"], "MIKU")
	var g := Scenario.derive(Scenario.GENESIS, events)
	assert_eq(Scenario.entity_status(Scenario.GENESIS, &"planet_forming", g), "STABLE")
	assert_eq(Scenario.entity_status(Scenario.ORIGIN_CHAMBER, &"origin_core", g), "UNKNOWN", "state mismatch")


func _assert_same_state(a: GenesisState, b: GenesisState, ctx: String) -> void:
	assert_eq(a.phase, b.phase, ctx)
	assert_eq(a.session_at, b.session_at, ctx)
	assert_eq(a.awaken_at, b.awaken_at, ctx)
	assert_eq(a.hands_at, b.hands_at, ctx)
	assert_eq(a.dust_at, b.dust_at, ctx)
	assert_eq(a.seeded_at, b.seeded_at, ctx)
	assert_eq(a.planet_layer_times, b.planet_layer_times, ctx)
	assert_eq(a.moon_times, b.moon_times, ctx)
	assert_eq(a.moon_names, b.moon_names, ctx)
	assert_eq(a.ring_at, b.ring_at, ctx)
	assert_eq(a.belt_at, b.belt_at, ctx)
	assert_eq(a.links_at, b.links_at, ctx)
	assert_eq(a.link_count, b.link_count, ctx)
	assert_eq(a.stable_at, b.stable_at, ctx)
	assert_eq(a.planet_name, b.planet_name, ctx)
	assert_eq(a.completed_at, b.completed_at, ctx)
