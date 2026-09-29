class_name LightRig
extends Node3D
## Lights of the ORIGIN CHAMBER. Owner: animator (levels and colours from EnvironmentProfile).
## Key (BONE, high angle from the front-left), fill (cool, low, front-right), rim (cool, from
## behind the subject) and the core light (EMBER omni at the core — the only warm light, off
## while dormant). Levels per story stage (EnvironmentProfile.LIGHT) are blended by
## Choreography.light_levels from the world timestamps, so seek/pause are always consistent.
## `environment` (set by the world before add_child) receives ambient, exposure and
## volumetric fog density of the stage. Every light gets EnvironmentProfile.FOG_LIGHT.

var environment: Environment

var key: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D
var core: OmniLight3D

var _levels := {}


func _ready() -> void:
	# Directions point from the light towards the subject (the core at the origin).
	key = _directional("Key", EnvironmentProfile.KEY_COLOR, Vector3(0.55, -1.0, -0.45), "key")
	fill = _directional("Fill", EnvironmentProfile.FILL_COLOR, Vector3(-0.9, -0.25, -0.35), "fill")
	# Rim from high behind (~40°): separates silhouettes and keeps its floor reflection out of frame.
	rim = _directional("Rim", EnvironmentProfile.RIM_COLOR, Vector3(0.3, -0.8, 0.9), "rim")
	core = OmniLight3D.new()
	core.name = "CoreLight"
	core.light_color = EnvironmentProfile.CORE_COLOR
	# Short reach: the core lights the inner faces of the rings, the key lights the outside.
	core.omni_range = 8.0
	core.omni_attenuation = 1.5
	core.light_energy = 0.0
	core.light_specular = 0.6
	core.shadow_enabled = false
	core.light_volumetric_fog_energy = float(EnvironmentProfile.FOG_LIGHT["core"])
	add_child(core)
	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)
	_update()


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
	if environment:
		environment.ambient_light_energy = _levels["ambient"]
		environment.tonemap_exposure = _levels["exposure"]
		environment.volumetric_fog_density = _levels["fog"]


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
	key.shadow_enabled = shadows
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_max_distance = 40.0
	key.shadow_blur = 1.2
	rim.shadow_enabled = false
	fill.shadow_enabled = false
