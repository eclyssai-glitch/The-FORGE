extends GutTest
## Entities, FX and camera compose headless exactly as world.gd will (load(path).new() +
## add_child, no arguments), follow Simulation.seek and expose the pick bodies and camera API.

const PATHS: Array[String] = [
	"res://src/entities/light_rig.gd", "res://src/entities/chamber_architecture.gd",
	"res://src/entities/origin_core.gd", "res://src/entities/fragment_structure.gd",
	"res://src/entities/verification_array.gd", "res://src/fx/activation_pulse.gd",
	"res://src/fx/dust_field.gd", "res://src/fx/emission_sparks.gd",
	"res://src/animation/camera_director.gd",
]

var _root: Node3D
var _env: Environment
var _nodes: Dictionary = {}


func before_each() -> void:
	Simulation.reset()
	Session.set_mode(SessionState.Mode.FORGE)
	_root = Node3D.new()
	_env = EnvironmentProfile.make_environment()
	for p in PATHS:
		var node: Node = load(p).new()
		if p.ends_with("light_rig.gd"):
			node.set("environment", _env)
		_root.add_child(node)
		_nodes[p.get_file().get_basename()] = node
	add_child_autofree(_root)


func after_each() -> void:
	Simulation.reset()
	Session.select(&"")
	Session.hover(&"")
	Session.set_mode(SessionState.Mode.FORGE)
	_nodes.clear()


func _bodies(n: Node, out: Dictionary) -> Dictionary:
	if n is StaticBody3D and n.has_meta("entity_id"):
		out[n.get_meta("entity_id")] = n
		assert_eq((n as StaticBody3D).collision_layer, 2, "%s on pick layer 2" % n.get_meta("entity_id"))
	for c in n.get_children():
		_bodies(c, out)
	return out


func test_pick_bodies_cover_the_chamber_entities() -> void:
	var ids := _bodies(_root, {})
	var expected: Array[StringName] = [&"origin_chamber", &"origin_core", &"fragment_field", &"verification_array"]
	for i in OriginChamberScript.LAYER_COUNT:
		expected.append(OriginChamberScript.layer_entity(i))
	for id in expected:
		assert_true(ids.has(id), "pick body for %s" % id)
		assert_false(EntityCatalog.info(id).is_empty(), "%s is a catalog id" % id)


func test_camera_director_group_and_current_camera() -> void:
	var director := get_tree().get_first_node_in_group(&"camera_director")
	assert_not_null(director)
	assert_true(director.has_method("snap_to_mode_shot"))
	assert_true((director as CameraDirector).camera.current)
	Simulation.seek(37.0)
	director.snap_to_mode_shot()
	var rig := (director as CameraDirector).rig()
	var goal := CameraShots.Shot.new()
	CameraShots.desired(Session.mode, Session.cinematic, Simulation.world, Simulation.time, goal)
	assert_true(rig.approx_equals(goal), "snap lands on the goal of the state")
	assert_gt((director as CameraDirector).camera.global_position.y, CameraShots.FLOOR_Y)


func test_structure_follows_seek() -> void:
	var fs: FragmentStructure = _nodes["fragment_structure"]
	var layer0 := fs.get_node("Layer0") as MultiMeshInstance3D
	var ribs := fs.get_node("Ribs") as MultiMeshInstance3D
	await wait_process_frames(2)
	assert_false(layer0.visible, "no fragments before emission")
	Simulation.seek(8.5)
	await wait_process_frames(2)
	assert_true(layer0.visible, "fragments emitted")
	assert_false(ribs.visible)
	Simulation.seek(49.0)
	await wait_process_frames(2)
	assert_true(ribs.visible, "ribs in the final form")
	for i in OriginChamberScript.FRAGMENT_COUNT:
		assert_almost_eq(fs.segment_state(i).r, 1.0, 1e-4, "segment %d assembled" % i)
	# Seek back: the same instant always gives the same state (no residual state).
	Simulation.seek(19.5)
	await wait_process_frames(1)
	var a := fs.segment_state(40)
	assert_between(a.r, 0.0, 1.0)
	Simulation.seek(49.0)
	await wait_process_frames(1)
	Simulation.seek(19.5)
	await wait_process_frames(1)
	assert_eq(fs.segment_state(40), a)


