extends GutTest
## CameraShots: framing per mode, event cues, limits (never through the floor) and blending.

const Mode := SessionState.Mode
## Height of the structure including ribs (StructureBlueprint.rib_mesh_params()["height"]).
var _structure_h: float


func before_all() -> void:
	_structure_h = float(StructureBlueprint.build().rib_mesh_params()["height"])


func _world(t: float) -> WorldState:
	var upto: Array[SimEvent] = []
	for e in OriginChamberScript.build():
		if e.time <= t:
			upto.append(e)
	return WorldState.derive(upto)


func _shot() -> CameraShots.Shot:
	return CameraShots.Shot.new()


## NDC (x, y) of a world point for a shot (ignoring h_offset), and its view depth.
func _project(s: CameraShots.Shot, p: Vector3) -> Vector3:
	var xf := Transform3D(Basis.IDENTITY, s.position()).looking_at(s.target, Vector3.UP)
	var local := xf.affine_inverse() * p
	var depth := -local.z
	var tan_half := tan(deg_to_rad(s.fov) * 0.5)
	return Vector3(local.x / depth / (tan_half * 16.0 / 9.0), local.y / depth / tan_half, depth)


func test_mode_shots_are_within_limits() -> void:
	for m in [Mode.UNIVERSE, Mode.FORGE, Mode.OBSERVATORY]:
		var s := CameraShots.mode_shot(m, _shot())
		var c := _shot().copy_from(s)
		CameraShots.clamp_shot(c, m)
		assert_true(c.approx_equals(s), "mode %d shot already clamped" % m)
		assert_gt(s.position().y, CameraShots.FLOOR_Y + CameraShots.FLOOR_CLEARANCE - 1e-4)


func test_forge_framing() -> void:
	var s := CameraShots.mode_shot(Mode.FORGE, _shot())
	var frame_h := 2.0 * s.distance * tan(deg_to_rad(s.fov) * 0.5)
	assert_between(_structure_h / frame_h, 0.45, 0.65, "structure fills ~55% of the height")
	var core := _project(s, Vector3.ZERO)
	assert_between(core.y, 0.02, 0.3, "core slightly above the optical centre")
	assert_almost_eq(core.x, 0.0, 1e-4)
	# Low horizon: the horizon (camera eye level, far away) sits on or below the centre.
	var far := s.position() + Vector3(-sin(s.yaw), 0.0, -cos(s.yaw)) * 1000.0
	assert_lt(_project(s, far).y, 0.25)


func test_universe_is_far_out_and_between_pillars() -> void:
	var s := CameraShots.mode_shot(Mode.UNIVERSE, _shot())
	var lim: Vector2 = CameraShots.DISTANCE_LIMITS[Mode.UNIVERSE]
	assert_between(s.distance, lim.x, lim.y, "inside the UNIVERSE distance limits")
	var flat := Vector2(s.position().x, s.position().z).length()
	assert_gt(flat, ChamberArchitecture.PILLAR_RADIUS + 20.0, "camera stands well outside the pillar ring")
	# Between pillars: the yaw is at least 40 % of the half gap away from every pillar.
	var half_gap := PI / float(ChamberArchitecture.PILLAR_COUNT)
	for p in ChamberArchitecture.PILLAR_COUNT:
		var d := absf(angle_difference(s.yaw, ChamberArchitecture.pillar_angle(p)))
		assert_gt(d, half_gap * 0.4, "yaw clear of pillar %d" % p)


func test_universe_frames_chamber_among_seeds() -> void:
	var s := CameraShots.mode_shot(Mode.UNIVERSE, _shot())
	var chamber := _project(s, Vector3.ZERO)
	assert_between(chamber.x, -0.15, 0.15, "chamber near the horizontal centre")
	assert_between(chamber.y, -0.4, 0.1, "chamber in the lower middle")
	var xs: Array[float] = []
	for seed_def: Dictionary in Universe.SEEDS:
		var p := _project(s, Universe.seed_base_position(seed_def))
		assert_gt(p.z, 0.0, "%s in front of the camera" % seed_def["id"])
		assert_between(p.x, -0.9, 0.9, "%s inside the frame (x)" % seed_def["id"])
		assert_between(p.y, chamber.y + 0.05, 0.9, "%s inside the frame, above the chamber" % seed_def["id"])
		xs.append(p.x)
	xs.sort()
	assert_lt(xs[0], chamber.x, "a seed on the left of the chamber")
	assert_gt(xs[xs.size() - 1], chamber.x, "a seed on the right of the chamber")
	# No near pillar reaches the structure on screen: every pillar in front of the chamber has its
	# top below the structure's lower edge (or stays clear of it horizontally).
	var bottom := _project(s, Vector3(0.0, -_structure_h * 0.5, 0.0)).y
	# Half width of the structure on screen: a point at the widest ring radius, camera-right.
	var right := Vector3(cos(s.yaw), 0.0, -sin(s.yaw))
	var half_w := absf(_project(s, right * 3.2).x - chamber.x)
	for p in ChamberArchitecture.PILLAR_COUNT:
		var xf := ChamberArchitecture.pillar_transform(p)
		var top := _project(s, xf.origin + Vector3(0.0, ChamberArchitecture.PILLAR_SIZE.y * 0.5, 0.0))
		if top.z >= chamber.z:
			continue
		var clear_x := absf(top.x - chamber.x) > half_w
		assert_true(clear_x or top.y < bottom, "near pillar %d does not cut the structure" % p)


