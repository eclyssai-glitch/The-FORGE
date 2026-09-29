extends GutTest
## Choreography: every visual value is a pure, continuous function of (world, sim time), fits the
## scripted timeline (no overlap between steps) and matches the event -> visual mapping.

var _events: Array[SimEvent]
var _end: float


func before_all() -> void:
	_events = OriginChamberScript.build()
	_end = _events[-1].time


## World as Simulation.seek(t) would derive it.
func _world(t: float) -> WorldState:
	var upto: Array[SimEvent] = []
	for e in _events:
		if e.time <= t:
			upto.append(e)
	return WorldState.derive(upto)


func _samples(step: float = 0.1) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var t := 0.0
	while t <= _end + 2.0:
		out.append(t)
		t += step
	return out


func test_dormant_core_has_no_energy() -> void:
	var w := _world(0.5)
	assert_eq(Choreography.core_energy(w, 0.5), 0.0, "no EMBER before activation")
	assert_eq(Choreography.core_pulse(w, 0.5), 0.0)
	assert_eq(Choreography.light_stage(w), "dormant")


func test_core_energy_rises_and_settles() -> void:
	var w := _world(_end)
	var act := w.core_activation_at
	var online := w.core_online_at
	var mid := Choreography.core_energy(_world((act + online) * 0.5), (act + online) * 0.5)
	assert_between(mid, 0.05, Choreography.CORE_WAKE_LEVEL)
	var settled := online + Choreography.CORE_ONLINE_SETTLE + 0.1
	assert_almost_eq(Choreography.core_energy(_world(settled), settled), 1.0, 1e-4)
	var prev := 0.0
	for t in _samples():
		var e := Choreography.core_energy(_world(t), t)
		assert_true(e >= prev - 1e-5, "energy never drops (t=%.1f)" % t)
		assert_between(e, 0.0, 1.0)
		prev = e


func test_values_are_bounded_and_continuous() -> void:
	# Jumps between 0.02 s samples stay small: no pops at event boundaries.
	var prev := {}
	var t := 0.0
	var levels := {}
	while t <= _end + 1.0:
		var w := _world(t)
		Choreography.light_levels(w, t, levels)
		var now := {
			"energy": Choreography.core_energy(w, t),
			"finish": Choreography.finish(w, t),
			"twist": Choreography.twist_amount(w, t),
			"lock": Choreography.final_lock(w, t),
			"ribs": Choreography.rib_growth(w, t),
			"scan_s": Choreography.scan_strength(w, t),
			"scan_y": Choreography.scan_y(w, t),
			"key": levels["key"], "core": levels["core"], "exposure": levels["exposure"],
		}
		for k: String in now:
			if k != "scan_y":
				assert_between(float(now[k]), 0.0, 3.0, "%s bounded at t=%.2f" % [k, t])
			if prev.has(k):
				assert_true(absf(float(now[k]) - float(prev[k])) < 0.12,
					"%s continuous at t=%.2f (%.3f -> %.3f)" % [k, t, prev[k], now[k]])
		prev = now
		t += 0.02


func test_light_levels_match_profile_at_rest() -> void:
	var levels := {}
	Choreography.light_levels(_world(0.0), 0.0, levels)
	for k: String in EnvironmentProfile.LIGHT["dormant"]:
		assert_almost_eq(float(levels[k]), float(EnvironmentProfile.LIGHT["dormant"][k]), 1e-5, k)
	Choreography.light_levels(_world(_end), _end, levels)
	for k: String in EnvironmentProfile.LIGHT["final"]:
		assert_almost_eq(float(levels[k]), float(EnvironmentProfile.LIGHT["final"][k]), 1e-5, k)


func test_light_stage_follows_events() -> void:
	var w := _world(_end)
	assert_eq(Choreography.light_stage(_world(w.core_activation_at)), "active")
	assert_eq(Choreography.light_stage(_world(w.materials_at)), "active", "active until lighting")
	assert_eq(Choreography.light_stage(_world(w.lighting_at)), "lit")
	assert_eq(Choreography.light_stage(_world(w.verification_at)), "verify")
	assert_eq(Choreography.light_stage(_world(w.verified_at)), "verify")
	assert_eq(Choreography.light_stage(_world(w.finalized_at)), "final")


func test_fragments_emit_then_rest_before_seeding() -> void:
	var w := _world(_end)
	for i in OriginChamberScript.FRAGMENT_COUNT:
		assert_eq(Choreography.emission(i, _world(w.fragments_at - 0.1), w.fragments_at - 0.1), 0.0)
	var rest := w.fragments_at + Choreography.EMIT_SPREAD + Choreography.EMIT_DUR
	assert_lt(rest, w.seeded_at, "all fragments at rest before the axis is seeded")
	for i in OriginChamberScript.FRAGMENT_COUNT:
		assert_almost_eq(Choreography.emission(i, _world(rest), rest), 1.0, 1e-5)


func test_each_layer_seats_before_the_next_step() -> void:
	var w := _world(_end)
	var n := w.layer_times.size()
	for l in n:
		var seated := Choreography.layer_seated_at(w.layer_times[l])
		var next := w.layer_times[l + 1] if l + 1 < n else w.materials_at
		assert_lt(seated, next, "layer %d seated before the next step" % l)
		for k in 16:
			assert_almost_eq(Choreography.assembly(k, 16, w.layer_times[l], seated), 1.0, 1e-5)
			assert_eq(Choreography.assembly(k, 16, w.layer_times[l], w.layer_times[l]), 0.0)
			assert_eq(Choreography.build_energy(k, 16, w.layer_times[l], seated + Choreography.BUILD_FADE + 0.01), 0.0,
				"EMBER build energy is transient")
	assert_eq(Choreography.assembly(0, 16, -1.0, 99.0), 0.0, "layer not added")