func test_light_rig_drives_environment() -> void:
	var rig: LightRig = _nodes["light_rig"]
	await wait_process_frames(1)
	assert_false(rig.core.visible, "no core light while dormant")
	assert_almost_eq(_env.ambient_light_energy, float(EnvironmentProfile.LIGHT["dormant"]["ambient"]), 1e-4)
	for l in [rig.key, rig.fill, rig.rim]:
		assert_true(l.light_volumetric_fog_energy <= 0.1, "directional lights barely enter the fog")
	Simulation.seek(49.0)
	await wait_process_frames(1)
	assert_true(rig.core.visible)
	assert_almost_eq(rig.key.light_energy, float(EnvironmentProfile.LIGHT["final"]["key"]), 1e-3)
	assert_almost_eq(_env.tonemap_exposure, float(EnvironmentProfile.LIGHT["final"]["exposure"]), 1e-3)


func test_verification_feeds_structure_material() -> void:
	Simulation.seek(37.0)
	await wait_process_frames(1)
	var m := MaterialLibrary.structure()
	assert_almost_eq(float(m.get_shader_parameter("scan_y")), Choreography.scan_y(Simulation.world, 37.0), 1e-4)
	assert_gt(float(m.get_shader_parameter("scan_strength")), 0.9)
	Simulation.seek(49.0)
	await wait_process_frames(1)
	assert_almost_eq(float(m.get_shader_parameter("scan_strength")), 0.0, 1e-4)


func test_selection_highlights_layer_instances() -> void:
	var fs: FragmentStructure = _nodes["fragment_structure"]
	Simulation.seek(30.0)
	Session.select(&"layer_2")
	await wait_process_frames(40)
	var first2 := fs.blueprint.layer_first_segment(2)
	var first1 := fs.blueprint.layer_first_segment(1)
	assert_gt(fs.segment_state(first2).b, 0.5, "selected layer highlighted (BONE)")
	assert_almost_eq(fs.segment_state(first1).b, 0.0, 1e-4, "others untouched")


func test_camera_input_orbits_zooms_and_resets() -> void:
	var d: CameraDirector = _nodes["camera_director"]
	d.snap_to_mode_shot()
	var yaw0 := d.rig().yaw
	var dist0 := d.rig().distance
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	d._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(60.0, 0.0)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	d._unhandled_input(drag)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	d._unhandled_input(wheel)
	await wait_process_frames(3)
	assert_ne(d.rig().yaw, yaw0, "drag orbits")
	assert_gt(d.rig().distance, dist0, "wheel zooms out")
	assert_lte(d.rig().distance, CameraShots.DISTANCE_LIMITS[SessionState.Mode.FORGE].y)
	d.reset_to_mode_shot()
	await wait_seconds(Palette.T_CINEMATIC + 0.3)
	var goal := CameraShots.Shot.new()
	CameraShots.desired(Session.mode, Session.cinematic, Simulation.world, Simulation.time, goal)
	assert_true(d.rig().approx_equals(goal), "camera_reset tweens back to the shot of the state")


func test_segment_state_is_defined_before_emission() -> void:
	var fs: FragmentStructure = _nodes["fragment_structure"]
	Simulation.seek(30.0)
	Session.select(&"layer_1")
	await wait_process_frames(2)
	assert_gt(fs.segment_state(fs.blueprint.layer_first_segment(1)).r, 0.5, "seated at t=30")
	# Back to before FRAGMENTS_EMITTED: the state is the one of that instant, not the last written.
	Session.select(&"")
	Simulation.seek(5.0)
	await wait_process_frames(2)
	for i in OriginChamberScript.FRAGMENT_COUNT:
		assert_eq(fs.segment_state(i), Color(0, 0, 0, 0), "segment %d hidden and neutral before emission" % i)


