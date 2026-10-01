extends GutTest
## GENESIS animation logic (pure): GenesisChoreography, GenesisShots, GenesisLayout and the thread
## arc helpers. Every narrative value is 0 before its event, settles after it and is continuous.

const STEP := 0.02


func _state_at(t: float) -> GenesisState:
	var events: Array[SimEvent] = []
	for e in GenesisScript.build():
		if e.time <= t:
			events.append(e)
	return GenesisState.derive(events)


func _full() -> GenesisState:
	return GenesisState.derive(GenesisScript.build())


## Samples `f(g, t)` over the whole session and returns the largest jump between samples.
func _max_jump(f: Callable) -> float:
	var g := _full()
	var prev := float(f.call(g, 0.0))
	var worst := 0.0
	var t := STEP
	while t <= GenesisScript.DURATION + 4.0:
		var v := float(f.call(g, t))
		worst = maxf(worst, absf(v - prev))
		prev = v
		t += STEP
	return worst


func test_values_rest_before_their_events() -> void:
	var g := GenesisState.new()
	for t in [0.0, 10.0, 50.0]:
		assert_eq(GenesisChoreography.awaken(g, t), 0.0)
		assert_eq(GenesisChoreography.halo(g, t), 0.0)
		assert_eq(GenesisChoreography.seed_light(g, t), GenesisChoreography.SEED_DORMANT,
			"asleep only the ember on her brow glows")
		assert_eq(GenesisChoreography.body_presence(g, t), 0.0, "in the dark: no body, no silhouette")
		assert_eq(GenesisChoreography.seed_bloom(g, t), 0.0)
		assert_eq(GenesisChoreography.climax(g, t), 0.0)
		assert_eq(GenesisChoreography.hands_release(g, t), 0.0)
		assert_eq(GenesisChoreography.head_lift(g, t), 0.0)
		assert_eq(GenesisChoreography.halo_close(g, t), 0.0)
		assert_eq(GenesisChoreography.stable_wave(g, t, 2), -1.0)
		assert_eq(GenesisChoreography.hands_visible(g, t), 0.0)
		assert_eq(GenesisChoreography.planet_radius(g, t), 0.0)
		assert_eq(GenesisChoreography.planet_heat(g, t), 0.0)
		assert_eq(GenesisChoreography.dust_visible(g, t), 0.0)
		assert_eq(GenesisChoreography.ring(g, t), 0.0)
		assert_eq(GenesisChoreography.belt(g, t), 0.0)
		assert_eq(GenesisChoreography.link(g, t, 0), 0.0)
		assert_eq(GenesisChoreography.veins(g, t, true), 0.0)
	assert_almost_eq(GenesisChoreography.hair_reveal(g, 5.0), GenesisChoreography.HAIR_ASLEEP, 1e-6,
		"asleep, the hair is short")


