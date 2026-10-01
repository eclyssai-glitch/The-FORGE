extends Node3D
## Composes the 3D world of the active scenario (root of scenes/world.tscn).
##
## Children, in order: WorldEnvironment -> scenario modules (MODULES_BY_SCENARIO) -> Universe
## (ORIGIN CHAMBER only) -> AudioDirector -> CameraDirector (or FallbackCamera) -> Picker.
## Scenario modules are composed for `Simulation.scenario` and recomposed on
## `Simulation.scenario_changed` (old ones leave the tree and are freed; the environment is
## rebuilt for the scenario). AudioDirector, CameraDirector and Picker persist across scenarios.
## Modules are loaded by path and skipped with a warning when their script does not exist yet,
## so the world always runs with whatever is present. A module that declares a property
## `environment` receives the world's Environment before add_child. Without a CameraDirector a
## fixed fallback Camera3D (current) frames each mode.
## Environment: ORIGIN = EnvironmentProfile (+ Universe sky); GENESIS = GenesisEnvironment
## (nebula sky, AgX, contained glow, light fog). Quality: MaterialLibrary.apply_quality and the
## scenario's apply_quality on Quality.profile_changed (and at start). Mode: the scenario's fog/sky
## settings on Session.mode_changed (and at start). GENESIS, every frame:
## MaterialLibrary.set_motion_time(MotionClock.now()); the sky's own `motion_time` is stepped at
## GenesisEnvironment.SKY_MOTION_HZ (static in LOW).
## Audio: the AudioDirector (group `audio_director`) is composed in every scenario; every Node3D
## of the world with meta `audio_anchor` (&"planet" | &"miku" | &"hands") becomes
## `set_anchor(kind, node)` — scanned after each composition and for nodes added later
## (SceneTree.node_added, checked at the end of the frame so metas set in _ready count).
## Module check: `missing_modules()` lists every module expected for the composed scenario that
## did not load; the smoke test fails on any (report line `modules=N/M`).

## [node name, script path] in composition order. Every module has a no-argument constructor.
const ORIGIN_MODULES: Array = [
	["LightRig", "res://src/entities/light_rig.gd"],
	["ChamberArchitecture", "res://src/entities/chamber_architecture.gd"],
	["OriginCore", "res://src/entities/origin_core.gd"],
	["FragmentStructure", "res://src/entities/fragment_structure.gd"],
	["VerificationArray", "res://src/entities/verification_array.gd"],
	["ActivationPulse", "res://src/fx/activation_pulse.gd"],
	["DustField", "res://src/fx/dust_field.gd"],
	["EmissionSparks", "res://src/fx/emission_sparks.gd"],
]
## GENESIS scene modules (animator, Loop 4 phase B; fixed paths — docs/contracts/loop-04.md).
const GENESIS_MODULES: Array = [
	["GenesisLightRig", "res://src/entities/genesis/genesis_light_rig.gd"],
	["Miku", "res://src/entities/genesis/miku.gd"],
	["AuxiliaryHands", "res://src/entities/genesis/auxiliary_hands.gd"],
	["FormingPlanet", "res://src/entities/genesis/forming_planet.gd"],
	["OrbitalSystem", "res://src/entities/genesis/orbital_system.gd"],
	["RelationThreads", "res://src/entities/genesis/relation_threads.gd"],
	["Stardust", "res://src/fx/genesis/stardust.gd"],
	["FormationGlow", "res://src/fx/genesis/formation_glow.gd"],
]
const MODULES_BY_SCENARIO: Dictionary = {
	Scenario.ORIGIN_CHAMBER: ORIGIN_MODULES,
	Scenario.GENESIS: GENESIS_MODULES,
}
## Legacy name: the ORIGIN CHAMBER modules.
const MODULES: Array = ORIGIN_MODULES
const AUDIO_DIRECTOR := ["AudioDirector", "res://src/audio/audio_director.gd"]
const CAMERA_DIRECTOR := ["CameraDirector", "res://src/animation/camera_director.gd"]
## Group used by automation to snap the camera to the current mode's shot.
const CAMERA_GROUP := &"camera_director"
## Group of the AudioDirector (UI sounds: call_group(AUDIO_GROUP, &"play_ui", ...)).
const AUDIO_GROUP := &"audio_director"
## Meta that marks a Node3D as the source of a kind of sound (value: &"planet" | &"miku" | &"hands").
const AUDIO_ANCHOR_META := &"audio_anchor"
## Anchor kinds the GENESIS scene is expected to register (the smoke checks them).
const GENESIS_AUDIO_ANCHORS: Array[StringName] = [&"planet", &"miku", &"hands"]

