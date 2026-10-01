class_name GenesisLightRig
extends Node3D
## Lights of the GENESIS scene (docs/VISUAL_DIRECTION.md §4). Owner: animator.
## Backlight first: a warm directional (DUSK_ROSE -> GOLD) from the nebula core behind MIKU cuts
## her, the hands and the planet out of the night; a cold ICE rim from behind/right separates the
## forms; a soft PEARL key from the three-quarter left side (never frontal: frontal light flattens
## the porcelain) gives volume and is the only shadow caster; a minimal NEBULA fill keeps the
## shadows night, not black. The forming planet lights the palms with its own GOLD/MAGMA glow
## (omni at the planet, energy with heat and formation).
## Levels grow with the awakening (GenesisChoreography.light_levels), so seek/pause are exact.
## `environment` (set by the world before add_child): only `ambient_light_energy` is written, and
## only when it changes (GenesisEnvironment owns exposure, fog and sky per mode). Directional
## lights use light_volumetric_fog_energy <= GenesisEnvironment.DIRECTIONAL_FOG_ENERGY (they turn
## the whole froxel volume milky); the planet glow gives the haze its body.

## Directions: from the light towards the scene (MIKU's heart).
const BACK_DIR := Vector3(0.05, -0.28, 1.0)
const RIM_DIR := Vector3(-0.85, -0.45, 0.6)
const KEY_DIR := Vector3(0.9, -0.5, -0.28)
const FILL_DIR := Vector3(-0.4, 0.35, -1.0)
const BACK_COLOR := Palette.DUSK_ROSE
## The warm backlight drifts from rose towards gold as the planet heats (creation light).
const BACK_GOLD_SHARE := 0.28
const RIM_COLOR := Palette.ICE
const KEY_COLOR := Palette.PEARL
const FILL_COLOR := Palette.NEBULA
## Planet glow: colour, reach and falloff; how much it scatters in the volumetric haze.
const PLANET_COLOR := Palette.GOLD
const PLANET_HOT_COLOR := Palette.MAGMA
const PLANET_RANGE := 7.5
const PLANET_ATTENUATION := 1.6
const PLANET_FOG := 0.6
const PLANET_SPECULAR := 0.35
## Climax (planet.stable): the world's sky light (colour) reaches farther (units at the peak).
const PLANET_SKY_COLOR := Palette.PEARL
const PLANET_SKY_ICE := 0.45
const PLANET_CLIMAX_REACH := 5.0
## Planet key: a PEARL key of the worlds' own (only GenesisLayout.PLANET_KEY_LAYER), from the left
## and a little above and in front of the hero camera — a three-quarter side light, so the formed
## world shows a lit crescent with its ICE limb, the DUSK_ROSE terminator across the disc and its
## continents, instead of the backlit night side. Warmed a little with DUSK_ROSE.
const PLANET_KEY_DIR := Vector3(0.9, -0.3, -0.3)
const PLANET_KEY_COLOR := Palette.PEARL
const PLANET_KEY_WARMTH := 0.18
## Planet rim: an ICE light of the worlds' own from behind and to the right of the hero camera (only
## PLANET_KEY_LAYER) — the atmosphere's lit ring on the far limb; it grows with the sky and peaks at
## the climax (GenesisChoreography light level "planet_rim").
const PLANET_RIM_DIR := Vector3(-0.75, -0.2, 0.62)
const PLANET_RIM_COLOR := Palette.ICE
## At the climax the planet glow scatters less in the haze (no milky bubble over the world).
const PLANET_FOG_CLIMAX := 0.3
const PLANET_FOG_CAP := 1.3
## Directional haze energy (<= GenesisEnvironment.DIRECTIONAL_FOG_ENERGY).
const DIRECTIONAL_FOG := 0.04
## Key shadow (the only caster): reach covers the hands and the planet from every hero shot; soft
## blur and normal bias keep the sculptures free of acne. MIKU casts no shadow (Miku: the key's
## self-shadow drew stair-stepped bands across her torso and gown — her baked AO and the SSAO shape
## her instead), so the key's shadows only seat the hands and the world in each other.
const KEY_SHADOW_MAX_DISTANCE := 60.0
const KEY_SHADOW_MAX_DISTANCE_2_SPLITS := 36.0
const KEY_SHADOW_BLUR := 2.2
const KEY_SHADOW_BLUR_2_SPLITS := 2.8
const KEY_SHADOW_NORMAL_BIAS := 2.0
const KEY_SHADOW_BIAS := 0.06

var environment: Environment

var back: DirectionalLight3D
var rim: DirectionalLight3D
var key: DirectionalLight3D
var fill: DirectionalLight3D
var planet_glow: OmniLight3D
var planet_key: DirectionalLight3D
var planet_rim: DirectionalLight3D

var _levels := {}
var _ambient_written := -1.0


