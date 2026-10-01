extends GutTest
## GENESIS modules compose headless exactly as world.gd composes them (load(path).new(), the
## environment before add_child), react to Simulation.genesis + Simulation.time, follow seek and
## reset exactly, expose one pickable body and one visual root per catalog entity, and carry the
## audio anchors. The CameraDirector frames GENESIS with GenesisShots.

const MODULES: Array = [
	["GenesisLightRig", "res://src/entities/genesis/genesis_light_rig.gd"],
	["Miku", "res://src/entities/genesis/miku.gd"],
	["AuxiliaryHands", "res://src/entities/genesis/auxiliary_hands.gd"],
	["FormingPlanet", "res://src/entities/genesis/forming_planet.gd"],
	["OrbitalSystem", "res://src/entities/genesis/orbital_system.gd"],
	["RelationThreads", "res://src/entities/genesis/relation_threads.gd"],
	["Stardust", "res://src/fx/genesis/stardust.gd"],
	["FormationGlow", "res://src/fx/genesis/formation_glow.gd"],
	["CameraDirector", "res://src/animation/camera_director.gd"],
]

var _root: Node3D
var _env: Environment
var _n: Dictionary = {}


func before_all() -> void:
	Simulation.set_scenario(Scenario.GENESIS)


func after_all() -> void:
	Simulation.set_scenario(Scenario.ORIGIN_CHAMBER)
	Session.set_mode(SessionState.Mode.FORGE)


func before_each() -> void:
	Simulation.set_scenario(Scenario.GENESIS)
	Simulation.reset()
	Session.set_mode(SessionState.Mode.FORGE)
	_root = Node3D.new()
	_env = GenesisEnvironment.make_environment(GenesisEnvironment.make_sky_material())
	for m in MODULES:
		var node: Node = load(m[1]).new()
		node.name = m[0]
		if &"environment" in node:
			node.set(&"environment", _env)
		_root.add_child(node)
		_n[m[0]] = node
	add_child_autofree(_root)


func after_each() -> void:
	Simulation.reset()
	Session.select(&"")
	Session.hover(&"")
	_n.clear()


func _seek(t: float) -> void:
	Simulation.seek(t)
	await wait_process_frames(2)


func _bodies(n: Node, out: Dictionary) -> Dictionary:
	if n is StaticBody3D and n.has_meta("entity_id"):
		out[n.get_meta("entity_id")] = n
		assert_true((n as StaticBody3D).collision_layer == 2 or (n as StaticBody3D).collision_layer == 0,
			"%s on pick layer 2 (or off while it does not exist)" % n.get_meta("entity_id"))
	for c in n.get_children():
		_bodies(c, out)
	return out


func _group_root(id: StringName) -> Node3D:
	for n in get_tree().get_nodes_in_group(SessionState.entity_group(id)):
		if _root.is_ancestor_of(n):
			return n as Node3D
	return null


func test_every_module_composes() -> void:
	for m in MODULES:
		assert_true(_n[m[0]] is Node3D, "%s is a Node3D" % m[0])
		assert_true((_n[m[0]] as Node).is_inside_tree())


func test_every_entity_has_a_root_and_a_pick_body() -> void:
	await _seek(GenesisScript.DURATION)
	var bodies := _bodies(_root, {})
	for id in GenesisCatalog.all_ids():
		assert_true(bodies.has(id), "pick body for %s" % id)
		assert_eq((bodies[id] as StaticBody3D).collision_layer, 2, "%s pickable once it exists" % id)
		var root := _group_root(id)
		assert_not_null(root, "visual root in entity_%s" % id)
		if root:
			assert_true(root.is_visible_in_tree(), "%s visible once it exists" % id)
	for id in [&"belt_memory", &"relations"]:
		assert_true(_group_root(id).has_meta(&"label_anchor"), "%s names a point of its own (label_anchor)" % id)


func test_bodies_hidden_until_they_exist() -> void:
	await _seek(1.0)
	for id in [&"hand_left", &"hand_right", &"planet_forming", &"moon_0", &"moon_1", &"ring_skill",
			&"belt_memory", &"relations"]:
		assert_false(_group_root(id).is_visible_in_tree(), "%s hidden at 1 s" % id)
	assert_true(_group_root(&"miku").is_visible_in_tree(), "MIKU is always there (her seed glows in the dark)")
	var bodies := _bodies(_root, {})
	assert_eq((bodies[&"planet_forming"] as StaticBody3D).collision_layer, 0, "no planet to pick yet")


func test_audio_anchors() -> void:
	var kinds := {}
	for n in _root.find_children("*", "Node3D", true, false):
		if n.has_meta(&"audio_anchor"):
			kinds[StringName(str(n.get_meta(&"audio_anchor")))] = n
	for k in [&"planet", &"miku", &"hands"]:
		assert_true(kinds.has(k), "audio anchor %s" % k)
	assert_almost_eq((kinds[&"planet"] as Node3D).global_position, GenesisLayout.PLANET_CENTER, Vector3.ONE * 1e-3)