func test_guides_appear_on_seeding_and_leave_with_their_layer() -> void:
	var w := _world(_end)
	assert_eq(Choreography.guide_strength(_world(w.seeded_at - 0.1), 4, w.seeded_at - 0.1), 0.0)
	var t := w.seeded_at + Choreography.GUIDE_IN
	assert_almost_eq(Choreography.guide_strength(_world(t), 4, t), Choreography.GUIDE_LEVEL, 1e-5)
	var gone := w.layer_times[4] + Choreography.GUIDE_OUT
	assert_almost_eq(Choreography.guide_strength(_world(gone), 4, gone), 0.0, 1e-5)


func test_final_lock_completes_before_session_end() -> void:
	var w := _world(_end)
	assert_eq(Choreography.twist_amount(_world(w.finalized_at - 0.1), w.finalized_at - 0.1), 1.0, "twisted until the lock")
	assert_eq(Choreography.final_lock(_world(w.verified_at), w.verified_at), 0.0)
	assert_eq(Choreography.rib_growth(_world(w.verified_at), w.verified_at), 0.0, "ribs only in the final form")
	var done := w.finalized_at + maxf(Choreography.LOCK_DUR, maxf(Choreography.RIB_DELAY + Choreography.RIB_DUR,
		Choreography.ARC_DELAY + Choreography.ARC_DUR))
	assert_lt(done, w.completed_at, "the lock finishes before SESSION_COMPLETED")
	assert_almost_eq(Choreography.twist_amount(w, done), 0.0, 1e-5)
	assert_almost_eq(Choreography.rib_growth(w, done), 1.0, 1e-5)
	assert_almost_eq(Choreography.final_lock(w, done), Choreography.FINAL_LOCK_LEVEL, 1e-5)
	assert_almost_eq(Choreography.rib_energy(w, done), 0.0, 1e-5, "ribs cool down")


func test_verification_sweep_stays_clear_of_floor_and_parks() -> void:
	var w := _world(_end)
	assert_eq(Choreography.scan_y(_world(1.0), 1.0), Choreography.SCAN_PARK_Y)
	assert_eq(Choreography.scan_strength(_world(w.verification_at - 0.1), w.verification_at - 0.1), 0.0)
	var mid := (w.verification_at + w.verified_at) * 0.5
	assert_almost_eq(Choreography.scan_strength(_world(mid), mid), 1.0, 1e-5)
	var after := w.verified_at + Choreography.SCAN_EXIT + 0.01
	assert_almost_eq(Choreography.scan_strength(_world(after), after), 0.0, 1e-5)
	assert_almost_eq(Choreography.scan_y(_world(after), after), Choreography.SCAN_PARK_Y, 1e-5)
	var lo := 99.0
	var hi := -99.0
	for t in _samples(0.05):
		var y := Choreography.scan_y(_world(t), t)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	assert_gt(lo, CameraShots.FLOOR_Y + 0.3, "ring never reaches the floor")
	assert_gt(hi, 1.84, "the sweep covers the top layer")


func test_check_flash_follows_checks() -> void:
	var w := _world(_end)
	var first := float(w.checks[0]["at"])
	assert_eq(Choreography.check_flash(_world(first - 0.01), first - 0.01, 0.0), 0.0)
	var y := Choreography.scan_y(w, first)
	assert_almost_eq(Choreography.check_flash(_world(first), first, y), 1.0, 1e-5, "flash starts at the ring")
	var far := y + 2.0
	assert_eq(Choreography.check_flash(_world(first + 0.1), first + 0.1, far), 0.0, "wave has not arrived yet")
	assert_gt(Choreography.check_flash(_world(first + 0.45), first + 0.45, far), 0.0, "wave arrived")


func test_waves_and_halo() -> void:
	var out := {}
	var w := _world(_end)
	Choreography.wave(_world(0.5), 0.5, out)
	assert_eq(out["strength"], 0.0, "no wave while dormant")
	var t := w.core_activation_at + 0.5
	Choreography.wave(_world(t), t, out)
	assert_gt(out["strength"], 0.0)
	assert_between(out["radius"], 0.5, 6.0)
	t = w.finalized_at + 1.0
	Choreography.wave(_world(t), t, out)
	assert_gt(out["radius"], 3.05, "final wave expands outside the structure")
	Choreography.wave(w, _end, out)
	assert_eq(out["strength"], 0.0, "no wave at rest")
	assert_eq(Choreography.final_halo(_world(w.verified_at), w.verified_at), 0.0, "EMBER halo only in final form")
	assert_almost_eq(Choreography.final_halo(w, _end), Choreography.FINAL_HALO_LEVEL, 1e-5)


func test_sparks_are_a_short_burst() -> void:
	var w := _world(_end)
	assert_eq(Choreography.sparks(_world(w.fragments_at - 0.1), w.fragments_at - 0.1), 0.0)
	var mid := w.fragments_at + Choreography.SPARK_DUR * 0.5
	assert_almost_eq(Choreography.sparks(_world(mid), mid), 0.5, 1e-5)
	assert_eq(Choreography.sparks(w, _end), 1.0)
