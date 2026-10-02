extends GutTest
## Loop 5 r2 — native migration STEP 1: MIKU's torso on an AnimationTree (MikuDirector, MikuPoses).
## Configuration (the 4.7.2 traps of docs/research/native-character-runtime.md), the emotional
## timing, no instantaneous transition, the composure grade, parity with the round-1 body,
## appearance untouched, determinism and the backend selection.

const DT := 1.0 / 30.0
const TORSO: Array[String] = ["hips", "spine", "chest", "neck", "head", "clavicle.L", "clavicle.R"]

var root: Node3D


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)


func after_each() -> void:
	MikuBody.override_backend = &""


func _miku(backend: StringName) -> Miku:
	MikuBody.override_backend = backend
	var m := Miku.new()
	root.add_child(m)
	m.set_process(false)
	m.tick(DT)
	MikuBody.override_backend = &""
	return m


func _mood(m: Miku, id: StringName) -> void:
	if id == &"focused":
		m.mind.begin_task(&"build", &"world_calyx")
	else:
		m.mind.force_mood(id)


func _tick(m: Miku, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		m.tick(DT)
		t += DT


func _local(m: Miku, key: String) -> Quaternion:
	var sk := m.body.skeleton
	var b := m.body.map.bone(key)
	return sk.get_bone_pose_rotation(b)


func test_backend_selection() -> void:
	assert_eq(MikuBody.choose_layers(PackedStringArray())[&"torso"], MikuBody.DEFAULT_BACKEND)
	var n := MikuBody.choose_layers(PackedStringArray(["--body=native"]))
	assert_eq(n[&"torso"], MikuBody.NATIVE)
	assert_eq(n[&"gaze"], MikuBody.LEGACY, "a layer without a native implementation stays legacy")
	var l := MikuBody.choose_layers(PackedStringArray(["--body=native", "--body-torso=legacy"]))
	assert_eq(l[&"torso"], MikuBody.LEGACY, "per layer")
	var m := _miku(MikuBody.NATIVE)
	assert_not_null(m.body.director)
	assert_eq(m.body.backend(), MikuBody.NATIVE)
	assert_eq(m.inspect_state()["body"]["layers"]["torso"], "native")
	var o := _miku(MikuBody.LEGACY)
	assert_null(o.body.director)
	assert_eq(o.inspect_state()["body"]["backend"], "legacy")


func test_tree_configuration() -> void:
	var m := _miku(MikuBody.NATIVE)
	var d := m.body.director
	assert_eq(d.tree.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "advanced by the MotionClock dt")
	var bt := d.tree.tree_root as AnimationNodeBlendTree
	var sm := bt.get_node(&"mood") as AnimationNodeStateMachine
	for s in MikuPoses.MOODS:
		assert_true(sm.has_node(s), "state %s" % s)
	var first_auto := false
	for i in sm.get_transition_count():
		var tr := sm.get_transition(i)
		if sm.get_transition_from(i) == &"Start":
			first_auto = tr.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			continue
		assert_gt(tr.xfade_time, 0.0, "no instantaneous transition %s -> %s" % [sm.get_transition_from(i), sm.get_transition_to(i)])
		assert_not_null(tr.xfade_curve)
		var to := MikuPoses.MOODS.find(sm.get_transition_to(i))
		var from := MikuPoses.MOODS.find(sm.get_transition_from(i))
		if (to == MikuMind.Mood.FRUSTRATED or to == MikuMind.Mood.ANGRY) and from != MikuMind.Mood.ANGRY:
			assert_almost_eq(tr.xfade_time, 0.25, 0.001, "composure is lost in 0.25 s")
		if (from == MikuMind.Mood.FRUSTRATED or from == MikuMind.Mood.ANGRY) and (to == MikuMind.Mood.CALM or to == MikuMind.Mood.RECOVERING):
			assert_between(tr.xfade_time, 1.2, 1.6001, "composure comes back in 1.2-1.6 s")
	assert_true(first_auto, "Start -> calm is AUTO (P-05)")
	assert_eq(sm.get_transition_count(), 1 + 5 * 4, "every mood reaches every other directly")
	var adds := 0
	for n in bt.get_node_list():
		var node := bt.get_node(n)
		if node is AnimationNodeAdd2:
			adds += 1
			assert_true((node as AnimationNodeAdd2).sync, "%s keeps its clock (sync, P-07)" % n)
		if node is AnimationNodeOneShot:
			assert_true((node as AnimationNodeOneShot).filter_enabled, "%s is filtered to the torso" % n)
	assert_eq(adds, 1 + 7 + 1 + 1 + 2)
	assert_true(bt.get_node(&"tension") is AnimationNodeBlendSpace1D, "composure grade")
	assert_true(bt.get_node(&"breath_rate") is AnimationNodeTimeScale)


func test_only_rotation_tracks() -> void:
	var m := _miku(MikuBody.NATIVE)
	var lib := m.body.director.tree.get_animation_library(&"")
	assert_gt(lib.get_animation_list().size(), 15)
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		for t in a.get_track_count():
			assert_eq(a.track_get_type(t), Animation.TYPE_ROTATION_3D, "%s track %d is rotation only (P-17)" % [n, t])


func test_appearance_is_never_overwritten() -> void:
	var m := _miku(MikuBody.NATIVE)
	m.apply_config({"appearance": {"height": 1.12, "neck_length": 1.25, "shoulder_width": 1.1}})
	_tick(m, 4.0)
	var sk := m.body.skeleton
	for key in ["neck", "head", "upper_arm.L"]:
		var b := m.body.map.bone(key)
		assert_almost_eq(sk.get_bone_pose_position(b).distance_to(sk.get_bone_rest(b).origin), 0.0, 1e-4,
			"%s keeps the appearance position" % key)


func test_mood_states_follow_the_mind() -> void:
	var m := _miku(MikuBody.NATIVE)
	var d := m.body.director
	assert_eq(d.current_state(), &"calm")
	m.mind.force_mood(&"frustrated")
	_tick(m, 0.35)
	assert_eq(d.current_state(), &"frustrated")
	assert_eq(String(d.inspect_state()["fading_from"]), "", "lost in ~0.25 s")
	assert_eq(int(d.gestures[&"flinch"]), 1, "the flinch")
	m.mind.force_mood(&"recover")
	_tick(m, 0.5)
	assert_eq(d.current_state(), &"recovering")
	assert_ne(String(d.inspect_state()["fading_from"]), "", "regained slowly: still fading at 0.5 s")
	assert_eq(int(d.gestures[&"exhale"]), 1, "the exhale")
	_tick(m, 1.2)
	assert_eq(String(d.inspect_state()["fading_from"]), "")


func test_no_instantaneous_motion() -> void:
	# Through a whole emotional arc, no torso bone jumps between frames.
	var m := _miku(MikuBody.NATIVE)
	var prev := {}
	var worst := 0.0
	var worst_at := ""
	var arc := [[0.0, &"calm"], [2.0, &"focused"], [4.0, &"frustrated"], [5.5, &"angry"], [7.5, &"recover"],
		[8.0, &"frustrated"], [9.5, &"recover"]]
	var t := 0.0
	var k := 0
	while t < 14.0:
		if k < arc.size() and t >= float(arc[k][0]):
			_mood(m, arc[k][1])
			k += 1
		m.tick(DT)
		t += DT
		for key in TORSO:
			var q := _local(m, key)
			if prev.has(key):
				var deg := rad_to_deg((prev[key] as Quaternion).angle_to(q))
				if deg > worst:
					worst = deg
					worst_at = "%s at %.2f s" % [key, t]
			prev[key] = q
	gut.p("largest torso step per frame: %.2f deg (%s)" % [worst, worst_at])
	assert_lt(worst, 3.0, "no pop (%s)" % worst_at)


func test_composure_grade_is_immediate_even_mid_fade() -> void:
	var m := _miku(MikuBody.NATIVE)
	var d := m.body.director
	m.mind.force_mood(&"frustrated")
	_tick(m, 1.0)
	m.mind.force_mood(&"recover")
	_tick(m, 0.3)
	var before := float(d.inspect_state()["tension"])
	m.mind.on_failure(1.0)
	_tick(m, 0.3)
	assert_gt(float(d.inspect_state()["tension"]), before, "the tension answers at once")


func test_parity_with_round_one() -> void:
	# Same mind, same goals: the native torso holds the round-1 carriage (small differences: the
	# life loop inside each mood).
	var a := _miku(MikuBody.LEGACY)
	var b := _miku(MikuBody.NATIVE)
	for mood in [&"calm", &"focused", &"frustrated", &"angry"]:
		_mood(a, mood)
		_mood(b, mood)
		_tick(a, 5.0)
		_tick(b, 5.0)
		for key in ["chest", "neck", "head", "clavicle.L"]:
			var deg := rad_to_deg(_local(a, key).angle_to(_local(b, key)))
			assert_lt(deg, 6.0, "%s %s within 6 deg of round 1 (%.2f)" % [mood, key, deg])


func test_breath_moves_the_chest() -> void:
	var m := _miku(MikuBody.NATIVE)
	var lo := INF
	var hi := -INF
	var rest := m.body.skeleton.get_bone_rest(m.body.map.bone("chest")).basis.get_rotation_quaternion()
	for i in 180:
		m.tick(DT)
		var x := (rest.inverse() * _local(m, "chest")).get_euler().x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	assert_gt(rad_to_deg(hi - lo), 1.0, "she breathes")


func test_deterministic() -> void:
	# Two runs, one after the other (a living Miku binds to the hands/worlds already in the tree).
	var poses: Array = []
	for run in 2:
		var m := _miku(MikuBody.NATIVE)
		_tick(m, 2.0)
		m.mind.force_mood(&"frustrated")
		_tick(m, 2.0)
		var q := {}
		for key in TORSO:
			q[key] = _local(m, key)
		poses.append(q)
		m.free()
	for key in TORSO:
		assert_almost_eq(absf((poses[0][key] as Quaternion).dot(poses[1][key])), 1.0, 1e-6, key)


func test_runtime_contract_holds_on_native() -> void:
	var m := _miku(MikuBody.NATIVE)
	var done: Array[StringName] = []
	m.action_finished.connect(func(x: StringName) -> void: done.append(x))
	for a in [[&"LOOK_AT_USER", {}], [&"SUMMON_HANDS", {"count": 2}], [&"FRUSTRATED", {}], [&"RECOVER", {}]]:
		m.perform(a[0], a[1])
		var t := 0.0
		while done.size() == 0 and t < 12.0:
			m.tick(DT)
			t += DT
		assert_eq(done.size(), 1, "%s finished" % a[0])
		done.clear()
	assert_false(m.body.fingertip(0, 1).is_equal_approx(Vector3.ZERO))
