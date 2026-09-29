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


# --- Focus framing (Session.focus_requested) ---------------------------------------------------

const ASPECT := 16.0 / 9.0


## Round entity bounds: a ring/sphere of radius r and height h centred at c.
func _round(c: Vector3, r: float, h: float) -> AABB:
	return AABB(c - Vector3(r, h * 0.5, r), Vector3(2.0 * r, h, 2.0 * r))


## Largest |NDC| (x, y) reached by the silhouette of a vertical cylinder (radius r, height h,
## centre c) seen from shot s, relative to the subject (before the screen offset): samples its rims.
func _extent(s: CameraShots.Shot, c: Vector3, r: float, h: float) -> Vector2:
	var m := Vector2.ZERO
	for k in 72:
		var a := TAU * float(k) / 72.0
		for dy: float in [-h * 0.5, h * 0.5]:
			var p := _project(s, c + Vector3(sin(a) * r, dy, cos(a) * r))
			m.x = maxf(m.x, absf(p.x))
			m.y = maxf(m.y, absf(p.y))
	return m


func test_fit_distance_fills_the_frame() -> void:
	for pitch: float in [0.0, 0.3, 0.62]:
		for dims: Vector2 in [Vector2(3.05, 0.19), Vector2(0.55, 1.1), Vector2(4.0, 4.4)]:
			var b := _round(Vector3.ZERO, dims.x, dims.y)
			var d := CameraShots.fit_distance(b, pitch, 36.0, 0.0, ASPECT)
			var s := _shot().setup(Vector3.ZERO, 0.4, pitch, d, 36.0)
			var e := _extent(s, Vector3.ZERO, dims.x, dims.y)
			var tight := maxf(e.x, e.y)
			# The fit is on the silhouette at the target depth; near rims of big rings reach a bit further.
			assert_between(tight, CameraShots.FOCUS_FILL * 0.85, CameraShots.FOCUS_FILL * 1.3,
				"pitch %.2f dims %s fills ~FOCUS_FILL (%.2f)" % [pitch, dims, tight])
			assert_lt(tight, 1.0, "entity entirely in frame")
	var small := CameraShots.fit_distance(_round(Vector3.ZERO, 1.0, 0.2), 0.3, 36.0, 0.0, ASPECT)
	var big := CameraShots.fit_distance(_round(Vector3.ZERO, 2.0, 0.2), 0.3, 36.0, 0.0, ASPECT)
	assert_gt(big, small * 1.5, "bigger entity, farther camera")
	var shifted := CameraShots.fit_distance(_round(Vector3.ZERO, 2.0, 0.2), 0.0, 36.0, 0.38, ASPECT)
	var centred := CameraShots.fit_distance(_round(Vector3.ZERO, 2.0, 0.2), 0.0, 36.0, 0.0, ASPECT)
	assert_gte(shifted, centred, "a shifted subject has less room")


func test_focus_keeps_the_mode_and_centres_the_entity() -> void:
	var layer := _round(Vector3(0.0, 0.9, 0.0), 2.8, 0.19)
	for m: int in [Mode.FORGE, Mode.OBSERVATORY]:
		var current := CameraShots.mode_shot(m, _shot())
		var s := CameraShots.focus_shot(m, layer, current, ASPECT, _shot())
		var base := CameraShots.mode_shot(m, _shot())
		assert_almost_eq(s.fov, base.fov, 1e-5, "mode %d keeps its fov" % m)
		assert_almost_eq(s.offset, base.offset, 1e-5, "mode %d keeps its screen offset" % m)
		assert_almost_eq(absf(angle_difference(s.yaw, current.yaw)), 0.0, 1e-5, "keeps the current yaw")
		assert_true(s.target.is_equal_approx(layer.get_center()), "targets the entity centre")
		var c := _shot().copy_from(s)
		assert_true(CameraShots.clamp_shot(c, m).approx_equals(s), "inside the mode limits")
		var lim: Vector2 = CameraShots.DISTANCE_LIMITS[m]
		assert_lt(s.distance, lim.y, "closer than the widest framing")
		var p := _project(s, layer.get_center())
		assert_almost_eq(p.x, 0.0, 1e-4)
		assert_almost_eq(p.y, 0.0, 1e-4)
	var forge := CameraShots.focus_shot(Mode.FORGE, layer, CameraShots.mode_shot(Mode.FORGE, _shot()), ASPECT, _shot())
	assert_gte(forge.pitch, CameraShots.FOCUS_MIN_PITCH, "FORGE looks down on a ring")
	var obs := CameraShots.focus_shot(Mode.OBSERVATORY, layer, CameraShots.mode_shot(Mode.OBSERVATORY, _shot()), ASPECT, _shot())
	assert_gt(obs.offset, 0.2, "OBSERVATORY keeps the subject right of the panel")


