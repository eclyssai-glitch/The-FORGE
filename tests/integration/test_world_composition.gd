extends GutTest
## World composition: environment, quality and mode wiring, missing modules, universe seeds and
## picking. Works whether or not the animator's modules (entities/fx/camera) are present.

const WorldScene := preload("res://scenes/world.tscn")
const WorldScript := preload("res://src/world/world.gd")

var world: WorldScript
var _prev_level: QualityProfiles.Level
var _prev_auto: bool
var _prev_mode: SessionState.Mode


func before_each() -> void:
	_prev_level = Quality.level
	_prev_auto = Quality.auto
	_prev_mode = Session.mode
	world = WorldScene.instantiate()
	add_child_autofree(world)


func after_each() -> void:
	Quality.override_for_session(_prev_level)
	Quality.auto = _prev_auto
	Session.set_mode(_prev_mode)
	Session.select(&"")
	Session.hover(&"")


func test_environment_is_configured() -> void:
	var we := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert_not_null(we, "WorldEnvironment exists")
	var env: Environment = world.environment
	assert_not_null(env)
	assert_eq(we.environment, env)
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_true(env.fog_enabled, "depth fog on")
	assert_eq(env.background_mode, Environment.BG_SKY, "universe sky installed")
	assert_not_null(env.sky)
	assert_eq(env.sky.sky_material, world.universe.sky_material)


func test_loop1_skeleton_is_gone() -> void:
	assert_eq(world.find_children("*", "OmniLight3D", false, false).size(), 0, "no loose EMBER omni light at the world root")
	assert_eq(world.find_children("*", "MeshInstance3D", false, false).size(), 0, "no placeholder sphere at the world root")


func test_missing_module_is_skipped() -> void:
	assert_null(WorldScript.load_module("res://src/entities/__does_not_exist__.gd"))
	assert_null(WorldScript.load_module("res://src/world/quality_profiles.gd"), "RefCounted is not a module")


func test_present_modules_are_composed_in_order() -> void:
	var last := -1
	for m in WorldScript.MODULES:
		var node := world.get_node_or_null(NodePath(m[0]))
		assert_eq(node != null, ResourceLoader.exists(m[1]), "%s present iff its script exists" % m[0])
		if node:
			assert_gt(node.get_index(), last, "%s after the previous module" % m[0])
			last = node.get_index()
	assert_gt(world.universe.get_index(), last, "universe after the chamber modules")
	assert_eq(world.picker.get_index(), world.get_child_count() - 1, "picker is last")


func test_there_is_always_a_current_camera() -> void:
	var cam := world.get_viewport().get_camera_3d()
	assert_not_null(cam)
	assert_true(world.is_ancestor_of(cam), "the active camera belongs to the world")
	if ResourceLoader.exists(WorldScript.CAMERA_DIRECTOR[1]):
		assert_null(world.fallback_camera)
		assert_true(world.modules["CameraDirector"].is_in_group(WorldScript.CAMERA_GROUP))
	else:
		assert_eq(cam, world.fallback_camera)


func test_quality_toggles_costly_effects() -> void:
	var env: Environment = world.environment
	Quality.override_for_session(QualityProfiles.Level.LOW)
	assert_false(env.ssao_enabled, "LOW: no SSAO")
	assert_false(env.volumetric_fog_enabled, "LOW: no volumetric fog")
	assert_false(env.ssil_enabled)
	Quality.override_for_session(QualityProfiles.Level.ULTRA)
	assert_true(env.ssao_enabled, "ULTRA: SSAO")
	assert_true(env.volumetric_fog_enabled, "ULTRA: volumetric fog")
	assert_true(env.ssil_enabled, "ULTRA: SSIL")


func test_mode_changes_fog() -> void:
	var env: Environment = world.environment
	Session.set_mode(SessionState.Mode.FORGE)
	var forge_end := env.fog_depth_end
	Session.set_mode(SessionState.Mode.UNIVERSE)
	assert_eq(env.fog_depth_end, float(EnvironmentProfile.mode_fog(SessionState.Mode.UNIVERSE)["fog_depth_end"]))
	assert_gt(env.fog_depth_end, forge_end, "UNIVERSE sees farther than FORGE")


