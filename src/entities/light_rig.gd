class_name LightRig
extends Node3D
## Lights of the ORIGIN CHAMBER. Owner: animator (levels and colours from EnvironmentProfile).
## Key (BONE, high angle from the front-left), fill (cool, low, front-right), rim (cool, from
## behind the subject) and the core light (EMBER omni at the core — the only warm light, off
## while dormant). Levels per story stage (EnvironmentProfile.LIGHT) are blended by
## Choreography.light_levels from the world timestamps, so seek/pause are always consistent.
## `environment` (set by the world before add_child) receives ambient, exposure and
## volumetric fog density of the stage; exposure is scaled per Session mode by
## EnvironmentProfile.mode_fog(mode)["exposure_scale"]. The Environment is only written when a
## value changes (a steady stage costs no resource updates); Simulation.world_rebuilt clears that
## cache. Every light gets
## EnvironmentProfile.FOG_LIGHT. Key shadow splits follow Quality.profile["shadow_splits"] (and,
## with 2 splits, a shorter and softer key shadow: shadow_reach_for).

## Core light: reach and falloff (the core lights the inner faces of the rings and fades before
## the outer walls; the key lights the outside), and a low specular so the metal does not show a
## hot point where the core reflects.
const CORE_RANGE := 12.0
const CORE_ATTENUATION := 2.2
## (0.35 left a copper hot spot on the one segment facing the camera, read as a selection;
## at 0.1 it is a soft warm glint spread over the ring under the core.)
const CORE_SPECULAR := 0.1
## Key shadow: normal bias and blur keep the rings free of acne and the edges soft.
const KEY_SHADOW_NORMAL_BIAS := 2.0
const KEY_SHADOW_BLUR := 1.8
const KEY_SHADOW_MAX_DISTANCE := 40.0
## With 2 cascades (LOW) the texels over 40 units were coarse enough to draw stepped stains on the
## ring tops (seen in OBSERVATORY): the key covers a shorter reach (the chamber seen from FORGE and
## OBSERVATORY stays inside it) with a softer blur. 1 or 4 cascades keep the values above.
const KEY_SHADOW_MAX_DISTANCE_2_SPLITS := 24.0
const KEY_SHADOW_BLUR_2_SPLITS := 2.5

var environment: Environment

var key: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D
var core: OmniLight3D

var _levels := {}
## Exposure multiplier of the current Session mode (read on mode change, not per frame).
var _exposure_scale := 1.0
## Last values written to the Environment (ambient, exposure, fog density).
var _env_written := Vector3(-1.0, -1.0, -1.0)


func _ready() -> void:
	# Directions point from the light towards the subject (the core at the origin).
	key = _directional("Key", EnvironmentProfile.KEY_COLOR, Vector3(0.55, -1.0, -0.45), "key")
	fill = _directional("Fill", EnvironmentProfile.FILL_COLOR, Vector3(-0.9, -0.25, -0.35), "fill")
	# Rim from high behind (~40°): separates silhouettes and keeps its floor reflection out of frame.
	rim = _directional("Rim", EnvironmentProfile.RIM_COLOR, Vector3(0.3, -0.8, 0.9), "rim")
	core = OmniLight3D.new()
	core.name = "CoreLight"
	core.light_color = EnvironmentProfile.CORE_COLOR
	core.omni_range = CORE_RANGE
	core.omni_attenuation = CORE_ATTENUATION
	core.light_energy = 0.0
	core.light_specular = CORE_SPECULAR
	core.shadow_enabled = false
	core.light_volumetric_fog_energy = float(EnvironmentProfile.FOG_LIGHT["core"])
	add_child(core)
	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)
	Session.mode_changed.connect(_on_mode_changed)
	Simulation.world_rebuilt.connect(_on_world_rebuilt)
	_on_mode_changed(Session.mode)


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var w := Simulation.world
	var t := Simulation.time
	Choreography.light_levels(w, t, _levels)
	key.light_energy = _levels["key"]
	fill.light_energy = _levels["fill"]
	rim.light_energy = _levels["rim"]
	var pulse := Choreography.core_pulse(w, t)
	core.light_energy = float(_levels["core"]) * (0.82 + 0.3 * pulse)
	core.visible = core.light_energy > 0.001
	key.visible = key.light_energy > 0.001
	if environment == null:
		return
	var env_now := Vector3(_levels["ambient"], float(_levels["exposure"]) * _exposure_scale, _levels["fog"])
	if env_now.is_equal_approx(_env_written):
		return
	_env_written = env_now
	environment.ambient_light_energy = env_now.x
	environment.tonemap_exposure = env_now.y
	environment.volumetric_fog_density = env_now.z


## Tonemap exposure multiplier of a Session mode (EnvironmentProfile.mode_fog, default 1).
static func exposure_scale_for(mode: int) -> float:
	return float(EnvironmentProfile.mode_fog(mode).get("exposure_scale", 1.0))


## Last values written to the Environment: (ambient, exposure, volumetric fog density).
func environment_written() -> Vector3:
	return _env_written


## Seek/reset: forget what was written, so the next frame writes the Environment again even if
## someone else changed it meanwhile (the cache only skips writes of a steady stage).
func _on_world_rebuilt() -> void:
	_env_written = Vector3(-1.0, -1.0, -1.0)
	_update()


func _on_mode_changed(mode: int) -> void:
	_exposure_scale = exposure_scale_for(mode)
	_update()


func _directional(n: String, color: Color, dir: Vector3, fog_key: String) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = n
	l.light_color = color
	l.light_energy = 0.0
	l.light_volumetric_fog_energy = float(EnvironmentProfile.FOG_LIGHT[fog_key])
	l.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), Vector3.ZERO)
	add_child(l)
	return l


func _on_quality(profile: Dictionary) -> void:
	var shadows := bool(profile.get("shadows", true))
	var splits := int(profile.get("shadow_splits", 4))
	var reach := shadow_reach_for(splits)
	key.shadow_enabled = shadows
	key.directional_shadow_mode = shadow_mode_for(splits)
	key.directional_shadow_max_distance = reach.x
	key.shadow_normal_bias = KEY_SHADOW_NORMAL_BIAS
	key.shadow_blur = reach.y
	rim.shadow_enabled = false
	fill.shadow_enabled = false


## Key shadow (max distance, blur) for a number of PSSM splits: shorter and softer with 2.
static func shadow_reach_for(splits: int) -> Vector2:
	if splits == 2:
		return Vector2(KEY_SHADOW_MAX_DISTANCE_2_SPLITS, KEY_SHADOW_BLUR_2_SPLITS)
	return Vector2(KEY_SHADOW_MAX_DISTANCE, KEY_SHADOW_BLUR)


## DirectionalLight3D shadow mode for a number of PSSM splits (1, 2 or 4; anything else -> 4).
static func shadow_mode_for(splits: int) -> DirectionalLight3D.ShadowMode:
	match splits:
		1:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		2:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
