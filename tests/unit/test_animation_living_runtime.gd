extends GutTest
## Loop 5 — the Miku runtime as the interaction system and the roteiro use it: one
## action_finished per perform, the living.* events drive the work, the user's call and pointing,
## configuration changes, the hand pool, causal particles, and life without any input.

const DT := 1.0 / 30.0

var root: Node3D
var miku: Miku
var finished: Array[StringName] = []


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	miku = Miku.new()
	root.add_child(miku)
	miku.set_process(false)
	finished.clear()
	miku.action_finished.connect(func(a: StringName) -> void: finished.append(a))
	miku.tick(DT)


func _tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		miku.tick(DT)
		t += DT


func _event(type: String, payload := {}) -> void:
	var p := payload.duplicate()
	p["world"] = &"world_calyx"
	miku.call(&"_on_sim_event", SimEvent.new(&"t", 0.0, StringName(type), type, "", &"miku", p))


func test_composes_its_world() -> void:
	assert_not_null(miku.hands)
	assert_not_null(miku.threads)
	assert_not_null(miku.worlds)
	assert_eq(miku.world_ids(), [&"world_vesper", &"world_calyx", &"world_orrin"] as Array[StringName])
	assert_true(miku.is_in_group(Miku.INSPECT_GROUP))
	assert_eq(miku.body.pick_body.get_meta(&"entity_id"), &"miku")
	assert_eq(miku.body.pick_body.collision_layer, 2)
	for id in miku.world_ids():
		assert_eq(miku.worlds.site(id).pick_body.get_meta(&"entity_id"), id)


func test_one_finished_per_perform() -> void:
	var plan: Array = [
		[ActionScript.LOOK_AT_USER, {}], [ActionScript.ACKNOWLEDGE, {"tone": "warm"}],
		[ActionScript.THINK, {"seconds": 1.0}], [ActionScript.LOOK_AT_WORLD, {"world": &"world_vesper"}],
		[ActionScript.POINT, {"target": &"world_vesper"}], [ActionScript.INSPECT, {"target": &"world_orrin"}],
		[ActionScript.SUMMON_HAND, {"side": "left", "role": "hold"}], [ActionScript.GRAB_FILE, {"file": "f"}],
		[ActionScript.SUMMON_HAND, {"side": "right", "role": "edit"}],
		[ActionScript.EDIT_FILE, {"file": "f", "path": "appearance.height", "value": 1.03}],
		[ActionScript.INSPECT, {"target": "self", "path": "appearance.height"}],
		[ActionScript.SATISFIED, {"intensity": 0.6}], [ActionScript.DISCARD, {"applied": true}],
		[ActionScript.SUMMON_HANDS, {"count": 3}], [ActionScript.FRUSTRATED, {}], [ActionScript.RECOVER, {}],
		[ActionScript.ANGRY, {}], [ActionScript.RECOVER, {}], [ActionScript.WORK, {"resume": true}],
	]
	for step: Array in plan:
		var before := finished.size()
		assert_true(miku.perform(step[0], step[1]))
		var t := 0.0
		while finished.size() == before and t < 15.0:
			miku.tick(DT)
			t += DT
		assert_eq(finished.size(), before + 1, "%s finished once (in %.1f s)" % [step[0], t])
		assert_eq(finished[finished.size() - 1], step[0])
	_tick(2.0)
	assert_eq(finished.size(), plan.size(), "no stray finished signals")


func test_unknown_action_is_refused() -> void:
	assert_false(miku.perform(&"FLY", {}))
	_tick(1.0)
	assert_true(finished.is_empty())


func test_queued_actions_each_finish() -> void:
	miku.perform(ActionScript.THINK, {"seconds": 1.0})
	miku.perform(ActionScript.ACKNOWLEDGE, {"tone": "brief"})
	miku.perform(ActionScript.POINT, {"target": &"world_orrin"})
	_tick(12.0)
	assert_eq(finished.count(ActionScript.THINK), 1)
	assert_eq(finished.count(ActionScript.ACKNOWLEDGE), 1)
	assert_eq(finished.count(ActionScript.POINT), 1)


func test_notice_user_then_plan_look_finishes_once() -> void:
	var r := miku.notice_user()
	assert_eq(r["reaction"], MikuMind.REACT_CURIOUS)
	miku.perform(ActionScript.LOOK_AT_USER, {})
	miku.perform(ActionScript.ACKNOWLEDGE, {"tone": "warm"})
	_tick(8.0)
	assert_eq(finished.count(ActionScript.LOOK_AT_USER), 1, "the plan's look joins the reaction")
	assert_eq(finished.count(ActionScript.ACKNOWLEDGE), 1, "and the acknowledgement waits for it")