func test_universe_has_three_pickable_seeds() -> void:
	Session.set_mode(SessionState.Mode.UNIVERSE)
	var u: Universe = world.universe
	assert_eq(u.seed_ids(), [&"seed_aurel", &"seed_vesper", &"seed_lattice"] as Array[StringName])
	for id in u.seed_ids():
		var root := u.seed_node(id)
		assert_not_null(root, String(id))
		var d := root.global_position.length()
		assert_between(d, 60.0, 72.0, "%s distance from the chamber" % id)
		var horizontal := Vector2(root.global_position.x, root.global_position.z).length()
		assert_gt(horizontal, 40.0, "%s beyond the chamber floor (radius 34)" % id)
		var bodies := root.find_children("*", "StaticBody3D", true, false)
		assert_eq(bodies.size(), 1, "%s has one pick body" % id)
		var body := bodies[0] as StaticBody3D
		assert_eq(body.collision_layer, 2)
		assert_eq(body.get_meta(&"entity_id"), id)
		var shapes := body.find_children("*", "CollisionShape3D", true, false)
		assert_eq(shapes.size(), 1)
		assert_not_null((shapes[0] as CollisionShape3D).shape)
		assert_true(EntityCatalog.all_ids().has(id), "%s is a catalog entity" % id)


func test_seed_rings_are_tilted_never_upright() -> void:
	var u: Universe = world.universe
	for id in u.seed_ids():
		var rings := u.seed_node(id).get_node("Rings")
		assert_gt(rings.get_child_count(), 0, "%s has halo rings" % id)
		for ring: Node3D in rings.get_children():
			var normal := ring.transform.basis.y.normalized()
			assert_gt(absf(normal.dot(Vector3.UP)), 0.7, "%s/%s is not an upright ring" % [id, ring.name])


func test_star_intensity_follows_mode() -> void:
	var sky: ShaderMaterial = world.universe.sky_material
	for mode: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.FORGE, SessionState.Mode.OBSERVATORY]:
		Session.set_mode(mode)
		assert_almost_eq(float(sky.get_shader_parameter("star_intensity")), Universe.star_intensity_for(mode), 1e-5)
	assert_gt(Universe.star_intensity_for(SessionState.Mode.UNIVERSE), Universe.star_intensity_for(SessionState.Mode.OBSERVATORY))
	assert_gt(Universe.star_intensity_for(SessionState.Mode.OBSERVATORY), Universe.star_intensity_for(SessionState.Mode.FORGE))


func test_sky_radiance_pass_has_a_lift() -> void:
	var names: Array = []
	for u: Dictionary in world.universe.sky_material.shader.get_shader_uniform_list():
		names.append(u["name"])
	assert_has(names, "radiance_lift", "reflection cubemap is not pure VOID")


func test_module_report_matches_scripts() -> void:
	var names := WorldScript.expected_module_names()
	assert_eq(names.size(), WorldScript.MODULES.size() + 1, "MODULES + CameraDirector")
	assert_eq(names[-1], String(WorldScript.CAMERA_DIRECTOR[0]))
	var missing := world.missing_modules()
	for m in WorldScript.MODULES + [WorldScript.CAMERA_DIRECTOR]:
		assert_eq(missing.has(String(m[0])), not ResourceLoader.exists(m[1]), "%s missing iff its script is absent" % m[0])


func test_seeds_drift_slowly_within_range() -> void:
	var u: Universe = world.universe
	var root := u.seed_node(&"seed_vesper")
	var before := root.position
	u._process(7.0)
	var moved := root.position.distance_to(before)
	assert_gt(moved, 0.0, "seeds drift")
	assert_lt(moved, 1.0, "drift is slight")
	for t in [0.0, 13.0, 29.0, 61.0]:
		assert_lt(Universe.drift_offset(t, 1.0).length(), Universe.DRIFT_AMPLITUDE * 1.2)


