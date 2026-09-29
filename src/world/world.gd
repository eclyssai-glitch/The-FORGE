extends Node3D
## Composes the 3D world of the ORIGIN CHAMBER (root of scenes/world.tscn).
##
## Order: WorldEnvironment (EnvironmentProfile) -> LightRig -> ChamberArchitecture -> OriginCore
## -> FragmentStructure -> VerificationArray -> fx (ActivationPulse, DustField, EmissionSparks)
## -> Universe -> CameraDirector -> Picker.
## Entity/fx/camera modules are loaded by path and skipped with a warning when their script
## does not exist yet, so the world always runs with whatever is present. Without a
## CameraDirector a fixed fallback Camera3D (current) frames each mode.
## Quality: EnvironmentProfile.apply_quality on Quality.profile_changed (and at start).
## Mode: EnvironmentProfile.apply_mode_fog + Universe.apply_mode on Session.mode_changed (and at start).
## Module check: `missing_modules()` lists every expected module that did not load; the smoke
## test fails on any (report line `modules=N/N`).

## [node name, script path] in composition order. Every module has a no-argument constructor.
const MODULES: Array = [
	["LightRig", "res://src/entities/light_rig.gd"],
	["ChamberArchitecture", "res://src/entities/chamber_architecture.gd"],
	["OriginCore", "res://src/entities/origin_core.gd"],
	["FragmentStructure", "res://src/entities/fragment_structure.gd"],
	["VerificationArray", "res://src/entities/verification_array.gd"],
	["ActivationPulse", "res://src/fx/activation_pulse.gd"],
	["DustField", "res://src/fx/dust_field.gd"],
	["EmissionSparks", "res://src/fx/emission_sparks.gd"],
]
const CAMERA_DIRECTOR := ["CameraDirector", "res://src/animation/camera_director.gd"]
## Group used by automation to snap the camera to the current mode's shot.
const CAMERA_GROUP := &"camera_director"

## Fallback framing per mode when no CameraDirector exists: [position, look-at target].
const FALLBACK_SHOTS := {
	SessionState.Mode.UNIVERSE: [Vector3(42.7, 29.3, 74.0), Vector3(0.0, 1.0, 0.0)],
	SessionState.Mode.FORGE: [Vector3(0.0, 1.0, 9.5), Vector3(0.0, 0.3, 0.0)],
	SessionState.Mode.OBSERVATORY: [Vector3(-3.5, 2.2, 11.0), Vector3(-1.6, 0.2, 0.0)],
}

## Missing-module warnings already printed (once per path per run).
static var _warned: Dictionary = {}

var environment: Environment
var world_environment: WorldEnvironment
var universe: Universe
var picker: Picker
## Module nodes by name (only the ones that were found), including "CameraDirector".
var modules: Dictionary = {}
## Fixed camera used only when no CameraDirector module exists.
var fallback_camera: Camera3D


func _ready() -> void:
	environment = EnvironmentProfile.make_environment()
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	for m in MODULES:
		var node := load_module(m[1])
		if node == null:
			continue
		node.name = m[0]
		if m[0] == "LightRig":
			node.set("environment", environment)
		add_child(node)
		modules[m[0]] = node

	universe = Universe.new()
	universe.apply_sky(environment)
	add_child(universe)

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
	if not Quality.profile.is_empty():
		_on_quality_changed(Quality.profile)
	_on_mode_changed(Session.mode)


## Node names of every module the world expects (MODULES + the CameraDirector), in order.
static func expected_module_names() -> Array[String]:
	var out: Array[String] = []
	for m in MODULES:
		out.append(String(m[0]))
	out.append(String(CAMERA_DIRECTOR[0]))
	return out


## Expected modules that were not composed (missing script, not a Node, not instantiable).
func missing_modules() -> Array[String]:
	var out: Array[String] = []
	for n in expected_module_names():
		if not modules.has(n):
			out.append(n)
	return out


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


func _on_quality_changed(profile: Dictionary) -> void:
	EnvironmentProfile.apply_quality(environment, profile)


func _on_mode_changed(mode: SessionState.Mode) -> void:
	EnvironmentProfile.apply_mode_fog(environment, mode)
	universe.apply_mode(mode)
	if fallback_camera:
		var shot: Array = FALLBACK_SHOTS.get(mode, FALLBACK_SHOTS[SessionState.Mode.FORGE])
		fallback_camera.position = shot[0]
		fallback_camera.look_at(shot[1])
