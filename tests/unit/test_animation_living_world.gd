extends GutTest
## Loop 5 — the work world in stages (WorldBuild), the work plan (WorkPlan) and the action
## scripts (ActionScript): built by work only, deliberate failure, dismantling, causal order.


func test_world_is_never_built_by_time() -> void:
	var b := WorldBuild.new()
	b.begin(WorldBuild.Stage.GATHER)
	for i in 100:
		b.cool(0.1)
	assert_eq(b.progress(), 0.0, "only the hands' work builds it")


func test_stages_in_order() -> void:
	var b := WorldBuild.new()
	b.begin(WorldBuild.Stage.GATHER)
	assert_true(b.work(1.0))
	b.begin(WorldBuild.Stage.CORE)
	assert_false(b.work(0.5))
	assert_true(b.work(0.6))
	b.begin(WorldBuild.Stage.LAYERS)
	assert_eq(b.current_layer(), 0)
	b.work(1.0)
	assert_eq(b.current_layer(), 1, "layers inner to outer")
	b.work(1.0)
	assert_true(b.work(1.0))
	b.begin(WorldBuild.Stage.ADJUST)
	b.work(1.0)
	assert_true(b.is_stable())
	assert_almost_eq(b.progress(), 1.0, 1e-6)
	assert_eq(b.history, [&"stage:gather", &"stage:core", &"stage:layers", &"stage:adjust", &"stage:stable"] as Array[StringName])


func _built() -> WorldBuild:
	var b := WorldBuild.new()
	for s in [WorldBuild.Stage.GATHER, WorldBuild.Stage.CORE, WorldBuild.Stage.LAYERS]:
		b.begin(s)
		for i in 4:
			b.work(1.0)
	return b


func test_broken_world_takes_no_building() -> void:
	var b := _built()
	b.layers[2] = 0.5
	b.fault(&"crack", 0.6)
	assert_true(b.is_broken())
	b.work(1.0)
	assert_eq(b.layers[2], 0.5, "a cracked world must be mended or torn down first")


func test_repair_closes_cracks_but_not_collapse() -> void:
	var b := _built()
	b.fault(&"crack", 0.5)
	assert_true(b.repair(0.6))
	b.fault(&"collapse", 0.5)
	assert_false(b.repair(1.0), "a collapse stays")
	assert_true(b.is_broken())


func test_dismantle_outer_first_and_floor() -> void:
	var b := _built()
	b.fault(&"collapse", 0.6)
	assert_false(b.dismantle(0.5, WorldBuild.LAYER_COUNT - 1))
	assert_almost_eq(b.layers[2], 0.5, 1e-6)
	assert_eq(b.layers[1], 1.0, "only the faulty sky is torn down")
	assert_true(b.dismantle(1.0, WorldBuild.LAYER_COUNT - 1))
	assert_eq(b.layers[2], 0.0)
	assert_eq(b.layers[1], 1.0)
	assert_false(b.is_broken(), "the faults went with the torn matter")
	assert_true(b.dismantle(9.0))
	assert_eq(b.core, 0.0, "a full tear-down returns everything to the cloud")


# ---------------------------------------------------------------- scripts


func _ops(beats: Array[Dictionary]) -> Array[StringName]:
	var sorted := beats.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var out: Array[StringName] = []
	for x in sorted:
		out.append(x["op"])
	return out


func _first(beats: Array[Dictionary], op: StringName, key := "", value: Variant = null) -> float:
	var t := INF
	for x in beats:
		if x["op"] == op and (key == "" or x.get(key) == value):
			t = minf(t, float(x["t"]))
	return t


func test_every_action_has_beats_that_end() -> void:
	for a in ActionScript.VOCABULARY:
		var beats := ActionScript.beats(a, {"world": &"world_calyx"})
		assert_false(beats.is_empty(), String(a))
		for x in beats:
			assert_true(ActionScript.OPS.has(x["op"]), "%s: op %s documented" % [a, x["op"]])
		if a != ActionScript.WORK:
			assert_true(_ops(beats).has(&"done"), "%s ends" % a)