func test_picker_click_logic() -> void:
	assert_eq(InputTuning.DRAG_THRESHOLD_PX, 4.0)
	assert_true(Picker.is_click_path(PackedVector2Array([Vector2(100, 100), Vector2(103, 100)])), "3 px is a click")
	assert_false(Picker.is_click_path(PackedVector2Array([Vector2(100, 100), Vector2(105, 100)])), "5 px is a drag")
	var round_trip := PackedVector2Array([Vector2(100, 100), Vector2(180, 100), Vector2(100, 100)])
	assert_almost_eq(Picker.path_length(round_trip), 160.0, 1e-4)
	assert_false(Picker.is_click_path(round_trip), "a drag back to the press point is still a drag")
	assert_true(InputTuning.is_drag(InputTuning.DRAG_THRESHOLD_PX))
	assert_false(InputTuning.is_drag(InputTuning.DRAG_THRESHOLD_PX - 0.01))
	assert_eq(Picker.entity_id_of_hit({}), &"")
	var body := StaticBody3D.new()
	body.set_meta(&"entity_id", &"seed_aurel")
	assert_eq(Picker.entity_id_of(body), &"seed_aurel")
	var child := StaticBody3D.new()
	body.add_child(child)
	assert_eq(Picker.entity_id_of(child), &"seed_aurel", "falls back to the parent's meta")
	body.free()


func test_picker_raycast_hits_seed_and_misses_void() -> void:
	Session.set_mode(SessionState.Mode.UNIVERSE)
	await wait_physics_frames(2)
	var target := world.universe.seed_node(&"seed_lattice").global_position
	var from := target + Vector3(0.0, 0.0, 12.0)
	assert_eq(world.picker.pick_ray(from, target), &"seed_lattice")
	assert_eq(world.picker.pick_ray(Vector3(0, 200, 0), Vector3(0, 400, 0)), &"", "empty space")


func test_click_selects_and_empty_click_clears() -> void:
	Session.set_mode(SessionState.Mode.UNIVERSE)
	var cam := Camera3D.new()
	world.add_child(cam)
	var target := world.universe.seed_node(&"seed_aurel").global_position
	cam.global_position = target + Vector3(0.0, 0.0, 10.0)
	cam.look_at(target)
	cam.make_current()
	await wait_physics_frames(2)
	var center := world.get_viewport().get_visible_rect().size * 0.5
	_click(center, center + Vector2(3, 0))
	await wait_physics_frames(2)
	assert_eq(Session.selected, &"seed_aurel", "a 3 px click on a seed selects it")
	# A drag (orbit) does not change the selection.
	_click(Vector2(1, 1), Vector2(80, 1))
	await wait_physics_frames(2)
	assert_eq(Session.selected, &"seed_aurel")
	# A 160 px round-trip drag that ends in the void where it started is still a drag.
	cam.look_at(target + Vector3(0.0, 40.0, 0.0))
	_click(center, center, [center + Vector2(80, 0)])
	await wait_physics_frames(2)
	assert_eq(Session.selected, &"seed_aurel", "round-trip drag does not clear the selection")
	cam.look_at(target)
	Session.select(&"")
	_click(center, center, [center + Vector2(80, 0)])
	await wait_physics_frames(2)
	assert_eq(Session.selected, &"", "round-trip drag over a seed does not select it")
	# Click in the void clears the selection.
	cam.look_at(target + Vector3(0.0, 40.0, 0.0))
	_click(center, center)
	await wait_physics_frames(2)
	assert_eq(Session.selected, &"")


func test_seed_roots_join_their_entity_group() -> void:
	var u: Universe = world.universe
	for id in u.seed_ids():
		var group := SessionState.entity_group(id)
		assert_eq(group, StringName("entity_" + String(id)))
		var nodes := get_tree().get_nodes_in_group(group)
		assert_eq(nodes.size(), 1, "%s: one node in its entity group" % id)
		if nodes.size() == 1:
			assert_eq(nodes[0], u.seed_node(id), "%s: the group holds the seed root (moves with the drift)" % id)