func test_target_world_without_plan_starts_the_work() -> void:
	assert_true(miku.target_world(&"world_orrin"))
	assert_false(miku.target_world(&"nowhere"))
	_tick(Miku.PLAN_GRACE + 0.5)
	assert_true(miku.is_working())
	assert_eq(miku.work_world, &"world_orrin")
	_tick(6.0)
	assert_gt(miku.hands.active_count(), 0, "she summons hands for the pointed world")


func test_roteiro_events_drive_the_work() -> void:
	_event("living.work_order")
	assert_true(miku.is_working())
	assert_eq(miku.mood(), &"focused")
	_event("living.work_step", {"step": 0, "attempt": 1, "hands": 2})
	_tick(6.0)
	var b := miku.worlds.site(&"world_calyx").build
	assert_eq(b.stage, WorldBuild.Stage.GATHER)
	assert_gt(b.gather, 0.0, "the hands gathered matter")
	assert_eq(miku.hands.active_count(), 2)
	assert_gt(miku.threads.alive_count(), 0, "through threads")
	_event("living.work_step", {"step": 1, "attempt": 1, "hands": 2})
	_tick(6.0)
	assert_gt(b.core, 0.5)
	_event("living.work_failed", {"attempt": 1})
	_tick(0.5)
	assert_gt(b.crack, 0.0)
	_event("living.work_failed", {"attempt": 2})
	_tick(0.5)
	assert_eq(miku.mood(), &"angry")
	_event("living.work_dismantled", {"hands": 6})
	_tick(3.0)
	assert_eq(miku.hands.active_count(), 6, "many hands at once")
	_event("living.work_recovered")
	_tick(0.5)
	assert_eq(miku.mood(), &"recovering")


func test_config_change_reaches_the_body() -> void:
	miku.apply_config({"appearance": {"halo_radius": 1.0}})
	miku.on_config_changed("appearance.halo_radius", 1.0, 1.2)
	assert_eq(miku.params.value(&"appearance", "halo_radius"), 1.2)
	_tick(4.0)
	assert_almost_eq(miku.body.appearance("halo_radius"), 1.2, 0.02, "the halo eased to its new size")
	miku.on_config_changed("identity.patience", 0.6, 0.1)
	assert_eq(miku.params.value(&"identity", "patience"), 0.1, "the mind reads the same params")


func test_pool_reuses_dissolved_hands() -> void:
	miku.perform(ActionScript.SUMMON_HANDS, {"count": 4})
	_tick(6.0)
	assert_eq(miku.hands.active_count(), 4)
	miku.perform(ActionScript.DISCARD, {})
	_tick(6.0)
	assert_eq(miku.hands.active_count(), 0, "released hands dissolve")
	var built := miku.hands.built
	miku.perform(ActionScript.SUMMON_HANDS, {"count": 3})
	_tick(6.0)
	assert_eq(miku.hands.built, built, "the pool reuses them")
	miku.perform(ActionScript.SUMMON_HANDS, {"count": 7})
	_tick(6.0)
	assert_eq(miku.hands.active_count(), 7, "no arbitrary limit")


func test_life_without_input_is_alive_and_causeless_particles_never_appear() -> void:
	var heads := PackedVector3Array()
	for i in 20:
		_tick(0.5)
		heads.append(miku.body.head_position())
	var moved := 0
	for i in range(1, heads.size()):
		if heads[i].distance_to(heads[i - 1]) > 0.0005:
			moved += 1
	assert_eq(moved, heads.size() - 1, "never frozen: she breathes, shifts, looks")
	for k: StringName in miku.particles.emitted:
		assert_eq(int(miku.particles.emitted[k]), 0, "no particle without a cause (%s)" % k)
	assert_gte(miku.agenda.history.size(), 2, "her own small acts")


func test_inspect_state_reports_the_character() -> void:
	miku.perform(ActionScript.SUMMON_HAND, {})
	_tick(2.0)
	var s := miku.inspect_state()
	for k in ["mood", "composure", "action", "hands", "threads", "worlds", "attention"]:
		assert_true(s.has(k), k)
	assert_eq((s["hands"] as Array).size(), 1)
