extends GutTest
## Event script invariants, timeline playback and world reduction.

var script_events: Array[SimEvent]


func before_each() -> void:
	script_events = OriginChamberScript.build()


func test_script_is_sorted_with_unique_ids() -> void:
	var ids := {}
	var last := -1.0
	for e in script_events:
		assert_true(e.time >= last, "event %s out of order" % e.id)
		last = e.time
		assert_false(ids.has(e.id), "duplicate id %s" % e.id)
		ids[e.id] = true


func test_script_uses_only_known_types_and_covers_all() -> void:
	var seen := {}
	for e in script_events:
		assert_has(SimEvent.ALL_TYPES, e.type, "unknown type %s" % e.type)
		seen[e.type] = true
	for t in SimEvent.ALL_TYPES:
		assert_true(seen.has(t), "type %s never scripted" % t)


func test_script_follows_required_sequence() -> void:
	var order: Array[StringName] = [
		SimEvent.CORE_ACTIVATION, SimEvent.FRAGMENTS_EMITTED, SimEvent.STRUCTURE_SEEDED,
		SimEvent.LAYER_ADDED, SimEvent.MATERIALS_APPLIED, SimEvent.LIGHTING_APPLIED,
		SimEvent.VERIFICATION_STARTED, SimEvent.VERIFICATION_PASSED, SimEvent.STRUCTURE_FINALIZED,
	]
	var first_time := {}
	for e in script_events:
		if not first_time.has(e.type):
			first_time[e.type] = e.time
	for i in range(1, order.size()):
		assert_lt(first_time[order[i - 1]], first_time[order[i]], "%s before %s" % [order[i - 1], order[i]])


func test_script_has_one_layer_event_per_layer_and_all_checks() -> void:
	var layers := []
	var checks := []
	for e in script_events:
		if e.type == SimEvent.LAYER_ADDED:
			layers.append(e.payload["layer"])
		if e.type == SimEvent.CHECK_PASSED:
			checks.append(e.payload["check"])
	assert_eq(layers, range(OriginChamberScript.LAYER_COUNT))
	assert_eq(checks.size(), OriginChamberScript.CHECKS.size())


func test_every_scripted_event_is_applied_by_world() -> void:
	var w := WorldState.new()
	for e in script_events:
		assert_true(w.apply(e), "world ignored %s" % e.type)
	assert_eq(w.phase, WorldState.Phase.COMPLETE)
	assert_eq(w.layers_built(), OriginChamberScript.LAYER_COUNT)


func test_payload_is_read_only() -> void:
	var e := script_events[3]
	assert_true(e.payload.is_read_only())


func test_timeline_idle_does_not_advance() -> void:
	var tl := EventTimeline.new(script_events)
	assert_eq(tl.advance(5.0).size(), 0)
	assert_eq(tl.playhead, 0.0)
	assert_eq(tl.status, EventTimeline.Status.IDLE)


func test_timeline_start_emits_in_order_and_completes() -> void:
	var tl := EventTimeline.new(script_events)
	tl.start()
	var all: Array[SimEvent] = []
	for i in 2000:
		all.append_array(tl.advance(1.0 / 30.0))
		if tl.status == EventTimeline.Status.COMPLETE:
			break
	assert_eq(tl.status, EventTimeline.Status.COMPLETE)
	assert_eq(all.size(), script_events.size())
	for i in all.size():
		assert_eq(all[i].id, script_events[i].id)


func test_timeline_pause_freezes_and_resume_continues() -> void:
	var tl := EventTimeline.new(script_events)
	tl.start()
	tl.advance(5.0)
	tl.pause()
	var frozen := tl.playhead
	assert_eq(tl.advance(10.0).size(), 0)
	assert_eq(tl.playhead, frozen)
	tl.start()
	assert_eq(tl.status, EventTimeline.Status.PLAYING)
	tl.advance(1.0)
	assert_almost_eq(tl.playhead, frozen + 1.0, 0.0001)


func test_timeline_reset_returns_to_idle_at_zero() -> void:
	var tl := EventTimeline.new(script_events)
	tl.start()
	tl.advance(20.0)
	tl.reset()
	assert_eq(tl.status, EventTimeline.Status.IDLE)
	assert_eq(tl.playhead, 0.0)
	assert_eq(tl.cursor, 0)