func test_seeds_pickable_only_in_universe() -> void:
	assert_true(Universe.seeds_pickable_in(SessionState.Mode.UNIVERSE))
	assert_false(Universe.seeds_pickable_in(SessionState.Mode.FORGE))
	assert_false(Universe.seeds_pickable_in(SessionState.Mode.OBSERVATORY))
	var u: Universe = world.universe
	for mode: SessionState.Mode in [SessionState.Mode.FORGE, SessionState.Mode.UNIVERSE, SessionState.Mode.OBSERVATORY, SessionState.Mode.UNIVERSE]:
		Session.set_mode(mode)
		assert_eq(u.seeds_pickable(), mode == SessionState.Mode.UNIVERSE, "pickable in %s" % Session.mode_name())
		for id in u.seed_ids():
			var body := u.seed_node(id).get_node("Pick") as StaticBody3D
			assert_eq(body.collision_layer, Universe.PICK_LAYER if mode == SessionState.Mode.UNIVERSE else 0,
				"%s layer in %s" % [id, Session.mode_name()])
	# Every seed lies beyond the end of the FORGE/OBSERVATORY depth fog: invisible there.
	var forge_end := float(EnvironmentProfile.mode_fog(SessionState.Mode.FORGE)["fog_depth_end"])
	var obs_end := float(EnvironmentProfile.mode_fog(SessionState.Mode.OBSERVATORY)["fog_depth_end"])
	for s in Universe.SEEDS:
		assert_gt(Universe.seed_base_position(s).length() - float(s["size"]) * Universe.PICK_RADIUS_SCALE,
			maxf(forge_end, obs_end), "%s beyond the fog end" % s["id"])


## Loop 2 audit: seeds hidden by the fog must not be selectable from the FORGE camera. The camera
## sits on the FORGE mode shot (CameraShots.mode_shot) and turns straight at each seed.
func test_forge_camera_cannot_pick_hidden_seeds() -> void:
	var shot := CameraShots.mode_shot(SessionState.Mode.FORGE, CameraShots.Shot.new())
	var cam := Camera3D.new()
	cam.fov = shot.fov
	cam.far = 600.0
	world.add_child(cam)
	cam.global_position = shot.position()
	cam.make_current()
	var center := world.get_viewport().get_visible_rect().size * 0.5
	var u: Universe = world.universe
	for id in u.seed_ids():
		cam.look_at(u.seed_node(id).global_position)
		Session.set_mode(SessionState.Mode.FORGE)
		await wait_physics_frames(2)
		assert_ne(world.picker.pick_at(center), id, "%s not pickable from the FORGE camera in FORGE" % id)
		assert_eq(world.picker.pick_ray(cam.global_position, u.seed_node(id).global_position), &"",
			"%s: nothing pickable on the ray to it in FORGE" % id)
		Session.set_mode(SessionState.Mode.OBSERVATORY)
		await wait_physics_frames(2)
		assert_ne(world.picker.pick_at(center), id, "%s not pickable in OBSERVATORY" % id)
		Session.set_mode(SessionState.Mode.UNIVERSE)
		await wait_physics_frames(2)
		assert_eq(world.picker.pick_at(center), id, "%s pickable along the same ray in UNIVERSE" % id)
	# The whole FORGE frame (mode shot, not turned) never yields a seed.
	Session.set_mode(SessionState.Mode.FORGE)
	cam.look_at(shot.target)
	await wait_physics_frames(2)
	var size := world.get_viewport().get_visible_rect().size
	for gx in 17:
		for gy in 9:
			var hit := world.picker.pick_at(Vector2(size.x * (gx + 0.5) / 17.0, size.y * (gy + 0.5) / 9.0))
			assert_false(String(hit).begins_with("seed_"), "FORGE frame picks no seed (%d,%d)" % [gx, gy])


## From the UNIVERSE mode shot a click on each seed selects it. (Whether every seed falls inside
## the frame is the animator's framing, tested with CameraShots; here the ray is what matters.)
func test_universe_camera_picks_seeds() -> void:
	Session.set_mode(SessionState.Mode.UNIVERSE)
	var shot := CameraShots.mode_shot(SessionState.Mode.UNIVERSE, CameraShots.Shot.new())
	var cam := Camera3D.new()
	cam.fov = shot.fov
	cam.far = 600.0
	world.add_child(cam)
	cam.global_position = shot.position()
	cam.look_at(shot.target)
	cam.make_current()
	await wait_physics_frames(2)
	var u: Universe = world.universe
	for id in u.seed_ids():
		var p := u.seed_node(id).global_position
		assert_false(cam.is_position_behind(p), "%s in front of the UNIVERSE camera" % id)
		assert_eq(world.picker.pick_at(cam.unproject_position(p)), id, "%s picked in UNIVERSE" % id)


func _click(press: Vector2, release: Vector2, via: Array = []) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = press
	world.picker._unhandled_input(down)
	var last := press
	for p: Vector2 in via + [release]:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.relative = p - last
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		world.picker._unhandled_input(mm)
		last = p
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = release
	world.picker._unhandled_input(up)