func _ready() -> void:
	back = _directional("Back", BACK_COLOR, BACK_DIR)
	rim = _directional("Rim", RIM_COLOR, RIM_DIR)
	key = _directional("Key", KEY_COLOR, KEY_DIR)
	fill = _directional("Fill", FILL_COLOR, FILL_DIR)
	# The backlight faces the camera: its specular would paint a hot sheen over the front of the
	# stone and porcelain. Keep it low; the rim and sheen of the materials do the edge work.
	back.light_specular = 0.25
	fill.light_specular = 0.0
	# The key is the only shadow caster: in the haze its shadows draw dark shafts across the sky
	# (the hands and MIKU cut long black bands). It lights surfaces only; the haze gets the others.
	key.light_volumetric_fog_energy = 0.0
	planet_key = _directional("PlanetKey", PLANET_KEY_COLOR.lerp(Palette.DUSK_ROSE, PLANET_KEY_WARMTH), PLANET_KEY_DIR)
	planet_key.light_cull_mask = GenesisLayout.PLANET_KEY_LAYER
	planet_key.light_volumetric_fog_energy = 0.0
	planet_key.light_specular = 0.3
	planet_rim = _directional("PlanetRim", PLANET_RIM_COLOR, PLANET_RIM_DIR)
	planet_rim.light_cull_mask = GenesisLayout.PLANET_KEY_LAYER
	planet_rim.light_volumetric_fog_energy = 0.0
	planet_rim.light_specular = 1.0
	planet_glow = OmniLight3D.new()
	planet_glow.name = "PlanetGlow"
	planet_glow.position = GenesisLayout.PLANET_CENTER
	planet_glow.light_color = PLANET_COLOR
	planet_glow.omni_range = PLANET_RANGE
	planet_glow.omni_attenuation = PLANET_ATTENUATION
	planet_glow.light_specular = PLANET_SPECULAR
	planet_glow.light_volumetric_fog_energy = PLANET_FOG
	planet_glow.shadow_enabled = false
	planet_glow.light_energy = 0.0
	add_child(planet_glow)
	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)
	Simulation.world_rebuilt.connect(_on_world_rebuilt)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	GenesisChoreography.light_levels(g, t, _levels)
	var heat := GenesisChoreography.planet_heat(g, t)
	back.light_energy = _levels["back"]
	back.light_color = BACK_COLOR.lerp(Palette.GOLD, BACK_GOLD_SHARE * heat)
	rim.light_energy = _levels["rim"]
	key.light_energy = _levels["key"]
	fill.light_energy = _levels["fill"]
	var pe := float(_levels["planet"])
	planet_glow.light_energy = pe
	# At the climax the formed world lights the scene with its own sky (cool pearl), not with magma.
	var sky_share := GenesisChoreography.PLANET_LIGHT_CLIMAX * float(_levels["climax"]) / maxf(pe, 1e-3)
	planet_glow.light_color = PLANET_COLOR.lerp(PLANET_HOT_COLOR, 0.35 * heat).lerp(PLANET_SKY_COLOR.lerp(Palette.ICE, PLANET_SKY_ICE), clampf(sky_share, 0.0, 1.0))
	planet_glow.omni_range = PLANET_RANGE + PLANET_CLIMAX_REACH * float(_levels["climax"])
	# The haze around the world never turns milky: its scatter is capped to the molten glow's and
	# drops further at the climax (the world itself must read, not a fog bubble in front of it).
	planet_glow.light_volumetric_fog_energy = PLANET_FOG * minf(1.0, PLANET_FOG_CAP / maxf(pe, 1e-3)) \
		* lerpf(1.0, PLANET_FOG_CLIMAX, float(_levels["climax"]))
	planet_key.light_energy = _levels["planet_key"]
	planet_key.visible = planet_key.light_energy > 0.002
	planet_rim.light_energy = _levels["planet_rim"]
	planet_rim.visible = planet_rim.light_energy > 0.002
	planet_glow.visible = pe > 0.002
	if environment == null:
		return
	var amb := float(_levels["ambient"])
	if not is_equal_approx(amb, _ambient_written):
		_ambient_written = amb
		environment.ambient_light_energy = amb


## Levels last computed: back, rim, key, fill, ambient, planet (tests/debug).
func levels() -> Dictionary:
	return _levels


func _on_world_rebuilt() -> void:
	_ambient_written = -1.0
	_update()


func _directional(n: String, color: Color, dir: Vector3) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = n
	l.light_color = color
	l.light_energy = 0.0
	l.light_volumetric_fog_energy = DIRECTIONAL_FOG
	l.shadow_enabled = false
	l.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.BACK), Vector3.ZERO)
	add_child(l)
	return l


func _on_quality(profile: Dictionary) -> void:
	var splits := int(profile.get("shadow_splits", 4))
	key.shadow_enabled = bool(profile.get("shadows", true))
	key.directional_shadow_mode = LightRig.shadow_mode_for(splits)
	key.directional_shadow_max_distance = KEY_SHADOW_MAX_DISTANCE_2_SPLITS if splits == 2 else KEY_SHADOW_MAX_DISTANCE
	key.shadow_blur = KEY_SHADOW_BLUR_2_SPLITS if splits == 2 else KEY_SHADOW_BLUR
	key.shadow_normal_bias = KEY_SHADOW_NORMAL_BIAS
	key.shadow_bias = KEY_SHADOW_BIAS
	# Blend the cascades: a hard split boundary reads as a step across the stone.
	key.directional_shadow_blend_splits = true