func test_summon_causal_order() -> void:
	# intention -> anticipation -> gesture -> thread -> pull -> hand.
	var b := ActionScript.summon_beats(2, false)
	var windup := _first(b, &"arm", "g", Gestures.WINDUP)
	var call := _first(b, &"arm", "g", Gestures.CALL)
	var cast := _first(b, &"cast")
	var pull := _first(b, &"pull")
	var send := _first(b, &"send")
	assert_lt(windup, call, "anticipation before the gesture")
	assert_lt(call, cast, "the gesture casts the thread")
	assert_lt(cast, pull, "the thread is pulled after it is cast")
	assert_lte(pull, send, "the hand is sent only when pulled")


func test_stage_causal_order() -> void:
	var b := WorkPlan.stage_beats(WorldBuild.Stage.CORE, &"world_calyx", false)
	assert_lt(_first(b, &"arm", "g", Gestures.WINDUP), _first(b, &"cast"))
	assert_lt(_first(b, &"cast"), _first(b, &"pull"))
	assert_lt(_first(b, &"pull"), _first(b, &"work"), "matter answers only after the hands are pulled")
	assert_true(_ops(b).has(&"wait"), "it waits for the hands to arrive and the stage to finish")


func test_failure_perception_comes_after_the_cause() -> void:
	var b := WorkPlan.failure_beats(&"w")
	var fault := _first(b, &"fault")
	var look := _first(b, &"gaze", "at", &"crack")
	assert_gt(look, fault, "she sees it a beat after it happens (overlap, no same-frame reaction)")
	var faults := 0
	for x in b:
		if x["op"] == &"fault" and float(x.get("severity", 0.0)) > 0.0:
			faults += 1
	assert_eq(faults, 3, "crack, the fix does not hold, collapse")
	assert_true(_ops(b).has(&"dismantle"))
	var summons := b.filter(func(x: Dictionary) -> bool: return x["op"] == &"summon")
	assert_eq(int(summons[0]["n"]), 6, "many hands when the composure is lost")


func test_event_steps_map_the_roteiro() -> void:
	assert_eq(WorkPlan.EVENT_STEPS.size(), 5, "GATHER, COMPRESS, MANTLE, CRUST, SKY")
	var sky := WorkPlan.step_beats(4, 1, 2, &"w", false)
	assert_true(_ops(sky).has(&"work"))
	var retry := WorkPlan.step_beats(4, 2, 2, &"w", false)
	assert_true(_ops(retry).has(&"repair"), "attempt 2 = the elegant retry mends while it lays")
	var tear := WorkPlan.dismantle_event_beats(6, &"w")
	var d := tear.filter(func(x: Dictionary) -> bool: return x["op"] == &"dismantle")
	assert_eq(int(d[0]["down_to"]), WorldBuild.LAYER_COUNT - 1, "only the faulty sky")
	var fail2 := WorkPlan.fail_event_beats(2, &"w")
	assert_gt(_first(fail2, &"gaze", "at", &"crack"), _first(fail2, &"fault"))


func test_normalize_router_arguments() -> void:
	var w: Array[StringName] = [&"world_vesper", &"world_calyx"]
	assert_eq(ActionScript.normalize(ActionScript.POINT, {"target": "world_vesper"}, w)["world"], &"world_vesper")
	assert_eq(ActionScript.normalize(ActionScript.INSPECT, {"target": "self"}, w)["inspect"], &"self")
	assert_eq(ActionScript.normalize(ActionScript.SUMMON_HAND, {"role": "hold"}, w)["role"], &"holder")
	assert_true(ActionScript.normalize(ActionScript.DISCARD, {"applied": false}, w)["rejected"])
	assert_true(ActionScript.normalize(ActionScript.EDIT_FILE, {"path": "appearance.height"}, w)["router"])


func test_router_edit_does_not_wait_for_the_change() -> void:
	var b := ActionScript.edit_beats(false, true, true)
	assert_true(_ops(b).has(&"commit"))
	for x in b:
		assert_ne(x.get("until", &""), &"applied", "the interaction system applies after EDIT_FILE")


func test_gestures_fill_every_id() -> void:
	var g := Gestures.ArmGoal.new()
	for id in Gestures.ALL:
		Gestures.goal(id, Vector3(0.3, 1.0, 0.0), 1.1, Vector3(1, 0, 3), Basis.IDENTITY, 1.0, 0.0,
			Vector3(0, 0.4, 0), Vector3(0, 1.2, 0), g)
		if id != Gestures.FREEZE:
			assert_true(g.palm.is_normalized() and g.point.is_normalized(), String(id))
			assert_lt((g.pos - Vector3(0.3, 1.0, 0.0)).length(), 1.1 * 1.05, "%s within reach" % id)