func test_light_rig_scales_exposure_per_mode_and_caches_writes() -> void:
	var rig: LightRig = _nodes["light_rig"]
	Simulation.seek(49.0)
	await wait_process_frames(1)
	var base := float(EnvironmentProfile.LIGHT["final"]["exposure"])
	assert_almost_eq(_env.tonemap_exposure, base * LightRig.exposure_scale_for(SessionState.Mode.FORGE), 1e-3)
	Session.set_mode(SessionState.Mode.UNIVERSE)
	await wait_process_frames(1)
	var scale := LightRig.exposure_scale_for(SessionState.Mode.UNIVERSE)
	assert_eq(scale, float(EnvironmentProfile.mode_fog(SessionState.Mode.UNIVERSE)["exposure_scale"]))
	assert_almost_eq(_env.tonemap_exposure, base * scale, 1e-3, "UNIVERSE exposure scaled")
	# Steady state: the Environment is not written again (an outside value survives a frame).
	_env.tonemap_exposure = 0.123
	await wait_process_frames(2)
	assert_almost_eq(_env.tonemap_exposure, 0.123, 1e-6, "no write while the levels are steady")
	assert_almost_eq(rig.environment_written().y, base * scale, 1e-3)


func test_light_rig_core_and_shadow_settings() -> void:
	var rig: LightRig = _nodes["light_rig"]
	assert_almost_eq(rig.core.omni_range, LightRig.CORE_RANGE, 1e-5)
	assert_almost_eq(rig.core.omni_attenuation, LightRig.CORE_ATTENUATION, 1e-5)
	assert_almost_eq(rig.core.light_specular, LightRig.CORE_SPECULAR, 1e-5)
	assert_almost_eq(rig.key.shadow_normal_bias, LightRig.KEY_SHADOW_NORMAL_BIAS, 1e-5)
	assert_almost_eq(rig.key.shadow_blur, LightRig.KEY_SHADOW_BLUR, 1e-5)
	assert_eq(LightRig.shadow_mode_for(2), DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_eq(LightRig.shadow_mode_for(4), DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_eq(LightRig.shadow_mode_for(1), DirectionalLight3D.SHADOW_ORTHOGONAL)
	for level in QualityProfiles.LEVEL_NAMES.size():
		var profile := QualityProfiles.get_profile(level)
		rig._on_quality(profile)
		assert_eq(rig.key.directional_shadow_mode, LightRig.shadow_mode_for(int(profile["shadow_splits"])),
			"key splits follow %s" % QualityProfiles.LEVEL_NAMES[level])
	rig._on_quality(Quality.profile)


func test_camera_drag_uses_the_shared_threshold() -> void:
	var d: CameraDirector = _nodes["camera_director"]
	d.snap_to_mode_shot()
	var yaw0 := d.rig().yaw
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	d._unhandled_input(press)
	# Below the threshold (accumulated): a click, the camera does not move.
	var small := InputEventMouseMotion.new()
	small.relative = Vector2(InputTuning.DRAG_THRESHOLD_PX * 0.3, 0.0)
	small.button_mask = MOUSE_BUTTON_MASK_LEFT
	d._unhandled_input(small)
	small.relative = -small.relative
	d._unhandled_input(small)
	assert_false(InputTuning.is_drag(d.press_travel()))
	assert_almost_eq(d.rig().yaw, yaw0, 1e-6, "sub-threshold travel does not orbit")
	# The travel accumulates (back and forth counts): crossing the threshold starts the orbit.
	small.relative = Vector2(InputTuning.DRAG_THRESHOLD_PX * 0.5, 0.0)
	d._unhandled_input(small)
	assert_true(InputTuning.is_drag(d.press_travel()), "accumulated %.1f px is a drag" % d.press_travel())
	assert_ne(d.rig().yaw, yaw0, "orbit once the press is a drag")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	d._unhandled_input(release)
	assert_eq(d.press_travel(), -1.0)


func test_floor_is_not_pickable_but_the_chamber_is() -> void:
	await wait_physics_frames(3)
	var space := _root.get_world_3d().direct_space_state
	# Straight down onto open floor (between the structure and the pillars): nothing.
	var down := PhysicsRayQueryParameters3D.create(Vector3(12.0, 20.0, 5.0), Vector3(12.0, -20.0, 5.0), 2)
	assert_true(space.intersect_ray(down).is_empty(), "the floor is empty space for the picker")
	# Towards a pillar: the chamber.
	var pillar := ChamberArchitecture.pillar_transform(0).origin
	var at := PhysicsRayQueryParameters3D.create(pillar * Vector3(2.0, 1.0, 2.0), pillar, 2)
	var hit := space.intersect_ray(at)
	assert_false(hit.is_empty(), "pillar is pickable")
	assert_eq(Picker.entity_id_of_hit(hit), ChamberArchitecture.ENTITY_ID)


func _focus_ids() -> Array[StringName]:
	var ids: Array[StringName] = [&"origin_chamber", &"origin_core", &"fragment_field", &"verification_array"]
	for i in OriginChamberScript.LAYER_COUNT:
		ids.append(OriginChamberScript.layer_entity(i))
	return ids


func test_every_entity_joins_its_focus_group() -> void:
	for id in _focus_ids():
		var nodes := get_tree().get_nodes_in_group(SessionState.entity_group(id))
		assert_eq(nodes.size(), 1, "one focus root for %s" % id)
		if nodes.is_empty():
			continue
		var b := CameraDirector.node_bounds(nodes[0] as Node3D)
		assert_gt(maxf(b.size.x, b.size.z), 0.5, "%s has real bounds" % id)
	var fs: FragmentStructure = _nodes["fragment_structure"]
	for l in OriginChamberScript.LAYER_COUNT:
		var node := get_tree().get_first_node_in_group(SessionState.entity_group(OriginChamberScript.layer_entity(l))) as Node3D
		var b := CameraDirector.node_bounds(node)
		assert_almost_eq(b.get_center().y, float(fs.blueprint.layers[l]["y"]), 1e-4, "layer %d bounds on its ring" % l)
		assert_almost_eq(b.size.x * 0.5, float(fs.blueprint.segment_mesh_params(l)["r_out"]), 1e-4)
	# Descendant fallback (no meta): the merged AABB of the visuals.
	var bare := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.0, 2.0)
	mi.mesh = box
	bare.add_child(mi)
	_root.add_child(bare)
	bare.position = Vector3(1.0, 2.0, 3.0)
	var bb := CameraDirector.node_bounds(bare)
	assert_true(bb.get_center().is_equal_approx(Vector3(1.0, 2.0, 3.0)), "fallback centre %s" % bb.get_center())
	assert_true(bb.size.is_equal_approx(Vector3(2.0, 1.0, 2.0)), "fallback size %s" % bb.size)


func test_focus_frames_the_layer_and_suspends_cues() -> void:
	var d: CameraDirector = _nodes["camera_director"]
	Session.set_cinematic(true)
	Simulation.seek(30.5)
	d.snap_to_mode_shot()
	Session.focus(&"layer_2")
	assert_eq(d.focused(), &"layer_2")
	await wait_seconds(Palette.T_CINEMATIC + 0.4)
	assert_true(d.rig().approx_equals(d.focus_goal()), "the framing settled on the focus goal")
	var fs: FragmentStructure = _nodes["fragment_structure"]
	assert_almost_eq(d.rig().target.y, float(fs.blueprint.layers[2]["y"]), 1e-3, "aimed at ring 2")
	assert_gte(d.rig().pitch, CameraShots.FOCUS_MIN_PITCH - 1e-4)
	# The cue did not take the camera back (a focus counts as user input).
	var cue := CameraShots.Shot.new()
	CameraShots.desired(Session.mode, true, Simulation.world, Simulation.time, cue)
	assert_false(d.rig().approx_equals(cue), "cue suspended while focused")
	# A repeated request re-frames (Session.focus always emits).
	Session.focus(&"layer_2")
	assert_eq(d.focused(), &"layer_2")
	# camera_reset: back to the shot of the state.
	d.reset_to_mode_shot()
	assert_eq(d.focused(), &"", "reset ends the focus")
	await wait_seconds(Palette.T_CINEMATIC + 0.3)
	var goal := CameraShots.Shot.new()
	CameraShots.desired(Session.mode, Session.cinematic, Simulation.world, Simulation.time, goal)
	assert_true(d.rig().approx_equals(goal), "back on the cue")


func test_focus_ignores_unknown_and_out_of_reach_targets() -> void:
	var d: CameraDirector = _nodes["camera_director"]
	d.snap_to_mode_shot()
	assert_false(d.focus_on(&"no_such_entity"))
	var far := Node3D.new()
	far.add_to_group(SessionState.entity_group(&"seed_test"))
	_root.add_child(far)
	far.position = Vector3(0.0, 8.0, -62.0)
	var before := CameraShots.Shot.new().copy_from(d.rig())
	assert_false(d.focus_on(&"seed_test"), "a seed is out of reach from FORGE")
	assert_true(d.rig().approx_equals(before), "camera untouched")
	Session.set_mode(SessionState.Mode.UNIVERSE)
	d.snap_to_mode_shot()
	assert_true(d.focus_on(&"seed_test"), "reachable in UNIVERSE")
	assert_true(d.focus_goal().target.is_equal_approx(far.position))


func test_input_during_focus_hands_control_to_the_user() -> void:
	var d: CameraDirector = _nodes["camera_director"]
	d.snap_to_mode_shot()
	Session.focus(&"origin_core")
	assert_eq(d.focused(), &"origin_core")
	await wait_process_frames(2)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	d._unhandled_input(wheel)
	assert_eq(d.focused(), &"", "input ends the focus tween")
	var held := CameraShots.Shot.new().copy_from(d.rig())
	await wait_process_frames(3)
	assert_true(d.rig().approx_equals(held), "the camera stays where the user left it")


func test_universe_focus_survives_seek() -> void:
	var d: CameraDirector = _nodes["camera_director"]
	Session.set_mode(SessionState.Mode.UNIVERSE)
	d.snap_to_mode_shot()
	Session.focus(&"origin_core")
	await wait_seconds(Palette.T_CINEMATIC + 0.3)
	Simulation.seek(20.0)
	await wait_process_frames(2)
	assert_true(d.rig().approx_equals(d.focus_goal()), "a scrub keeps the focus outside a cue")


func test_oculus_hidden_only_in_universe() -> void:
	var arch: ChamberArchitecture = _nodes["chamber_architecture"]
	assert_true(arch.oculus.visible)
	Session.set_mode(SessionState.Mode.UNIVERSE)
	assert_false(arch.oculus.visible, "no loose ring above the chamber in UNIVERSE")
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	assert_true(arch.oculus.visible)


func test_scan_band_rides_on_top_of_the_ring() -> void:
	var va: VerificationArray = _nodes["verification_array"]
	Simulation.seek(37.0)
	await wait_process_frames(1)
	var y := Choreography.scan_y(Simulation.world, Simulation.time)
	assert_almost_eq(va.band.global_position.y, y, 1e-4, "band centre = scan height")
	var ring_top := va.ring.global_position.y + VerificationArray.RING_HEIGHT * 0.5
	var band_bottom := va.band.global_position.y - VerificationArray.BAND_WIDTH * 0.5
	assert_gte(band_bottom, ring_top - 1e-4, "the opaque ring never covers the band")


func test_light_rig_rewrites_environment_after_rebuild() -> void:
	Simulation.seek(49.0)
	await wait_process_frames(1)
	var expected := _env.tonemap_exposure
	_env.tonemap_exposure = 0.123
	Simulation.seek(49.0)
	await wait_process_frames(1)
	assert_almost_eq(_env.tonemap_exposure, expected, 1e-4, "world_rebuilt clears the write cache")