func test_focus_distance_limited_to_the_chamber() -> void:
	# The whole chamber (pillar ring) from FORGE: framed from inside, at the FORGE limit.
	var chamber := ChamberArchitecture.focus_bounds()
	var s := CameraShots.focus_shot(Mode.FORGE, chamber, CameraShots.mode_shot(Mode.FORGE, _shot()), ASPECT, _shot())
	assert_almost_eq(s.distance, CameraShots.DISTANCE_LIMITS[Mode.FORGE].y, 1e-4)
	# A tiny entity never brings the camera closer than the mode allows.
	var tiny := CameraShots.focus_shot(Mode.FORGE, _round(Vector3.ZERO, 0.05, 0.05), _shot(), ASPECT, _shot())
	assert_almost_eq(tiny.distance, CameraShots.DISTANCE_LIMITS[Mode.FORGE].x, 1e-4)


func test_focus_reach_per_mode() -> void:
	for seed_def: Dictionary in Universe.SEEDS:
		var p := Universe.seed_base_position(seed_def)
		assert_true(CameraShots.focus_reachable(Mode.UNIVERSE, p), "%s reachable in UNIVERSE" % seed_def["id"])
		assert_false(CameraShots.focus_reachable(Mode.FORGE, p), "%s out of reach in FORGE" % seed_def["id"])
		assert_false(CameraShots.focus_reachable(Mode.OBSERVATORY, p), "%s out of reach in OBSERVATORY" % seed_def["id"])
	for m: int in [Mode.UNIVERSE, Mode.FORGE, Mode.OBSERVATORY]:
		assert_true(CameraShots.focus_reachable(m, Vector3(0.0, 0.9, 0.0)), "chamber entities reachable in mode %d" % m)


func test_universe_seed_focus_keeps_the_chamber_in_the_background() -> void:
	for seed_def: Dictionary in Universe.SEEDS:
		var size := float(seed_def["size"])
		var centre := Universe.seed_base_position(seed_def)
		var b := _round(centre, size * 1.9, size * 2.0)
		var current := CameraShots.mode_shot(Mode.UNIVERSE, _shot())
		var s := CameraShots.focus_shot(Mode.UNIVERSE, b, current, ASPECT, _shot())
		var id: StringName = seed_def["id"]
		assert_true(s.target.is_equal_approx(centre), "%s: target is the seed (not clamped)" % id)
		var lim: Vector2 = CameraShots.DISTANCE_LIMITS[Mode.UNIVERSE]
		assert_between(s.distance, lim.x, 40.0, "%s: close to the seed" % id)
		assert_gt(s.position().y, CameraShots.FLOOR_Y + CameraShots.FLOOR_CLEARANCE)
		var e := _extent(s, centre, size * 1.9, size * 2.0)
		assert_lt(maxf(e.x, e.y), 0.9, "%s: whole seed in frame" % id)
		assert_lt(s.offset, 0.0, "%s: seed on the left third" % id)
		assert_lt(maxf(e.x + absf(s.offset), e.y), 0.95, "%s: whole seed in frame with its offset" % id)
		# Screen x = projected x + offset (Camera3D.h_offset shifts the whole image).
		var chamber := _project(s, Vector3.ZERO)
		var cx := chamber.x + s.offset
		assert_gt(chamber.z, s.distance + 20.0, "%s: chamber far behind the seed" % id)
		assert_between(cx, 0.2, 0.8, "%s: chamber on the right third (%.2f)" % [id, cx])
		assert_between(chamber.y, -0.7, 0.7, "%s: chamber in frame (y %.2f)" % [id, chamber.y])
		assert_gt(chamber.x, e.x + 0.1, "%s: chamber beside the seed, not behind it" % id)