func test_observatory_pushes_subject_right() -> void:
	var s := CameraShots.mode_shot(Mode.OBSERVATORY, _shot())
	var f := CameraShots.mode_shot(Mode.FORGE, _shot())
	assert_gt(s.offset, 0.2, "subject in the right part (panel ~38% on the left)")
	assert_lt(s.h_offset(16.0 / 9.0), 0.0, "camera shifts left so the subject moves right")
	assert_gt(s.pitch, f.pitch + 0.3, "high, oblique view")


func test_cues_follow_the_story() -> void:
	var expected := [
		[0.5, CameraShots.CUE_DORMANT], [3.0, CameraShots.CUE_ACTIVATION], [8.5, CameraShots.CUE_FRAGMENTS],
		[19.5, CameraShots.CUE_BUILDING], [30.5, CameraShots.CUE_FINISHING],
		[37.0, CameraShots.CUE_VERIFICATION], [49.0, CameraShots.CUE_FINAL],
	]
	for e in expected:
		var s := _shot()
		var id := CameraShots.desired(Mode.FORGE, true, _world(e[0]), e[0], s)
		assert_eq(id, e[1], "cue at t=%.1f" % e[0])
		assert_gt(s.position().y, CameraShots.FLOOR_Y + CameraShots.FLOOR_CLEARANCE - 1e-4)
	var act := _shot()
	var frag := _shot()
	var verify := _shot()
	CameraShots.cue(_world(3.0), 3.0, act)
	CameraShots.cue(_world(8.5), 8.5, frag)
	CameraShots.cue(_world(37.0), 37.0, verify)
	var base := CameraShots.mode_shot(Mode.FORGE, _shot())
	assert_lt(act.distance, base.distance, "activation: approach")
	assert_gt(frag.distance, base.distance, "fragments: pull back")
	assert_lt(verify.pitch, 0.0, "verification: low angle")


func test_final_cue_orbits_slowly() -> void:
	var w := _world(50.0)
	var a := _shot()
	var b := _shot()
	CameraShots.cue(w, 46.0, a)
	CameraShots.cue(w, 50.0, b)
	var d := angle_difference(a.yaw, b.yaw)
	assert_between(d, 0.05, 0.5, "slow orbital reveal")


func test_non_cinematic_and_other_modes_use_mode_shots() -> void:
	var w := _world(20.0)
	for m in [Mode.UNIVERSE, Mode.FORGE, Mode.OBSERVATORY]:
		var s := _shot()
		var id := CameraShots.desired(m, false, w, 20.0, s)
		assert_eq(id, StringName("mode_%d" % m))
		assert_true(s.approx_equals(CameraShots.mode_shot(m, _shot())))
	assert_eq(CameraShots.desired(Mode.UNIVERSE, true, w, 20.0, _shot()), StringName("mode_%d" % Mode.UNIVERSE),
		"cues are FORGE only")


func test_build_orbit_is_continuous() -> void:
	var w := _world(50.0)
	var prev := CameraShots.build_yaw(w, 0.0)
	var t := 0.0
	while t < 50.0:
		var y := CameraShots.build_yaw(w, t)
		assert_true(absf(y - prev) < 0.01, "build yaw continuous at %.1f" % t)
		prev = y
		t += 0.05


func test_clamp_never_goes_through_the_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 400:
		var m: int = [Mode.UNIVERSE, Mode.FORGE, Mode.OBSERVATORY][i % 3]
		var s := _shot().setup(Vector3(rng.randf_range(-90, 90), rng.randf_range(-6, 4), rng.randf_range(-90, 90)),
			rng.randf_range(-PI, PI), rng.randf_range(-1.6, 1.6), rng.randf_range(0.5, 300.0), 40.0)
		CameraShots.clamp_shot(s, m)
		var lim: Vector2 = CameraShots.DISTANCE_LIMITS[m]
		assert_between(s.distance, lim.x, lim.y)
		assert_between(s.pitch, CameraShots.PITCH_MIN, CameraShots.PITCH_MAX)
		assert_true(s.position().y >= CameraShots.FLOOR_Y + CameraShots.FLOOR_CLEARANCE - 1e-3,
			"camera above the floor (%s)" % s.position())
		assert_true(Vector2(s.target.x, s.target.z).length() <= CameraShots.FLY_RADIUS + 1e-3)


func test_blend_endpoints_and_shortest_yaw() -> void:
	var a := _shot().setup(Vector3(1, 0, 0), 3.0, 0.1, 10.0, 30.0, 0.0)
	var b := _shot().setup(Vector3(0, 2, 0), -3.0, 0.5, 20.0, 50.0, 0.4)
	var out := _shot()
	assert_true(CameraShots.blend(a, b, 0.0, out).approx_equals(a))
	assert_true(CameraShots.blend(a, b, 1.0, out).approx_equals(b))
	CameraShots.blend(a, b, 0.5, out)
	assert_gt(absf(out.yaw), 3.0, "yaw crosses PI (shortest arc), not through 0")
	assert_almost_eq(out.distance, 15.0, 1e-5)