func test_planet_follows_the_story_and_seek() -> void:
	var planet: FormingPlanet = _n["FormingPlanet"]
	await _seek(GenesisScript.T_SEEDED - 0.5)
	assert_false(planet.body.visible)
	await _seek(GenesisScript.LAYER_TIMES[0] + 5.0)
	var mid_r := planet.radius()
	assert_gt(mid_r, GenesisLayout.PLANET_STEP_RADII[0])
	assert_almost_eq(float(planet.material().get_shader_parameter("heat")), 1.0, 0.02, "the mantle burns")
	assert_eq(float(planet.material().get_shader_parameter("crust")), 0.0)
	await _seek(GenesisScript.DURATION)
	assert_almost_eq(planet.radius(), GenesisLayout.PLANET_RADIUS, 1e-3)
	assert_almost_eq(float(planet.material().get_shader_parameter("crust")), 1.0, 1e-3)
	assert_almost_eq(float(planet.material().get_shader_parameter("atmosphere")), 1.0, 1e-3)
	# Seek back: exactly the earlier frame again.
	await _seek(GenesisScript.LAYER_TIMES[0] + 5.0)
	assert_almost_eq(planet.radius(), mid_r, 1e-4, "seek rebuilds the same instant")
	Simulation.reset()
	await wait_process_frames(2)
	assert_false(planet.body.visible, "reset: no world")


func test_hands_rise_and_work() -> void:
	var hands: AuxiliaryHands = _n["AuxiliaryHands"]
	await _seek(GenesisScript.T_HANDS - 0.1)
	assert_false((hands.pivots[&"hand_left"] as Node3D).visible, "in the mist")
	await _seek(GenesisScript.T_HANDS + GenesisChoreography.HANDS_RISE + 1.0)
	var rest := GenesisLayout.hand_rest(true).origin
	assert_lt((hands.pivots[&"hand_left"] as Node3D).position.distance_to(rest), 0.5, "risen to its pose")
	var v_rest := hands.veins_of(&"hand_right")
	await _seek(GenesisScript.LAYER_TIMES[1] + GenesisChoreography.SCULPT_RISE)
	assert_gt(hands.veins_of(&"hand_right"), v_rest, "the kintsugi wakes while the hand sculpts")