## Fallback framing per mode when no CameraDirector exists: [position, look-at target].
const FALLBACK_SHOTS := {
	SessionState.Mode.UNIVERSE: [Vector3(42.7, 29.3, 74.0), Vector3(0.0, 1.0, 0.0)],
	SessionState.Mode.FORGE: [Vector3(0.0, 1.0, 9.5), Vector3(0.0, 0.3, 0.0)],
	SessionState.Mode.OBSERVATORY: [Vector3(-3.5, 2.2, 11.0), Vector3(-1.6, 0.2, 0.0)],
}
## GENESIS fallback framing (layout of docs/contracts/loop-04.md: MIKU at (0, 4, 0), planet at
## (0, 1, 4), belt r 16–19, far planets r 11 and 24).
const FALLBACK_SHOTS_GENESIS := {
	SessionState.Mode.UNIVERSE: [Vector3(0.0, 26.0, 44.0), Vector3(0.0, 2.0, 0.0)],
	SessionState.Mode.FORGE: [Vector3(0.0, 0.4, 17.0), Vector3(0.0, 4.0, 1.5)],
	SessionState.Mode.OBSERVATORY: [Vector3(-13.0, 10.0, 16.0), Vector3(0.0, 3.0, 2.0)],
}

## Missing-module warnings already printed (once per path per run).
static var _warned: Dictionary = {}

## Scenario the world is composed for (follows Simulation.scenario).
var scenario: StringName = &""
var environment: Environment
var world_environment: WorldEnvironment
## ORIGIN CHAMBER only (null in GENESIS).
var universe: Universe
## GENESIS sky (the world's duplicate of MaterialLibrary.nebula_sky()); created on first use.
var genesis_sky: ShaderMaterial
var picker: Picker
var audio_director: Node
## Module nodes by name (only the ones that were found), including "AudioDirector" and
## "CameraDirector".
var modules: Dictionary = {}
## Fixed camera used only when no CameraDirector module exists.
var fallback_camera: Camera3D
## Audio anchors registered by the world: kind -> Node3D.
var audio_anchors: Dictionary = {}

## Scenario module nodes currently composed (freed on recomposition).
var _scenario_nodes: Array[Node] = []
var _sky_motion_enabled := true
var _sky_motion_applied := -1.0

## GENESIS environment shown now (GenesisEnvironment.MODES layout) and the mode blend in flight:
## from, to, seconds elapsed (>= MODE_BLEND = settled). Empty until the first mode is applied.
var _env_current: Dictionary = {}
var _env_from: Dictionary = {}
var _env_to: Dictionary = {}
var _env_elapsed := 0.0
## Exposure trim shown now and its target (World.set_exposure_trim; 1 = the mode's exposure).
var exposure_trim := 1.0
var _trim_target := 1.0


func _ready() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	add_child(world_environment)

	_compose_scenario(Simulation.scenario)

	audio_director = load_module(AUDIO_DIRECTOR[1])
	if audio_director:
		audio_director.name = AUDIO_DIRECTOR[0]
		audio_director.add_to_group(AUDIO_GROUP)
		add_child(audio_director)
		modules[AUDIO_DIRECTOR[0]] = audio_director

	var director := load_module(CAMERA_DIRECTOR[1])
	if director:
		director.name = CAMERA_DIRECTOR[0]
		director.add_to_group(CAMERA_GROUP)
		add_child(director)
		modules[CAMERA_DIRECTOR[0]] = director
	else:
		fallback_camera = Camera3D.new()
		fallback_camera.name = "FallbackCamera"
		fallback_camera.fov = 50.0
		fallback_camera.far = 800.0
		add_child(fallback_camera)
		fallback_camera.make_current()

	picker = Picker.new()
	add_child(picker)

	Quality.profile_changed.connect(_on_quality_changed)
	Session.mode_changed.connect(_on_mode_changed)
	Simulation.scenario_changed.connect(_on_scenario_changed)
	get_tree().node_added.connect(_on_node_added)
	_apply_quality_and_mode()
	register_audio_anchors()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(delta: float) -> void:
	if scenario != Scenario.GENESIS:
		return
	_step_environment(delta)
	var t := MotionClock.now()
	MaterialLibrary.set_motion_time(t)
	if _sky_motion_enabled and genesis_sky:
		var step := GenesisEnvironment.sky_motion_step(t)
		if step != _sky_motion_applied:
			_sky_motion_applied = step
			genesis_sky.set_shader_parameter("motion_time", step)


## GENESIS: asks for an exposure trim (x the mode's exposure; clamped to
## GenesisEnvironment.TRIM_RANGE). The environment eases towards it (TRIM_TAU), so a camera cue
## can compensate a darker framing without a pop. Ignored outside GENESIS; reset on recomposition.
func set_exposure_trim(trim: float) -> void:
	_trim_target = GenesisEnvironment.clamp_trim(trim)


## Target of the exposure trim (1 = none).
func exposure_trim_target() -> float:
	return _trim_target


