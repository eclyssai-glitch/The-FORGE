extends GutTest
## World composition per scenario (Loop 4, phase B): modules of the active scenario, recomposition
## on Simulation.scenario_changed, GENESIS environment (nebula sky, AgX, glow, fog, quality/mode,
## sky motion throttle), AudioDirector in both scenarios and audio anchors by meta, picking of
## GENESIS entities, style frame poses and the GENESIS capture list. Composition checks work
## whether or not a module script exists; the smoke audio report expects the animator's real
## GENESIS modules (integrated in Loop 4) to register the anchors.

const WorldScene := preload("res://scenes/world.tscn")
const WorldScript := preload("res://src/world/world.gd")
const AutomationScript := preload("res://src/core/automation.gd")

var world: WorldScript
var _prev_level: QualityProfiles.Level
var _prev_auto: bool
var _prev_mode: SessionState.Mode


func before_each() -> void:
	_prev_level = Quality.level
	_prev_auto = Quality.auto
	_prev_mode = Session.mode
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	world = WorldScene.instantiate()
	add_child_autofree(world)


func after_each() -> void:
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	Simulation.reset()
	Quality.override_for_session(_prev_level)
	Quality.auto = _prev_auto
	Session.set_mode(_prev_mode)
	Session.select(&"")
	Session.hover(&"")
	# Modules of a recomposed scenario are queue_free()d: let them go before the orphan count.
	await wait_process_frames(2)


func _names(list: Array) -> Array[String]:
	var out: Array[String] = []
	for m in list:
		out.append(String(m[0]))
	return out


func _assert_scenario_modules(id: StringName) -> void:
	var last := world.world_environment.get_index()
	for m in WorldScript.modules_for(id):
		var node := world.get_node_or_null(NodePath(m[0]))
		assert_eq(node != null, ResourceLoader.exists(m[1]), "%s present iff its script exists" % m[0])
		assert_eq(world.missing_modules().has(String(m[0])), not ResourceLoader.exists(m[1]),
			"%s reported missing iff its script is absent" % m[0])
		if node:
			assert_gt(node.get_index(), last, "%s after the previous module" % m[0])
			last = node.get_index()
	var audio := world.get_node_or_null(^"AudioDirector")
	assert_not_null(audio, "AudioDirector composed")
	if audio:
		assert_gt(audio.get_index(), last, "AudioDirector after the scenario modules")
	assert_eq(world.picker.get_index(), world.get_child_count() - 1, "picker is last")


func test_expected_modules_per_scenario() -> void:
	var origin := WorldScript.expected_module_names(Scenario.ORIGIN_CHAMBER)
	var genesis := WorldScript.expected_module_names(Scenario.GENESIS)
	assert_eq(origin, _names(WorldScript.ORIGIN_MODULES) + ["AudioDirector", "CameraDirector"])
	assert_eq(genesis, _names(WorldScript.GENESIS_MODULES) + ["AudioDirector", "CameraDirector"])
	assert_eq(_names(WorldScript.GENESIS_MODULES), ["GenesisLightRig", "Miku", "AuxiliaryHands",
		"FormingPlanet", "OrbitalSystem", "RelationThreads", "Stardust", "FormationGlow"] as Array[String])
	for m in WorldScript.GENESIS_MODULES:
		var path := String(m[1])
		assert_true(path.begins_with("res://src/entities/genesis/") or path.begins_with("res://src/fx/genesis/"),
			"%s lives in the animator's genesis folders" % path)
	assert_eq(WorldScript.MODULES, WorldScript.ORIGIN_MODULES, "legacy MODULES = ORIGIN")
	assert_eq(WorldScript.modules_for(&"nope"), WorldScript.ORIGIN_MODULES, "unknown id -> ORIGIN")
	assert_eq(WorldScript.expected_module_names(), origin, "default: the active scenario (ORIGIN)")


func test_origin_is_composed_by_default() -> void:
	assert_eq(world.scenario, Scenario.ORIGIN_CHAMBER)
	_assert_scenario_modules(Scenario.ORIGIN_CHAMBER)
	assert_not_null(world.universe, "ORIGIN has its universe")
	assert_eq(world.environment.sky.sky_material, world.universe.sky_material)
	assert_eq(get_tree().get_nodes_in_group(&"entity_seed_aurel").size(), 1)