func test_miku_wakes() -> void:
	var miku: Miku = _n["Miku"]
	await _seek(1.0)
	assert_false(miku.halo.visible, "no halo asleep")
	assert_false(miku.body.visible, "asleep the porcelain is in the dark (no silhouette)")
	assert_false(miku.hair_pivot.visible, "no hair in the dark")
	assert_true(miku.seed_motes.visible, "only the ember on her brow")
	assert_eq(miku.body.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no self-shadow steps on MIKU")
	var short := miku.hair_pivot.scale.x
	await _seek(GenesisScript.T_AWAKEN + 2.5)
	assert_true(miku.body.visible)
	assert_gt(miku.body.transparency, 0.05, "revealed by the seed's light, not popped in")
	assert_gt(miku.seed_light.omni_range, Miku.SEED_LIGHT_RANGE + 1.0, "the seed's light blooms out")
	await _seek(GenesisScript.T_AWAKEN + 12.0)
	assert_true(miku.halo.visible)
	assert_eq(miku.body.transparency, 0.0, "opaque once revealed")
	assert_gt(miku.hair_pivot.scale.x, short, "the hair unfurls")
	assert_true(miku.seed_motes.visible, "the seed on her brow")
	var tilt_before := miku.figure.basis.y.normalized().z
	await _seek(GenesisScript.DURATION)
	await wait_process_frames(2)
	assert_lt(miku.figure.basis.y.normalized().z, tilt_before - 0.03, "she raises her head at the climax")


func test_hands_let_go_after_stable() -> void:
	var hands: AuxiliaryHands = _n["AuxiliaryHands"]
	await _seek(GenesisScript.T_STABLE)
	var at_stable: Vector3 = (hands.pivots[&"hand_right"] as Node3D).position
	var left_at_stable: Vector3 = (hands.pivots[&"hand_left"] as Node3D).position
	await _seek(GenesisScript.DURATION)
	assert_gt((hands.pivots[&"hand_right"] as Node3D).position.distance_to(GenesisLayout.PLANET_CENTER),
		at_stable.distance_to(GenesisLayout.PLANET_CENTER) + 0.5, "the right hand withdraws from the world")
	assert_gt((hands.pivots[&"hand_left"] as Node3D).position.distance_to(GenesisLayout.PLANET_CENTER),
		left_at_stable.distance_to(GenesisLayout.PLANET_CENTER) + 0.5, "the left hand lowers away")
	assert_lt(hands.veins_of(&"hand_right"), 0.12, "the kintsugi has cooled")


func test_the_stable_wave_lights_the_threads() -> void:
	var rt: RelationThreads = _n["RelationThreads"]
	await _seek(GenesisScript.T_STABLE - 0.2)
	var base := float(rt.threads[0].material_override.get_shader_parameter("intensity"))
	await _seek(GenesisScript.T_STABLE + GenesisChoreography.WAVE_DELAY + GenesisChoreography.WAVE_HOP * 0.5)
	assert_gt(float(rt.threads[0].material_override.get_shader_parameter("intensity")), base * 1.5,
		"the pulse lights MIKU's thread as it runs")
	assert_true(rt.pulses.visible)


func test_universe_is_populated() -> void:
	var orb: OrbitalSystem = _n["OrbitalSystem"]
	await _seek(GenesisScript.DURATION)
	assert_gte(GenesisLayout.BELT_ROCKS + OrbitalSystem.BELT_DUST, 3000, "thousands of belt instances")
	assert_true(orb.belt_dust.is_visible_in_tree())
	assert_eq(orb.belt_dust.transparency, 0.0, "formed belt: dust at full presence")
	assert_not_null(orb.far_ring, "NAUVE-2 carries its own ring")
	assert_not_null(orb.far_moon2_pivot, "KESTRE-4 a second moon")


func test_orbital_bodies_appear_on_their_events() -> void:
	var orb: OrbitalSystem = _n["OrbitalSystem"]
	await _seek(GenesisScript.MOON_TIMES[0] + 2.0)
	assert_true(orb.moons[0].visible)
	assert_false(orb.moons[1].visible)
	assert_false(orb.ring.visible)
	await _seek(GenesisScript.DURATION)
	assert_true(orb.moons[1].visible and orb.ring.visible and orb.belt.visible)
	for w in orb.far_planets:
		assert_true(w.is_visible_in_tree(), "the older worlds are always there")


func test_threads_weave_after_links() -> void:
	var rt: RelationThreads = _n["RelationThreads"]
	await _seek(GenesisScript.T_LINKS - 0.2)
	assert_false(rt.visible)
	await _seek(GenesisScript.T_LINKS + 0.6)
	assert_true(rt.visible)
	assert_true(rt.threads[0].visible, "the first thread is being spun")
	assert_false(rt.threads[7].visible, "the backlink comes last")
	await _seek(GenesisScript.DURATION)
	for th in rt.threads:
		assert_true(th.visible)
		assert_not_null(th.mesh)


func test_light_rig_writes_only_ambient() -> void:
	var rig: GenesisLightRig = _n["GenesisLightRig"]
	var exposure := _env.tonemap_exposure
	await _seek(1.0)
	var asleep := _env.ambient_light_energy
	await _seek(20.0)
	assert_gt(_env.ambient_light_energy, asleep, "ambient grows with the awakening")
	assert_eq(_env.tonemap_exposure, exposure, "exposure belongs to GenesisEnvironment")
	for l in [rig.back, rig.rim, rig.key, rig.fill]:
		assert_lte(l.light_volumetric_fog_energy, GenesisEnvironment.DIRECTIONAL_FOG_ENERGY)
	assert_true(rig.planet_glow.visible, "the molten world glows")
	assert_true(rig.key.shadow_enabled == bool(Quality.profile.get("shadows", true)))


func test_camera_uses_genesis_shots_and_focuses_every_body() -> void:
	var director: CameraDirector = _n["CameraDirector"]
	await _seek(30.0)
	director.snap_to_mode_shot()
	var goal := CameraShots.Shot.new()
	GenesisShots.desired(Session.mode, Session.cinematic, Simulation.genesis, Simulation.time, MotionClock.now(), goal)
	assert_lt(director.rig().target.distance_to(goal.target), 0.05, "GENESIS cue")
	await _seek(GenesisScript.DURATION)
	for id in GenesisCatalog.all_ids():
		assert_true(director.focus_on(id), "focus on %s" % id)
		assert_eq(director.focused(), id)
	assert_gte(StyleFrames.poses_from(director).size(), StyleFrames.MIN_FRAMES)
	assert_eq(str(StyleFrames.poses_from(director)[0]["name"]), "sf_01_hero", "the director's poses")


func test_selection_highlights() -> void:
	await _seek(GenesisScript.DURATION)
	var miku: Miku = _n["Miku"]
	Session.select(&"miku")
	await wait_process_frames(30)
	assert_gt(float(miku.body.material_override.get_shader_parameter("select")), 0.1)


func test_particles_scale_with_quality() -> void:
	var dust: Stardust = _n["Stardust"]
	var before := Quality.level
	Quality.override_for_session(QualityProfiles.Level.HIGH)
	var high := dust.river.visible_count
	assert_eq(high, Stardust.RIVER_MOTES)
	Quality.override_for_session(QualityProfiles.Level.LOW)
	assert_lt(dust.river.visible_count, high, "LOW draws fewer motes")
	assert_gt((_n["OrbitalSystem"] as OrbitalSystem).belt_rocks.multimesh.visible_instance_count, 0)
	Quality.override_for_session(before)