## True while a GENESIS mode blend is in flight.
func environment_blending() -> bool:
	return not _env_current.is_empty() and _env_elapsed < GenesisEnvironment.MODE_BLEND


## Ends any GENESIS environment blend and trim easing at once (automation snaps, composition).
func snap_environment() -> void:
	if scenario != Scenario.GENESIS or environment == null:
		return
	if not _env_to.is_empty():
		_env_current = _env_to.duplicate()
		_env_from = _env_current
	_env_elapsed = GenesisEnvironment.MODE_BLEND
	exposure_trim = _trim_target
	if not _env_current.is_empty():
		GenesisEnvironment.apply_settings(environment, genesis_sky, _env_current, exposure_trim)


## Per-frame GENESIS environment easing (real time, like the camera's transitions): the mode
## blend and the exposure trim. Writes the environment only while something moves.
func _step_environment(delta: float) -> void:
	if _env_current.is_empty() or environment == null:
		return
	var dirty := false
	if _env_elapsed < GenesisEnvironment.MODE_BLEND:
		_env_elapsed = minf(_env_elapsed + delta, GenesisEnvironment.MODE_BLEND)
		var k := GenesisEnvironment.blend_weight(_env_elapsed / GenesisEnvironment.MODE_BLEND)
		_env_current = GenesisEnvironment.blend_settings(_env_from, _env_to, k)
		dirty = true
	if exposure_trim != _trim_target:
		exposure_trim = GenesisEnvironment.smooth_toward(exposure_trim, _trim_target, delta)
		dirty = true
	if dirty:
		GenesisEnvironment.apply_settings(environment, genesis_sky, _env_current, exposure_trim)


## Modules [name, path] of a scenario (ORIGIN CHAMBER for an unknown id).
static func modules_for(id: StringName) -> Array:
	return MODULES_BY_SCENARIO.get(id, ORIGIN_MODULES)


## Node names of every module the world expects for a scenario (its modules + AudioDirector +
## CameraDirector), in order. Without an id: the active scenario (Simulation.scenario).
static func expected_module_names(id: StringName = &"") -> Array[String]:
	var sid := id if id != &"" else Simulation.scenario
	var out: Array[String] = []
	for m in modules_for(sid):
		out.append(String(m[0]))
	out.append(String(AUDIO_DIRECTOR[0]))
	out.append(String(CAMERA_DIRECTOR[0]))
	return out


## Expected modules of the composed scenario that were not composed (missing script, not a
## Node, not instantiable).
func missing_modules() -> Array[String]:
	var out: Array[String] = []
	for n in expected_module_names(scenario):
		if not modules.has(n):
			out.append(n)
	return out


## Scenario module nodes currently composed, in order.
func scenario_nodes() -> Array[Node]:
	return _scenario_nodes.duplicate()


## Instantiates the script at `path` (no-argument constructor), or returns null with a warning
## when the file is missing or is not a Node.
static func load_module(path: String) -> Node:
	if not ResourceLoader.exists(path):
		if not _warned.has(path):
			_warned[path] = true
			push_warning("World: module %s not found; skipped." % path)
		return null
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		push_warning("World: module %s cannot be instantiated; skipped." % path)
		return null
	var obj: Variant = script.new()
	if not obj is Node:
		push_warning("World: module %s is not a Node; skipped." % path)
		if obj is Object and not obj is RefCounted:
			(obj as Object).free()
		return null
	return obj


## Registers as audio anchor every Node3D under `root` (default: the whole world) that carries
## the AUDIO_ANCHOR_META meta. Returns how many anchors were registered.
func register_audio_anchors(root: Node = null) -> int:
	var from := root if root != null else self
	var count := 0
	if register_audio_anchor(from):
		count += 1
	for n in from.find_children("*", "Node3D", true, false):
		if register_audio_anchor(n):
			count += 1
	return count


## Registers `node` with the AudioDirector if it is a Node3D of this world with a non-empty
## AUDIO_ANCHOR_META. Returns true when it was registered.
func register_audio_anchor(node: Variant) -> bool:
	if audio_director == null or not is_instance_valid(node) or not node is Node3D:
		return false
	var n := node as Node3D
	if not n.has_meta(AUDIO_ANCHOR_META) or not n.is_inside_tree() or not is_ancestor_of(n):
		return false
	var kind := StringName(str(n.get_meta(AUDIO_ANCHOR_META)))
	if kind == &"":
		return false
	if audio_director.has_method(&"set_anchor"):
		audio_director.call(&"set_anchor", kind, n)
	audio_anchors[kind] = n
	return true


## Anchor kinds currently registered by live nodes, sorted.
func audio_anchor_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in audio_anchors:
		var n: Variant = audio_anchors[k]
		if is_instance_valid(n) and (n as Node).is_inside_tree():
			out.append(k)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Stops every audio player of the world at once (AudioDirector voices and ambience). Called