func test_audio_director_is_composed_in_its_group() -> void:
	var audio := world.audio_director
	assert_not_null(audio)
	assert_true(audio is AudioDirector)
	assert_eq(audio.name, "AudioDirector")
	assert_true(audio.is_in_group(WorldScript.AUDIO_GROUP))
	assert_eq(get_tree().get_nodes_in_group(&"audio_director"), [audio] as Array[Node])
	assert_eq(world.modules["AudioDirector"], audio)


func test_recomposition_to_genesis_and_back() -> void:
	var audio := world.audio_director
	var picker := world.picker
	var origin_env := world.environment
	Session.select(&"seed_aurel")
	Simulation.set_scenario(Scenario.GENESIS)
	assert_eq(world.scenario, Scenario.GENESIS)
	assert_null(world.universe, "ORIGIN universe off in GENESIS")
	for m in WorldScript.ORIGIN_MODULES:
		assert_null(world.get_node_or_null(NodePath(m[0])), "%s left the tree" % m[0])
		assert_false(world.modules.has(String(m[0])))
	for id in [&"seed_aurel", &"seed_vesper", &"seed_lattice"]:
		assert_eq(get_tree().get_nodes_in_group(SessionState.entity_group(id)).size(), 0, "%s gone" % id)
	assert_eq(Session.selected, &"", "selection of the previous scenario cleared")
	_assert_scenario_modules(Scenario.GENESIS)
	assert_eq(world.audio_director, audio, "AudioDirector persists")
	assert_eq(world.picker, picker, "Picker persists")
	assert_ne(world.environment, origin_env, "environment rebuilt")
	assert_eq(world.world_environment.environment, world.environment)
	assert_not_null(world.get_viewport().get_camera_3d(), "a camera stays current")

	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	assert_eq(world.scenario, Scenario.ORIGIN_CHAMBER)
	_assert_scenario_modules(Scenario.ORIGIN_CHAMBER)
	assert_not_null(world.universe, "universe back")
	assert_eq(world.environment.sky.sky_material, world.universe.sky_material)
	assert_eq(world.environment.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_eq(get_tree().get_nodes_in_group(&"entity_seed_aurel").size(), 1)
	await wait_process_frames(2)
	assert_eq(get_tree().get_nodes_in_group(&"entity_seed_aurel").size(), 1, "old nodes really freed")


func test_genesis_environment() -> void:
	Simulation.set_scenario(Scenario.GENESIS)
	var env: Environment = world.environment
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_not_null(env.sky)
	var sky := env.sky.sky_material as ShaderMaterial
	assert_eq(sky, world.genesis_sky)
	assert_eq(sky.shader, MaterialLibrary.nebula_sky().shader, "nebula sky shader")
	assert_ne(sky, MaterialLibrary.nebula_sky(), "the world owns a duplicate (its own motion_time rate)")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_true(env.glow_enabled)
	assert_gte(env.glow_hdr_threshold, 1.0, "only HDR emission blooms")
	assert_eq(env.glow_bloom, 0.0, "no bloom over everything")
	assert_true(env.fog_enabled)
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_eq(env.fog_light_color, Palette.SPACE_DEEP)
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_lte(env.ambient_light_energy, 0.4, "minimal ambient: the light comes from the rig")
	assert_eq(env.reflected_light_source, Environment.REFLECTION_SOURCE_SKY)


func test_genesis_quality_and_mode() -> void:
	Simulation.set_scenario(Scenario.GENESIS)
	var env: Environment = world.environment
	var sky := world.genesis_sky
	Quality.override_for_session(QualityProfiles.Level.LOW)
	assert_false(env.volumetric_fog_enabled, "LOW: no volumetric")
	assert_false(env.ssao_enabled)
	assert_true(env.glow_enabled, "LOW keeps the contained glow")
	assert_eq(int(sky.get_shader_parameter("detail")), MaterialLibrary.SKY_DETAIL[0])
	assert_eq(int(MaterialLibrary.planet_forming().get_shader_parameter("detail")), MaterialLibrary.PLANET_DETAIL[0],
		"MaterialLibrary.apply_quality on profile change")
	assert_eq(env.sky.radiance_size, GenesisEnvironment.RADIANCE_SIZE[0])
	var low_begin := env.fog_depth_begin
	Quality.override_for_session(QualityProfiles.Level.ULTRA)
	assert_true(env.volumetric_fog_enabled)
	assert_true(env.ssil_enabled)
	assert_eq(int(sky.get_shader_parameter("detail")), MaterialLibrary.SKY_DETAIL[3])
	assert_gt(env.fog_depth_begin, low_begin, "without volumetric the depth fog starts closer")
	Session.set_mode(SessionState.Mode.FORGE)
	var forge_energy := float(sky.get_shader_parameter("sky_energy"))
	Session.set_mode(SessionState.Mode.OBSERVATORY)
	assert_lt(float(sky.get_shader_parameter("sky_energy")), forge_energy, "OBSERVATORY: the nebula recedes")
	Session.set_mode(SessionState.Mode.UNIVERSE)
	assert_eq(env.fog_depth_end, float(GenesisEnvironment.mode_settings(SessionState.Mode.UNIVERSE)["fog_depth_end"]))
	assert_gt(env.fog_depth_end, float(GenesisEnvironment.mode_settings(SessionState.Mode.FORGE)["fog_depth_end"]),
		"UNIVERSE sees the whole system")


func test_sky_motion_is_throttled() -> void:
	assert_lte(GenesisEnvironment.SKY_MOTION_HZ, 5.0)
	var values := {}
	var t := 100.0
	while t < 101.0:
		values[GenesisEnvironment.sky_motion_step(t)] = true
		t += 1.0 / 144.0
	assert_lte(values.size(), int(GenesisEnvironment.SKY_MOTION_HZ) + 1, "≤ SKY_MOTION_HZ changes per second")
	assert_false(GenesisEnvironment.sky_motion_enabled(QualityProfiles.get_profile(QualityProfiles.Level.LOW)))
	assert_true(GenesisEnvironment.sky_motion_enabled(QualityProfiles.get_profile(QualityProfiles.Level.HIGH)))


func test_genesis_frame_updates_motion_time() -> void:
	Quality.override_for_session(QualityProfiles.Level.HIGH)
	Simulation.set_scenario(Scenario.GENESIS)
	await wait_process_frames(3)
	var now := MotionClock.now()
	assert_almost_eq(float(MaterialLibrary.hand_stone().get_shader_parameter("motion_time")), now, 0.5,
		"MaterialLibrary.set_motion_time(MotionClock.now()) each frame")
	var sky_t := float(world.genesis_sky.get_shader_parameter("motion_time"))
	assert_almost_eq(sky_t, GenesisEnvironment.sky_motion_step(now), 1.0 / GenesisEnvironment.SKY_MOTION_HZ + 0.1)


func test_audio_anchor_registered_by_meta() -> void:
	var audio := world.audio_director as AudioDirector
	# Meta set before entering the tree: picked by node_added.
	var planet := Node3D.new()
	planet.set_meta(WorldScript.AUDIO_ANCHOR_META, &"planet")
	world.add_child(planet)
	# Meta set after add_child (as a module would in _ready): picked at the end of the frame.
	var holder := Node3D.new()
	world.add_child(holder)
	var hands := Node3D.new()
	holder.add_child(hands)
	hands.set_meta(WorldScript.AUDIO_ANCHOR_META, &"hands")
	# Outside the world: ignored.
	var stray := Node3D.new()
	stray.set_meta(WorldScript.AUDIO_ANCHOR_META, &"miku")
	add_child_autofree(stray)
	await wait_process_frames(2)
	assert_eq(audio.get_anchor(&"planet"), planet)
	assert_eq(audio.get_anchor(&"hands"), hands)
	assert_null(audio.get_anchor(&"miku"), "nodes outside the world are not anchors")
	assert_eq(world.audio_anchor_kinds(), [&"hands", &"planet"] as Array[StringName])
	# Explicit scan.
	var miku := Node3D.new()
	world.add_child(miku)
	miku.set_meta(WorldScript.AUDIO_ANCHOR_META, &"miku")
	assert_eq(world.register_audio_anchors(), 3)
	assert_eq(audio.get_anchor(&"miku"), miku)
	var loose := Node3D.new()
	assert_false(world.register_audio_anchor(loose), "no meta, not in the world")
	loose.free()
	planet.queue_free()
	await wait_process_frames(1)
	assert_false(world.audio_anchor_kinds().has(&"planet"), "freed anchors drop out")
	assert_null(audio.get_anchor(&"planet"))


func test_audio_anchors_rescanned_after_recomposition() -> void:
	Simulation.set_scenario(Scenario.GENESIS)
	var audio := world.audio_director as AudioDirector
	var planet := Node3D.new()
	planet.set_meta(WorldScript.AUDIO_ANCHOR_META, &"planet")
	world.add_child(planet)
	await wait_process_frames(1)
	assert_eq(audio.get_anchor(&"planet"), planet)
	# A scene module with the meta (fake; the real ones come from the animator) is scanned on
	# composition — every scenario node with the meta becomes an anchor.
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	Simulation.set_scenario(Scenario.GENESIS)
	assert_eq(world.scenario, Scenario.GENESIS)
	assert_eq(audio.get_anchor(&"planet"), planet, "anchors outside the scenario modules survive")


func test_smoke_audio_report() -> void:
	var lines: PackedStringArray = []
	assert_true(AutomationScript._smoke_audio(world, lines), "ORIGIN needs no anchors")
	assert_eq(lines[0], "audio=present anchors=")
	# (a) GENESIS with the real animator modules: they register the three anchors themselves.
	Simulation.set_scenario(Scenario.GENESIS)
	await wait_process_frames(1)
	assert_eq(world.missing_modules(), [] as Array[String], "GENESIS modules integrated")
	lines = []
	assert_true(AutomationScript._smoke_audio(world, lines), "\n".join(lines))
	assert_eq(lines[0], "audio=present anchors=hands,miku,planet")
	var modules := world.scenario_nodes()
	for kind: StringName in WorldScript.GENESIS_AUDIO_ANCHORS:
		var anchor := world.audio_director.get_anchor(kind) as Node
		assert_true(modules.any(func(m: Node) -> bool: return m.is_ancestor_of(anchor)),
			"anchor %s comes from a scenario module" % kind)
	# (b) GENESIS without the modules: detach them from the world (kept alive and restored
	# below, so the recomposition in after_each frees them normally) — no anchors, smoke fails.
	var slots: Array[int] = []
	for m in modules:
		slots.append(m.get_index())
	for m in modules:
		world.remove_child(m)
	assert_eq(world.audio_anchor_kinds(), [] as Array[StringName])
	lines = []
	assert_false(AutomationScript._smoke_audio(world, lines), "GENESIS without anchors fails")
	assert_eq(lines[0], "audio=present anchors=")
	assert_eq(lines[-1], "FAIL audio anchors missing: planet, miku, hands")
	for i in modules.size():
		world.add_child(modules[i])
		world.move_child(modules[i], slots[i])
	await wait_process_frames(1)
	lines = []
	assert_true(AutomationScript._smoke_audio(world, lines), "anchors back with the modules")
	assert_eq(lines[0], "audio=present anchors=hands,miku,planet")


func test_silence_audio_stops_every_player() -> void:
	var audio := world.audio_director as AudioDirector
	await wait_process_frames(1)
	assert_true(audio.ambience_player.playing, "ambience plays in every scenario")
	audio.play_sound(&"sfx_planet_seed")
	assert_gte(world.silence_audio(), 1)
	assert_false(audio.ambience_player.playing)
	assert_eq(audio.active_voices(), 0)


func test_picker_selects_genesis_entities() -> void:
	Simulation.set_scenario(Scenario.GENESIS)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta(&"entity_id", &"miku")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	shape.shape = sphere
	body.add_child(shape)
	body.position = Vector3(0.0, 4.0, 0.0)
	world.add_child(body)
	await wait_physics_frames(2)
	assert_true(GenesisCatalog.all_ids().has(&"miku"))
	assert_eq(world.picker.pick_ray(Vector3(0.0, 4.0, 20.0), Vector3(0.0, 4.0, -20.0)), &"miku")
	assert_eq(world.picker.pick_ray(Vector3(0.0, 40.0, 20.0), Vector3(0.0, 40.0, -20.0)), &"", "empty space")
	# No ORIGIN seed is pickable in GENESIS (the universe is gone), even in UNIVERSE mode.
	Session.set_mode(SessionState.Mode.UNIVERSE)
	await wait_physics_frames(2)
	var seed := Universe.seed_base_position(Universe.SEEDS[0])
	assert_eq(world.picker.pick_ray(seed + Vector3(0.0, 0.0, 12.0), seed), &"")


func test_fallback_shots_cover_every_mode() -> void:
	for shots: Dictionary in [WorldScript.FALLBACK_SHOTS, WorldScript.FALLBACK_SHOTS_GENESIS]:
		for mode: SessionState.Mode in [SessionState.Mode.UNIVERSE, SessionState.Mode.FORGE, SessionState.Mode.OBSERVATORY]:
			assert_true(shots.has(mode))
	var forge: Array = WorldScript.FALLBACK_SHOTS_GENESIS[SessionState.Mode.FORGE]
	assert_lt((forge[0] as Vector3).y, (forge[1] as Vector3).y, "GENESIS FORGE: slight low angle")


func test_scenario_from_args() -> void:
	var sim: Script = Simulation.get_script()
	assert_eq(sim.call(&"scenario_from_args", PackedStringArray(["--scenario=GENESIS"])), &"genesis")
	assert_eq(sim.call(&"scenario_from_args", PackedStringArray(["--smoke-test", "--scenario=origin_chamber"])), &"origin_chamber")
	assert_eq(sim.call(&"scenario_from_args", PackedStringArray(["--smoke-test"])), &"")


func test_style_frame_poses() -> void:
	var poses := StyleFrames.DEFAULT_POSES
	assert_gte(poses.size(), StyleFrames.MIN_FRAMES)
	assert_eq(StyleFrames.valid_poses(poses).size(), poses.size(), "every default pose is valid")
	assert_eq(StyleFrames.SIZE, Vector2i(1920, 1080))
	var modes := {}
	for p in poses:
		modes[int(p["mode"])] = true
	assert_eq(modes.size(), 3, "style frames cover the three modes")
	assert_eq(StyleFrames.poses_from(null), poses)
	assert_false(StyleFrames.is_valid_pose({"name": "x"}))
	assert_false(StyleFrames.is_valid_pose({"name": "bad name", "time": 1.0, "mode": 1,
		"position": Vector3.ZERO, "target": Vector3.ONE, "fov": 40.0}))
	assert_false(StyleFrames.is_valid_pose({"name": "late", "time": 99.0, "mode": 1,
		"position": Vector3.ZERO, "target": Vector3.ONE, "fov": 40.0}))
	assert_false(StyleFrames.is_valid_pose({"name": "degenerate", "time": 1.0, "mode": 1,
		"position": Vector3.ONE, "target": Vector3.ONE, "fov": 40.0}))


func test_style_frame_poses_from_director() -> void:
	var director := FakeDirector.new()
	for i in 6:
		director.poses.append({"name": "d%d" % i, "time": 10.0 + i, "mode": SessionState.Mode.FORGE,
			"position": Vector3(0, 1, 10 + i), "target": Vector3(0, 4, 0), "fov": 40.0})
	assert_eq(StyleFrames.poses_from(director).size(), 6, "director poses used")
	assert_eq(str(StyleFrames.poses_from(director)[0]["name"]), "d0")
	director.poses.pop_back()
	assert_eq(StyleFrames.poses_from(director), StyleFrames.DEFAULT_POSES, "< 6 valid -> defaults")
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var pose: Dictionary = StyleFrames.DEFAULT_POSES[0]
	StyleFrames.apply_pose(cam, pose)
	assert_almost_eq(cam.global_position, pose["position"] as Vector3, Vector3.ONE * 1e-4)
	var forward := -cam.global_transform.basis.z
	assert_almost_eq(forward.dot(((pose["target"] as Vector3) - (pose["position"] as Vector3)).normalized()), 1.0, 1e-4)
	assert_almost_eq(cam.fov, float(pose["fov"]), 1e-4)


func test_genesis_capture_list() -> void:
	assert_eq(AutomationScript.captures_for(Scenario.ORIGIN_CHAMBER), AutomationScript.CAPTURES)
	var list: Array = AutomationScript.captures_for(Scenario.GENESIS)
	assert_eq(list, AutomationScript.CAPTURES_GENESIS)
	var names := {}
	var modes := {}
	for c: Array in list:
		assert_false(names.has(c[0]), "unique name %s" % c[0])
		names[c[0]] = true
		modes[int(c[2])] = true
		assert_between(float(c[1]), 0.0, GenesisScript.DURATION, "%s inside the timeline" % c[0])
		var sel := AutomationScript.capture_selected(c)
		if sel != &"":
			assert_true(GenesisCatalog.all_ids().has(sel), "%s selects a GENESIS entity" % c[0])
	assert_eq(modes.size(), 3, "GENESIS captures cover the three modes")
	var last: Array = list.back()
	assert_false(bool(AutomationScript.capture_options(last).get("hud", true)), "last capture hides the HUD")


class FakeDirector:
	extends RefCounted
	var poses: Array = []

	func style_frame_poses() -> Array:
		return poses