func test_values_settle_after_the_session() -> void:
	var g := _full()
	var t := GenesisScript.DURATION
	assert_almost_eq(GenesisChoreography.awaken(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.hair_reveal(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.halo(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.hands_rise(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.planet_radius(g, t), GenesisLayout.PLANET_RADIUS, 1e-4)
	assert_almost_eq(GenesisChoreography.planet_formation(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.planet_crust(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.planet_atmosphere(g, t), 1.0, 1e-4)
	assert_lt(GenesisChoreography.planet_heat(g, t), 0.3, "the crust has cooled the world")
	for i in GenesisScript.MOON_COUNT:
		assert_almost_eq(GenesisChoreography.moon(g, t, i), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.ring(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.belt(g, t), 1.0, 1e-4)
	for i in GenesisScript.LINKS.size():
		assert_almost_eq(GenesisChoreography.link(g, t, i), 1.0, 1e-4, "thread %d woven" % i)
	assert_eq(GenesisChoreography.dust_visible(g, t), 0.0, "the dust fed the seed")
	assert_almost_eq(GenesisChoreography.veins(g, t, false), GenesisChoreography.VEINS_STABLE, 0.02,
		"the kintsugi has cooled after the work")
	# Every climax beat resolves before the session completes (its last instant is held).
	assert_almost_eq(GenesisChoreography.body_presence(g, t), 1.0, 1e-4)
	assert_almost_eq(GenesisChoreography.climax(g, t), GenesisChoreography.CLIMAX_REST, 1e-3)
	assert_almost_eq(GenesisChoreography.hands_release(g, t), 1.0, 1e-3, "the hands have let go")
	assert_almost_eq(GenesisChoreography.head_lift(g, t), 1.0, 1e-3, "she has raised her head")
	assert_almost_eq(GenesisChoreography.halo_close(g, t), 1.0, 1e-3, "the halo is a full circle")
	assert_eq(GenesisChoreography.stable_wave(g, t + 0.01, GenesisChoreography.wave_hops()), -1.0,
		"the single pulse has crossed the graph")


func test_everything_is_continuous() -> void:
	var fns := {
		"awaken": GenesisChoreography.awaken, "hair": GenesisChoreography.hair_reveal,
		"halo": GenesisChoreography.halo, "seed": GenesisChoreography.seed_light,
		"rise": GenesisChoreography.hands_rise, "visible": GenesisChoreography.hands_visible,
		"work": GenesisChoreography.hands_work, "press": GenesisChoreography.sculpt_press,
		"dust": GenesisChoreography.dust_visible, "converge": GenesisChoreography.dust_converge,
		"radius": GenesisChoreography.planet_radius, "formation": GenesisChoreography.planet_formation,
		"heat": GenesisChoreography.planet_heat, "crust": GenesisChoreography.planet_crust,
		"sky": GenesisChoreography.planet_atmosphere, "disc": GenesisChoreography.accretion_disc,
		"ring": GenesisChoreography.ring, "belt": GenesisChoreography.belt,
		"presence": GenesisChoreography.body_presence, "bloom": GenesisChoreography.seed_bloom,
		"climax": GenesisChoreography.climax, "release": GenesisChoreography.hands_release,
		"lift": GenesisChoreography.head_lift, "halo_close": GenesisChoreography.halo_close,
		"reveal_glow": GenesisChoreography.reveal_glow, "gown": GenesisChoreography.gown_presence,
		"trim": GenesisShots.cue_trim,
	}
	for k: String in fns:
		assert_lt(_max_jump(fns[k]), 0.05, "%s has no jump between 0.02 s samples" % k)
	assert_lt(_max_jump(func(g: GenesisState, t: float) -> float: return GenesisChoreography.veins(g, t, true)), 0.05)
	assert_lt(_max_jump(func(g: GenesisState, t: float) -> float: return GenesisChoreography.moon(g, t, 1)), 0.05)
	assert_lt(_max_jump(func(g: GenesisState, t: float) -> float: return GenesisChoreography.link(g, t, 3)), 0.05)
	assert_lt(_max_jump(func(g: GenesisState, t: float) -> float: return GenesisChoreography.belt_rock(g, t, 17)), 0.05)


func test_the_world_only_grows() -> void:
	var g := _full()
	var prev := 0.0
	var t := 0.0
	while t < GenesisScript.DURATION:
		var r := GenesisChoreography.planet_radius(g, t)
		assert_true(r >= prev - 1e-6, "radius never shrinks (t=%.2f)" % t)
		prev = r
		t += 0.1
	# Each step swells after its own event.
	var radii := GenesisLayout.PLANET_STEP_RADII
	assert_almost_eq(GenesisChoreography.planet_radius(g, GenesisScript.LAYER_TIMES[0] - 0.01), radii[0], 1e-3)
	assert_almost_eq(GenesisChoreography.planet_radius(g, GenesisScript.LAYER_TIMES[1] - 0.01), radii[1], 1e-3)


func test_hands_rise_slowly_and_settle() -> void:
	var g := _full()
	var at := GenesisScript.T_HANDS
	assert_eq(GenesisChoreography.hands_rise(g, at), 0.0)
	assert_lt(GenesisChoreography.hands_rise(g, at + 1.0), 0.2, "slow and heavy, never a pop")
	var peak := 0.0
	var t := at
	while t < at + GenesisChoreography.HANDS_RISE + 1.0:
		peak = maxf(peak, GenesisChoreography.hands_rise(g, t))
		t += 0.05
	assert_gt(peak, 1.0, "overshoots a little before settling")
	assert_lt(peak, 1.0 + GenesisChoreography.HANDS_OVERSHOOT + 0.01)
	assert_almost_eq(GenesisChoreography.hands_rise(g, at + GenesisChoreography.HANDS_RISE), 1.0, 1e-4)


func test_right_hand_presses_on_each_layer() -> void:
	var g := _full()
	for at in GenesisScript.LAYER_TIMES:
		var peak := GenesisChoreography.sculpt_press(g, at + GenesisChoreography.SCULPT_RISE)
		assert_almost_eq(peak, 1.0, 1e-3, "press at layer %.0f" % at)
		assert_gt(GenesisChoreography.veins(g, at + GenesisChoreography.SCULPT_RISE, true),
			GenesisChoreography.veins(g, at - 0.5, true), "the kintsugi lights while it presses")


func test_threads_are_woven_in_order() -> void:
	var g := _full()
	var t := GenesisScript.T_LINKS + 1.0
	for i in range(1, GenesisScript.LINKS.size()):
		assert_true(GenesisChoreography.link(g, t, i) <= GenesisChoreography.link(g, t, i - 1),
			"thread %d starts after thread %d" % [i, i - 1])
	assert_gt(GenesisChoreography.link_done_at(g, 7), GenesisChoreography.link_done_at(g, 0))


func test_light_grows_with_the_awakening() -> void:
	var asleep := GenesisChoreography.light_levels(_state_at(1.0), 1.0, {})
	var awake := GenesisChoreography.light_levels(_full(), 12.0, {})
	for k in ["back", "rim", "key", "ambient"]:
		assert_gt(float(awake[k]), float(asleep[k]), "%s grows" % k)
	assert_eq(float(asleep["planet"]), 0.0)
	# The opening is dark (only the seed): every asleep level is a small share of the awake one.
	for k in ["back", "rim", "key", "fill"]:
		assert_lt(float(asleep[k]), 0.15 * float(GenesisChoreography.LIGHT_AWAKE[k]), "%s dark asleep" % k)
	# The front lights lead the awakening (the revealed body is lit, never cut out by the backlight).
	var g := _full()
	var early := GenesisChoreography.light_levels(g, GenesisScript.T_AWAKEN + 1.8, {})
	var share := func(lv: Dictionary, k: String) -> float:
		return (float(lv[k]) - float(GenesisChoreography.LIGHT_ASLEEP[k])) / (float(GenesisChoreography.LIGHT_AWAKE[k]) - float(GenesisChoreography.LIGHT_ASLEEP[k]))
	assert_gt(share.call(early, "key"), share.call(early, "back") + 0.2, "key and rim before the backlight")
	assert_gt(share.call(early, "rim"), share.call(early, "back") + 0.2)
	assert_gt(GenesisChoreography.seed_bloom(g, GenesisScript.T_AWAKEN + GenesisChoreography.SEED_BLOOM_RISE), 0.99,
		"the seed's light blooms first")
	assert_lt(GenesisChoreography.body_presence(g, GenesisScript.T_AWAKEN + GenesisChoreography.SEED_BLOOM_RISE), 0.25,
		"…and then reveals her")
	var forming := GenesisChoreography.light_levels(_full(), GenesisScript.LAYER_TIMES[0] + 3.0, {})
	assert_gt(float(forming["planet"]), 1.0, "the molten world lights the palms")
	assert_lte(GenesisEnvironment.DIRECTIONAL_FOG_ENERGY, 0.05)
	assert_lte(GenesisLightRig.DIRECTIONAL_FOG, GenesisEnvironment.DIRECTIONAL_FOG_ENERGY)


# --- Shots -------------------------------------------------------------------------------------------

## Screen position (0..1, y down) of `p` seen from a shot (Camera3D convention, 16:9).
func _project(s: CameraShots.Shot, p: Vector3) -> Vector2:
	var cam := Transform3D(Basis.IDENTITY, s.position()).looking_at(s.target, Vector3.UP)
	var local := cam.affine_inverse() * p
	var tv := tan(deg_to_rad(s.fov) * 0.5)
	return Vector2(0.5 + 0.5 * local.x / (-local.z * tv * 16.0 / 9.0), 0.5 - 0.5 * local.y / (-local.z * tv))


func test_hero_composition() -> void:
	var s := GenesisShots.mode_shot(SessionState.Mode.FORGE, CameraShots.Shot.new())
	var head := _project(s, GenesisLayout.miku_point("head_top"))
	var heart := _project(s, GenesisLayout.miku_heart())
	var planet := _project(s, GenesisLayout.PLANET_CENTER)
	assert_between(heart.y, 0.2, 0.42, "MIKU in the upper third")
	assert_between(head.y, 0.1, 0.34)
	assert_between(planet.y, 0.6, 0.86, "the world in the lower third")
	assert_between(heart.x, 0.4, 0.6, "centred")
	assert_lt(s.position().y, GenesisLayout.miku_heart().y, "slight low angle: the camera below her chest")
	assert_gt(s.pitch, -0.3)


func test_cues_follow_the_story() -> void:
	var out := CameraShots.Shot.new()
	var expect := {1.0: GenesisShots.CUE_PORTRAIT, 10.0: GenesisShots.CUE_HERO, 38.0: GenesisShots.CUE_ORBITS,
		47.0: GenesisShots.CUE_BELT, 51.0: GenesisShots.CUE_THREADS, 55.0: GenesisShots.CUE_STABLE}
	for t: float in expect:
		var id := GenesisShots.desired(SessionState.Mode.FORGE, true, _state_at(t), t, 0.0, out)
		assert_eq(id, expect[t], "cue at %.0f s" % t)
		assert_true(String(id).begins_with("cue_"), "cue ids start with cue_ (the director holds user framings outside cues)")
		assert_true(out.position().y >= GenesisShots.MIN_CAMERA_Y - 1e-4)
	var id := GenesisShots.desired(SessionState.Mode.UNIVERSE, true, _full(), 55.0, 0.0, out)
	assert_eq(id, GenesisShots.MODE_IDS[SessionState.Mode.UNIVERSE], "cues only in FORGE")


func test_cue_pose_is_a_function_of_time() -> void:
	var a := CameraShots.Shot.new()
	var b := CameraShots.Shot.new()
	var g := _state_at(30.0)
	GenesisShots.cue(g, 30.0, 12.0, a)
	GenesisShots.cue(g, 30.0, 12.0, b)
	assert_true(a.approx_equals(b), "same (state, time, clock) -> same pose")
	GenesisShots.cue(g, 30.5, 12.0, b)
	assert_lt(absf(a.yaw - b.yaw), 0.04, "slow move")
	GenesisShots.cue(g, 30.0, 12.5, b)
	assert_lt(absf(a.yaw - b.yaw), 0.005, "the ambient sway is tiny")


func test_camera_path_is_one_continuous_move() -> void:
	# The cues are stations of one path: no jump anywhere, also where the cue id changes.
	var prev := CameraShots.Shot.new()
	var cur := CameraShots.Shot.new()
	GenesisShots.cue_path(_state_at(0.0), 0.0, prev)
	var t := STEP
	var worst := 0.0
	while t <= GenesisScript.DURATION:
		GenesisShots.cue_path(_state_at(t), t, cur)
		worst = maxf(worst, cur.position().distance_to(prev.position()))
		assert_lt(absf(cur.fov - prev.fov), 0.05, "fov continuous at %.2f" % t)
		prev.copy_from(cur)
		t += STEP
	assert_lt(worst, 0.12, "the camera never jumps (largest step per 0.02 s)")
	# It opens close on the seed in the dark and recedes at the climax.
	var open := GenesisShots.cue_path(_state_at(1.0), 1.0, CameraShots.Shot.new())
	assert_lt(open.distance, 5.0, "close on the seed")
	assert_lt(open.target.distance_to(GenesisLayout.miku_point("forehead")), 0.3)
	var at_stable := GenesisShots.cue_path(_full(), GenesisScript.T_STABLE, CameraShots.Shot.new())
	var held := GenesisShots.cue_path(_full(), GenesisScript.DURATION, CameraShots.Shot.new())
	assert_gt(held.distance, at_stable.distance + 3.0, "the camera cranes back at the climax")


func test_framings_never_cut_miku_at_the_waist() -> void:
	# Key stations of the path: MIKU's waist is either well inside the frame or the frame stays below
	# her hem / above her chest — never the waist on the frame edge.
	var waist := GenesisLayout.MIKU_ORIGIN
	var s := CameraShots.Shot.new()
	for t in [8.0, 21.5, 35.0, 53.0, GenesisScript.DURATION]:
		GenesisShots.cue_path(_full(), t, s)
		var y := _project(s, waist).y
		assert_true(y > 0.12 and y < 0.88 or y < -0.15 or y > 1.15, "waist clear of the frame edge at %.1f s (y=%.2f)" % [t, y])


func test_climax_is_the_peak_of_light() -> void:
	var g := _full()
	var best := -1.0
	var best_t := 0.0
	var t := 0.0
	var lv := {}
	while t <= GenesisScript.DURATION:
		var total := GenesisChoreography.light_total(GenesisChoreography.light_levels(g, t, lv))
		if total > best + 1e-6:
			best = total
			best_t = t
		t += 0.05
	assert_gte(best_t, GenesisScript.T_STABLE, "no brighter moment before planet.stable (peak at %.2f s)" % best_t)
	var mantle := GenesisChoreography.light_total(GenesisChoreography.light_levels(g, GenesisScript.LAYER_TIMES[0] + 3.0, lv))
	assert_gt(best, mantle * 1.25, "the climax clearly outshines the molten mantle")


func test_hands_let_go_and_the_kintsugi_cools() -> void:
	var g := _full()
	var st := GenesisScript.T_STABLE
	assert_eq(GenesisChoreography.hands_release(g, st), 0.0)
	var prev := 0.0
	var t := st
	while t <= GenesisScript.DURATION:
		var r := GenesisChoreography.hands_release(g, t)
		assert_true(r >= prev - 1e-6, "the release never goes back")
		prev = r
		t += 0.05
	assert_lt(GenesisChoreography.veins(g, GenesisScript.DURATION, true), GenesisChoreography.veins(g, st, true) * 0.5,
		"the kintsugi cools down")


func test_a_single_pulse_runs_through_every_thread() -> void:
	var hops := GenesisChoreography.wave_hops()
	assert_eq(hops, 2, "MIKU's threads, then the ones leaving the bodies she reached")
	for i in [0, 4, 5, 6]:
		assert_eq(GenesisChoreography.link_hop(i), 0, "link %d leaves MIKU" % i)
	for i in [1, 2, 3, 7]:
		assert_eq(GenesisChoreography.link_hop(i), 1, "link %d leaves a body MIKU reached" % i)
	var g := _full()
	for i in GenesisScript.LINKS.size():
		var seen := 0
		var was_on := false
		var t := GenesisScript.T_STABLE
		while t <= GenesisScript.DURATION:
			var on := GenesisChoreography.wave_on_link(GenesisChoreography.stable_wave(g, t, hops), GenesisChoreography.link_hop(i)) >= 0.0
			if on and not was_on:
				seen += 1
			was_on = on
			t += 0.02
		assert_eq(seen, 1, "the pulse crosses link %d exactly once" % i)
		var done := GenesisScript.T_STABLE + GenesisChoreography.WAVE_DELAY + GenesisChoreography.WAVE_HAIR \
			+ GenesisChoreography.WAVE_HOP * GenesisChoreography.link_hop(i)
		assert_gte(done, GenesisChoreography.link_done_at(g, i), "link %d is woven when the pulse reaches it" % i)
	assert_lte(GenesisScript.T_STABLE + GenesisChoreography.WAVE_DELAY + GenesisChoreography.WAVE_HAIR
		+ GenesisChoreography.WAVE_HOP * hops, GenesisScript.DURATION, "the wave ends before the session completes")
	# It leaves her hair first: along the link strands, ending where her threads begin.
	var before := GenesisScript.T_STABLE + GenesisChoreography.WAVE_DELAY
	assert_lt(GenesisChoreography.hair_wave(g, before - 0.01), 0.0, "no hair pulse before the wave")
	assert_almost_eq(GenesisChoreography.hair_wave(g, before), 0.0, 1e-4, "the pulse leaves the root")
	var handover := before + GenesisChoreography.WAVE_HAIR
	assert_almost_eq(GenesisChoreography.hair_wave(g, handover), 1.0, 1e-4, "it reaches the strand tips...")
	assert_almost_eq(GenesisChoreography.stable_wave(g, handover, hops), 0.0, 1e-4, "...as it enters her threads")


func test_threads_end_on_the_limb() -> void:
	for i in GenesisScript.LINKS.size():
		for source in [true, false]:
			var id: StringName = GenesisScript.LINKS[i][0 if source else 1]
			var r := RelationThreads.body_radius(id)
			if r <= 0.0:
				continue
			var c := RelationThreads.body_point(i, id, 3.0)
			assert_almost_eq(RelationThreads.endpoint(i, source, 3.0).distance_to(c), r * RelationThreads.LIMB_CLEARANCE, 1e-3,
				"link %d ends on the surface of %s, not at its centre" % [i, id])
	assert_lt(RelationThreads.width_of(1), RelationThreads.width_of(0), "planet -> moon threads are the finest")


func test_limits() -> void:
	var s := CameraShots.Shot.new().setup(Vector3(0, 0, 0), 0.0, -1.4, 30.0, 40.0)
	GenesisShots.clamp_shot(s, SessionState.Mode.FORGE)
	assert_gte(s.pitch, GenesisShots.PITCH_MIN)
	assert_gte(s.position().y, GenesisShots.MIN_CAMERA_Y - 1e-3, "never below the mist")
	s.setup(Vector3(200, 0, 0), 0.0, 0.2, 500.0, 40.0)
	GenesisShots.clamp_shot(s, SessionState.Mode.UNIVERSE)
	assert_lte(Vector2(s.target.x, s.target.z).length(), GenesisShots.FLY_RADIUS + 1e-3)
	assert_lte(s.distance, GenesisShots.DISTANCE_LIMITS[SessionState.Mode.UNIVERSE].y)


func test_focus_frames_every_body() -> void:
	var cur := GenesisShots.mode_shot(SessionState.Mode.FORGE, CameraShots.Shot.new())
	var out := CameraShots.Shot.new()
	var planet := AABB(GenesisLayout.PLANET_CENTER - Vector3.ONE * 1.6, Vector3.ONE * 3.2)
	assert_true(GenesisShots.focus_reachable(planet.get_center()))
	GenesisShots.focus_shot(SessionState.Mode.FORGE, planet, cur, 16.0 / 9.0, out)
	assert_almost_eq(out.target, planet.get_center(), Vector3.ONE * 1e-4)
	assert_lt(out.distance, cur.distance, "closer than the hero shot")
	var far := AABB(GenesisLayout.far_position(1, 0.0) - Vector3.ONE * 2.0, Vector3.ONE * 4.0)
	assert_true(GenesisShots.focus_reachable(far.get_center()), "the farthest world is in reach")


func test_style_frame_poses() -> void:
	var poses := GenesisShots.style_frame_poses()
	assert_gte(StyleFrames.valid_poses(poses).size(), StyleFrames.MIN_FRAMES)
	assert_eq(StyleFrames.valid_poses(poses).size(), poses.size(), "every pose valid")
	var modes := {}
	for p in poses:
		modes[int(p["mode"])] = true
	assert_eq(modes.size(), 3, "the three modes")


# --- Layout and threads -------------------------------------------------------------------------------

func test_layout_reads_the_sculpt_anchors() -> void:
	var a := GenesisLayout.anchors("miku_body")
	for k in ["hair_root", "forehead", "chest", "head_top", "gown_hem_center"]:
		assert_true(a.get(k) is Vector3, "anchor %s" % k)
	assert_true(GenesisLayout.bounds("hand_left").size.x > 1.0)
	assert_gt(GenesisLayout.miku_point("head_top").y, GenesisLayout.miku_heart().y)
	assert_gt(GenesisLayout.miku_point("gown_hem_center").y, GenesisLayout.PLANET_CENTER.y,
		"the world sits below her hem")


func test_hands_do_not_pierce_the_world() -> void:
	for left in [true, false]:
		var name := "hand_left" if left else "hand_right"
		var xf := GenesisLayout.hand_rest(left)
		for k in ["tip_thumb", "tip_index", "tip_middle", "tip_ring", "tip_little", "palm_center"]:
			var p: Vector3 = xf * GenesisLayout.anchor(name, k)
			assert_gt(p.distance_to(GenesisLayout.PLANET_CENTER), GenesisLayout.PLANET_RADIUS + 0.05,
				"%s %s clears the final world" % [name, k])


func test_orbit_points() -> void:
	var p := GenesisLayout.orbit_point(Vector3.ZERO, 3.0, Vector3.ZERO, 0.0)
	assert_almost_eq(p, Vector3(0, 0, 3), Vector3.ONE * 1e-5, "phase 0 = +Z (OrbitLine convention)")
	for i in GenesisScript.MOON_COUNT:
		assert_almost_eq(GenesisLayout.moon_position(i, 7.0).distance_to(GenesisLayout.PLANET_CENTER),
			GenesisLayout.MOON_ORBITS[i], 1e-4)


func test_partial_thread_arc() -> void:
	var a := Vector3(0, 8, -1)
	var b := Vector3(0, 0, 3)
	var up := Vector3(-1, 0, 0.3)
	var h := a.distance_to(b) * RelationThreads.ARC
	var full := RelationThreads.partial_arc(a, b, h, up, 1.0)
	assert_almost_eq(full[0] as Vector3, b, Vector3.ONE * 1e-4, "w = 1 ends at the target")
	var half := RelationThreads.partial_arc(a, b, h, up, 0.5)
	var e: Vector3 = half[0]
	assert_almost_eq(e, RelationThread.arc_point(a, b, h, 0.5, up), Vector3.ONE * 1e-4, "grows along its own path")
	# The partial arc's midpoint stays near the full arc's quarter point.
	var mid := RelationThread.arc_point(a, e, half[1], 0.5, half[2])
	assert_lt(mid.distance_to(RelationThread.arc_point(a, b, h, 0.25, up)), 0.15)


func test_pulses_only_on_woven_threads() -> void:
	assert_eq(RelationThreads.pulse_at(0, 0.5, 3.0, 9.0), -1.0)
	var seen := false
	var m := 0.0
	while m < 20.0:
		var p := RelationThreads.pulse_at(0, 1.0, m, 9.0)
		if p >= 0.0:
			seen = true
			assert_between(p, 0.0, 1.0)
		m += 0.1
	assert_true(seen, "a pulse travels every period")


func test_the_hair_becomes_the_threads() -> void:
	# One link strand per MIKU thread, from the single root to the point where its thread begins;
	# the thread starts on the strand (overlapping its tip) in the figure's current pose.
	var curves := Miku.hair_link_curves()
	var sources := Miku.hair_sources()
	assert_eq(curves.size(), RelationThreads.MIKU_LINKS.size(), "one link strand per thread of MIKU")
	var root := GenesisLayout.anchor("miku_body", "hair_root", Miku.HAIR_ROOT_FALLBACK)
	var seen := {}
	for k in RelationThreads.MIKU_LINKS.size():
		var i: int = RelationThreads.MIKU_LINKS[k]
		assert_eq(GenesisScript.LINKS[i][0], &"miku")
		var c: PackedVector3Array = curves[k]
		assert_lt(c[0].length(), 0.25, "strand %d leaves the single root" % k)
		assert_lt(c[c.size() - 1].distance_to(sources[i]), 1e-3, "strand %d ends where its thread begins" % k)
		assert_gt(sources[i].length(), 2.0, "the thread leaves the plume, not the knot")
		seen[sources[i]] = true
		for lift in [0.0, 1.0]:
			for m in [0.0, 7.3]:
				var a := RelationThreads.endpoint(i, true, m, lift)
				var on := Miku.figure_pose(m, lift) * (root + HairRibbons.curve_point(c, 1.0 - RelationThreads.HAIR_OVERLAP))
				assert_lt(a.distance_to(on), 1e-3, "thread %d starts on its strand (lift %.0f, m %.1f)" % [i, lift, m])
	assert_eq(seen.size(), RelationThreads.MIKU_LINKS.size(), "each thread leaves from its own tuft")


func test_threads_leave_along_their_strand() -> void:
	var a := Vector3(0.0, 10.0, 0.0)
	var b := Vector3(6.0, 2.0, 4.0)
	var chord := (b - a).normalized()
	# Within the allowed angle the arc leaves exactly along the strand.
	var side := chord.cross(Vector3.UP).normalized()
	var tn := (chord * 0.8 + side * 0.6).normalized()
	var arc := RelationThreads.tangent_arc(a, b, tn)
	var t0 := RelationThread.arc_tangent(a, b, arc[0], 0.0, arc[1]).normalized()
	assert_gt(t0.dot(tn), 0.999, "the thread continues the strand's direction")
	assert_almost_eq(RelationThread.arc_point(a, b, arc[0], 1.0, arc[1]).distance_to(b), 0.0, 1e-4, "and still ends on its body")
	# A strand heading away from the body: the start is turned to the allowed angle (no U-turn loop).
	var away := (-chord * 0.6 + side * 0.8).normalized()
	arc = RelationThreads.tangent_arc(a, b, away)
	t0 = RelationThread.arc_tangent(a, b, arc[0], 0.0, arc[1]).normalized()
	assert_almost_eq(t0.dot(chord), RelationThreads.HAIR_TANGENT_MIN_COS, 1e-3, "turned towards the body")
	assert_gt(t0.dot(side), 0.0, "on the strand's side")


func test_exposure_trim_follows_the_belt_rise() -> void:
	var g := _full()
	assert_almost_eq(GenesisShots.cue_trim(_state_at(20.0), 20.0), 1.0, 1e-6, "no trim before the rise")
	var top := GenesisScript.MOON_TIMES[0] + GenesisShots.RISE_DUR
	assert_almost_eq(GenesisShots.cue_trim(_state_at(top - 0.5), top - 0.5), GenesisShots.TRIM_RISE, 1e-3,
		"the rise over the belt is compensated")
	assert_almost_eq(GenesisShots.cue_trim(g, GenesisScript.DURATION), 1.0, 1e-6, "back to the mode's exposure at the end")


func test_reveal_comes_from_the_light() -> void:
	var g := _full()
	assert_eq(GenesisChoreography.reveal_glow(_state_at(2.0), 2.0), 0.0, "nothing glows in the dark")
	assert_eq(GenesisChoreography.gown_presence(_state_at(2.0), 2.0), 0.0, "in the dark the gown is only dust")
	var mid := GenesisScript.T_AWAKEN + GenesisChoreography.REVEAL_DELAY + GenesisChoreography.REVEAL_DUR * 0.5
	assert_gt(GenesisChoreography.reveal_glow(g, mid), 0.9, "she is revealed as light")
	assert_lt(GenesisChoreography.gown_presence(g, GenesisScript.T_AWAKEN + GenesisChoreography.REVEAL_DELAY + 0.3), 0.01,
		"no veil before the reveal reaches the skirt")
	assert_lt(GenesisChoreography.hair_reveal(g, GenesisScript.T_AWAKEN + 0.5), GenesisChoreography.HAIR_ASLEEP + 1e-6,
		"no comet of hair in the dark: it is spun out once the light reveals her")
