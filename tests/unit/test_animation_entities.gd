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