func test_timeline_speed_scales_time() -> void:
	var tl := EventTimeline.new(script_events)
	tl.speed = 4.0
	tl.start()
	tl.advance(1.0)
	assert_almost_eq(tl.playhead, 4.0, 0.0001)


func test_seek_rebuilds_world_equal_to_incremental_playback() -> void:
	var tl := EventTimeline.new(script_events)
	tl.start()
	var incremental := WorldState.new()
	for i in 23 * 10:
		for e in tl.advance(0.1):
			incremental.apply(e)
	var seeker := EventTimeline.new(script_events)
	var derived := WorldState.derive(seeker.seek(tl.playhead))
	assert_eq(derived.phase, incremental.phase)
	assert_eq(derived.layers_built(), incremental.layers_built())
	assert_eq(derived.layer_times, incremental.layer_times)
	assert_eq(derived.fragments_at, incremental.fragments_at)


func test_seek_backwards_leaves_no_future_state() -> void:
	var tl := EventTimeline.new(script_events)
	WorldState.derive(tl.seek(tl.duration))
	assert_eq(tl.status, EventTimeline.Status.COMPLETE)
	var w := WorldState.derive(tl.seek(12.0))
	assert_eq(tl.status, EventTimeline.Status.PAUSED)
	assert_eq(w.layers_built(), 1)
	assert_eq(w.materials_at, -1.0)
	assert_eq(w.finalized_at, -1.0)
	assert_eq(w.phase, WorldState.Phase.BUILDING)


func test_world_ignores_unknown_and_out_of_range_events() -> void:
	var w := WorldState.new()
	assert_false(w.apply(SimEvent.new(&"x", 0.0, &"not.a.type", "", "")))
	assert_false(w.apply(SimEvent.new(&"y", 0.0, SimEvent.LAYER_ADDED, "", "", &"", {"layer": 99})))
	assert_eq(w.layers_built(), 0)
	assert_push_warning_count(2)


func test_mission_objectives_track_events() -> void:
	var tl := EventTimeline.new(script_events)
	var none := Mission.evaluate(tl.seek(0.5))
	assert_eq(Mission.completed_count(none), 0)
	var mid := Mission.evaluate(tl.seek(15.0))
	assert_eq(Mission.completed_count(mid), 3, "core, fragments, seed done at t=15")
	var all := Mission.evaluate(tl.seek(tl.duration))
	assert_eq(Mission.completed_count(all), all.size())


func test_entity_catalog_covers_every_id_and_statuses_progress() -> void:
	for id in EntityCatalog.all_ids():
		assert_false(EntityCatalog.info(id).is_empty(), "missing info for %s" % id)
	var tl := EventTimeline.new(script_events)
	var w0 := WorldState.derive(tl.seek(0.0))
	assert_eq(EntityCatalog.status(&"origin_core", w0), "DORMANT")
	assert_eq(EntityCatalog.status(&"layer_0", w0), "PENDING")
	var w1 := WorldState.derive(tl.seek(tl.duration))
	assert_eq(EntityCatalog.status(&"origin_core", w1), "ONLINE")
	assert_eq(EntityCatalog.status(&"layer_4", w1), "FINAL")
	assert_eq(EntityCatalog.status(&"verification_array", w1), "PASSED")


func test_event_text_never_mentions_real_connectivity() -> void:
	var forbidden := ["api", "http", "openai", "anthropic", "claude", "gpt", "korium", "server", "provider"]
	for e in script_events:
		var text := (e.label + " " + e.detail).to_lower()
		for word in forbidden:
			assert_false(text.contains(word), "event %s mentions '%s'" % [e.id, word])


func test_timeline_sorts_input_and_rejects_negative_speed() -> void:
	var shuffled: Array[SimEvent] = script_events.duplicate()
	shuffled.reverse()
	var tl := EventTimeline.new(shuffled)
	assert_eq(tl.events[0].id, script_events[0].id)
	assert_eq(tl.duration, script_events[-1].time)
	assert_eq(shuffled[0].id, script_events[-1].id, "caller's array is not mutated")
	tl.speed = -2.0
	assert_eq(tl.speed, 0.0)
	tl.start()
	tl.advance(1.0)
	assert_eq(tl.playhead, 0.0)