## before a scripted quit: the AudioServer releases a stopped playback on its next mix step, so a
## player still playing when the engine shuts down is reported as "resources still in use at
## exit" (the ambience stream and its playback). Returns how many players were stopped.
func silence_audio() -> int:
	var n := 0
	for p in find_children("*", "AudioStreamPlayer", true, false) \
			+ find_children("*", "AudioStreamPlayer3D", true, false):
		if p.get(&"playing") or p.get(&"stream_paused"):
			p.call(&"stop")
			n += 1
	return n


# ------------------------------------------------------------------ composition


## Rebuilds the environment and the scenario modules for `id`. Old modules leave the tree at
## once (their groups and pick bodies go with them) and are freed at the end of the frame.
func _compose_scenario(id: StringName) -> void:
	_clear_scenario()
	scenario = id if Scenario.is_valid(id) else Scenario.DEFAULT
	if scenario == Scenario.GENESIS:
		if genesis_sky == null:
			genesis_sky = GenesisEnvironment.make_sky_material()
		environment = GenesisEnvironment.make_environment(genesis_sky)
		_sky_motion_applied = -1.0
		_env_current = {}
		_env_to = {}
		exposure_trim = 1.0
		_trim_target = 1.0
	else:
		environment = EnvironmentProfile.make_environment()
	world_environment.environment = environment

	var at := world_environment.get_index() + 1
	for m in modules_for(scenario):
		var node := load_module(m[1])
		if node == null:
			continue
		node.name = m[0]
		if &"environment" in node:
			node.set(&"environment", environment)
		add_child(node)
		move_child(node, at)
		at += 1
		modules[m[0]] = node
		_scenario_nodes.append(node)

	if scenario == Scenario.ORIGIN_CHAMBER:
		universe = Universe.new()
		universe.apply_sky(environment)
		add_child(universe)
		move_child(universe, at)


func _clear_scenario() -> void:
	for n in _scenario_nodes:
		if not is_instance_valid(n):
			continue
		modules.erase(String(n.name))
		remove_child(n)
		n.queue_free()
	_scenario_nodes.clear()
	if universe:
		remove_child(universe)
		universe.queue_free()
		universe = null
	for k: StringName in audio_anchors.keys():
		var n: Variant = audio_anchors[k]
		if not is_instance_valid(n) or not (n as Node).is_inside_tree():
			audio_anchors.erase(k)


func _apply_quality_and_mode() -> void:
	if not Quality.profile.is_empty():
		_on_quality_changed(Quality.profile)
	_on_mode_changed(Session.mode)
	snap_environment()


func _on_scenario_changed(id: StringName) -> void:
	if id == scenario:
		return
	# Entities of the previous scenario no longer exist.
	Session.select(&"")
	Session.hover(&"")
	_compose_scenario(id)
	_apply_quality_and_mode()
	register_audio_anchors()


func _on_node_added(node: Node) -> void:
	if audio_director == null or not is_ancestor_of(node):
		return
	# Checked at the end of the frame: metas set in the node's _ready count.
	register_audio_anchor.call_deferred(node)


func _on_quality_changed(profile: Dictionary) -> void:
	MaterialLibrary.apply_quality(profile)
	if scenario == Scenario.GENESIS:
		GenesisEnvironment.apply_quality(environment, genesis_sky, profile)
		_sky_motion_enabled = GenesisEnvironment.sky_motion_enabled(profile)
	else:
		EnvironmentProfile.apply_quality(environment, profile)


func _on_mode_changed(mode: SessionState.Mode) -> void:
	if scenario == Scenario.GENESIS:
		_blend_environment_to(GenesisEnvironment.mode_settings(mode))
	else:
		EnvironmentProfile.apply_mode_fog(environment, mode)
	if universe:
		universe.apply_mode(mode)
	if fallback_camera:
		var shots: Dictionary = FALLBACK_SHOTS_GENESIS if scenario == Scenario.GENESIS else FALLBACK_SHOTS
		var shot: Array = shots.get(mode, shots[SessionState.Mode.FORGE])
		fallback_camera.position = shot[0]
		fallback_camera.look_at(shot[1])


## Starts blending the GENESIS environment from what is shown now to `target` (the first
## application lands at once).
func _blend_environment_to(target: Dictionary) -> void:
	if _env_current.is_empty():
		_env_current = target.duplicate()
		_env_from = _env_current
		_env_to = target.duplicate()
		_env_elapsed = GenesisEnvironment.MODE_BLEND
		GenesisEnvironment.apply_settings(environment, genesis_sky, _env_current, exposure_trim)
		return
	_env_from = _env_current.duplicate()
	_env_to = target.duplicate()
	_env_elapsed = 0.0
