extends GutTest
## Loop 5 — second-order springs (SecondOrder, SecondOrder3), the weight of a puppet hand
## (HandDynamics), the intent thread's cycle (ThreadCycle), finger poses and IK helpers (LimbIK).


func _run(s: SecondOrder, target: float, seconds: float, dt := 1.0 / 60.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var t := 0.0
	while t < seconds:
		out.append(s.step(target, dt))
		t += dt
	return out


func test_spring_settles_on_target() -> void:
	var s := SecondOrder.new(1.0, 1.0, 0.0, 0.0)
	var y := _run(s, 1.0, 5.0)
	assert_almost_eq(y[y.size() - 1], 1.0, 1e-3)


func test_spring_is_not_linear_and_starts_slow_with_weight() -> void:
	var s := SecondOrder.new(1.0, 1.0, 0.0, 0.0)
	var y := _run(s, 1.0, 1.0, 0.1)
	assert_lt(y[0], 0.25, "r = 0: it does not jump with the target")
	var d1 := y[1] - y[0]
	var d5 := y[5] - y[4]
	assert_ne(snappedf(d1, 1e-4), snappedf(d5, 1e-4), "not a constant-speed tween")


func test_underdamped_overshoots_critically_damped_does_not() -> void:
	var under := _run(SecondOrder.new(1.0, 0.4, 0.0, 0.0), 1.0, 4.0)
	var crit := _run(SecondOrder.new(1.0, 1.0, 0.0, 0.0), 1.0, 4.0)
	var max_u := 0.0
	var max_c := 0.0
	for v in under:
		max_u = maxf(max_u, v)
	for v in crit:
		max_c = maxf(max_c, v)
	assert_gt(max_u, 1.05, "calm springs overshoot a little (follow-through)")
	assert_lt(max_c, 1.001, "lost composure: dry, no overshoot")


func test_negative_response_anticipates() -> void:
	var s := SecondOrder.new(1.0, 0.8, -1.5, 0.0)
	var y := _run(s, 1.0, 0.3)
	var minimum := 0.0
	for v in y:
		minimum = minf(minimum, v)
	assert_lt(minimum, -0.001, "r < 0 moves the wrong way first")


func test_spring_survives_a_long_frame() -> void:
	var s := SecondOrder.new(3.0, 0.5, 0.0, 0.0)
	s.step(1.0, 0.5)
	assert_true(is_finite(s.y) and absf(s.y) < 3.0, "a slow software frame never explodes")


func test_higher_frequency_arrives_sooner() -> void:
	var slow := _run(SecondOrder.new(0.5, 1.0, 0.0, 0.0), 1.0, 0.8)
	var fast := _run(SecondOrder.new(2.0, 1.0, 0.0, 0.0), 1.0, 0.8)
	assert_gt(fast[fast.size() - 1], slow[slow.size() - 1])


func test_vector_spring_acceleration_limit() -> void:
	var s := SecondOrder3.new(2.0, 1.0, 0.0, Vector3.ZERO)
	var dt := 1.0 / 60.0
	var v_prev := Vector3.ZERO
	for i in 30:
		s.step_limited(Vector3(10, 0, 0), dt, 2.0)
		assert_lte((s.v - v_prev).length() / dt, 2.0 + 1e-3, "acceleration capped")
		v_prev = s.v


# ---------------------------------------------------------------- hand weight


func _travel(mass: float, force: float, seconds: float) -> float:
	var m := SecondOrder3.new(1.0, 1.0, 0.0, Vector3.ZERO)
	var t := 0.0
	while t < seconds:
		HandDynamics.step(m, Vector3(5, 0, 0), force, mass, 1.0 / 60.0)
		t += 1.0 / 60.0
	return m.y.x


func test_hand_never_moves_without_thread_tension() -> void:
	assert_eq(_travel(1.0, 0.0, 3.0), 0.0, "a puppet: no tension, no motion")


func test_heavier_hand_is_slower() -> void:
	assert_gt(_travel(0.6, 1.0, 1.0), _travel(2.5, 1.0, 1.0))


func test_stronger_pull_is_faster() -> void:
	assert_gt(_travel(1.0, 1.0, 1.0), _travel(1.0, 0.3, 1.0))


func test_slack_thread_lets_the_hand_coast_and_stop() -> void:
	var m := SecondOrder3.new(1.0, 1.0, 0.0, Vector3.ZERO)
	for i in 60:
		HandDynamics.step(m, Vector3(5, 0, 0), 1.0, 1.0, 1.0 / 60.0)
	var at_release := m.y.x
	for i in 240:
		HandDynamics.step(m, Vector3(5, 0, 0), 0.0, 1.0, 1.0 / 60.0)
	assert_gt(m.y.x, at_release, "it coasts on (inertia)")
	assert_lt(m.v.length(), 0.05, "and stops by itself (no spring pulls it any more)")
	var stopped := m.y.x
	for i in 120:
		HandDynamics.step(m, Vector3(5, 0, 0), 0.0, 1.0, 1.0 / 60.0)
	assert_almost_eq(m.y.x, stopped, 0.01, "at rest it stays where it stopped")


func test_travel_time_grows_with_mass() -> void:
	assert_gt(HandDynamics.travel_time(4.0, 3.0), HandDynamics.travel_time(4.0, 1.0))


# ---------------------------------------------------------------- thread cycle


func _cycle_until(c: ThreadCycle, phase: ThreadCycle.Phase, limit := 10.0) -> float:
	var t := 0.0
	while c.phase != phase and t < limit:
		c.step(1.0 / 60.0)
		t += 1.0 / 60.0
	return t


func test_thread_cycle_order() -> void:
	var c := ThreadCycle.new()
	c.start(0.8)
	assert_eq(c.phase, ThreadCycle.Phase.APPEAR)
	assert_false(c.responding(), "the hand never moves before the thread is taut")
	_cycle_until(c, ThreadCycle.Phase.PULL)
	assert_eq(c.phase, ThreadCycle.Phase.PULL, "cast across, then pulled")
	assert_eq(c.reach, 1.0)
	for i in 120:
		c.step(1.0 / 60.0)
	assert_true(c.responding())
	c.relax()
	_cycle_until(c, ThreadCycle.Phase.GONE)
	assert_eq(c.log, [ThreadCycle.Phase.APPEAR, ThreadCycle.Phase.PULL, ThreadCycle.Phase.RELAX,
		ThreadCycle.Phase.FADE, ThreadCycle.Phase.GONE] as Array[ThreadCycle.Phase])
	assert_false(c.is_alive())


func test_thread_waits_for_a_pull() -> void:
	var c := ThreadCycle.new()
	c.start(0.0)
	for i in 120:
		c.step(1.0 / 60.0)
	assert_eq(c.phase, ThreadCycle.Phase.APPEAR, "cast, slack, waiting for the gesture's pull")
	c.pull(0.6)
	_cycle_until(c, ThreadCycle.Phase.PULL)
	assert_eq(c.phase, ThreadCycle.Phase.PULL)


func test_tension_is_proportional_to_force() -> void:
	var weak := ThreadCycle.new()
	var strong := ThreadCycle.new()
	weak.start(0.3)
	strong.start(1.0)
	for i in 300:
		weak.step(1.0 / 60.0)
		strong.step(1.0 / 60.0)
	assert_almost_eq(weak.tension.y, 0.3, 0.03)
	assert_almost_eq(strong.tension.y, 1.0, 0.03)


func test_angry_tempo_casts_faster() -> void:
	var calm := ThreadCycle.new()
	var angry := ThreadCycle.new()
	calm.start(1.0, 1.0)
	angry.start(1.0, 1.9)
	assert_gt(_cycle_until(calm, ThreadCycle.Phase.PULL), _cycle_until(angry, ThreadCycle.Phase.PULL))


# ---------------------------------------------------------------- poses & IK


func test_hand_poses_have_five_fingers() -> void:
	var out := PackedFloat32Array()
	for id: StringName in HandPoses.POSES:
		HandPoses.curls(id, out)
		assert_eq(out.size(), 5, String(id))
	HandPoses.curls(&"fist", out)
	assert_gt(out[2], 0.9)
	HandPoses.curls(&"point", out)
	assert_lt(out[1], 0.1, "the index stays straight")
	assert_gt(HandPoses.finger_lag(1), HandPoses.finger_lag(4), "index leads, little finger trails")


func test_elbow_keeps_segment_lengths() -> void:
	var s := Vector3(0.3, 1.0, 0.0)
	var t := Vector3(0.5, 0.2, 0.6)
	var e := LimbIK.elbow(s, t, 0.6, 0.55, Vector3(1, -0.5, -0.5))
	assert_almost_eq((e - s).length(), 0.6, 1e-4)
	assert_almost_eq((t - e).length(), 0.55, 1e-3)


func test_elbow_out_of_reach_straightens() -> void:
	var e := LimbIK.elbow(Vector3.ZERO, Vector3(0, -5, 0), 0.6, 0.5, Vector3.RIGHT)
	assert_almost_eq(e.y, -0.6, 1e-3)


func test_align_maps_frames() -> void:
	var q := LimbIK.align(Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP)
	assert_true((q * Vector3.DOWN).is_equal_approx(Vector3.RIGHT))
	assert_true((q * Vector3.FORWARD).is_equal_approx(Vector3.UP))
