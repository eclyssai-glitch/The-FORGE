class_name GenesisEnvironment
extends RefCounted
## Atmosphere of the GENESIS scenario (Loop 4, v2 look; docs/VISUAL_DIRECTION.md §4, §5, §11):
## deep-nebula sky (a world-owned duplicate of MaterialLibrary.nebula_sky()), AgX, contained
## glow (only true HDR emission blooms), a thin depth fog that sinks distant bodies into the
## nebula (aerial perspective), a light volumetric haze that gives the backlight a body (off in
## LOW; the depth fog then starts closer) and a minimal INDIGO/NEBULA ambient — the light comes
## from the GENESIS light rig (animator), not from the environment.
## Pure configuration (no nodes, no clock): the world (src/world/world.gd) builds it, applies
## quality/mode on Quality.profile_changed / Session.mode_changed and steps the sky's
## `motion_time` at most SKY_MOTION_HZ times per second (the radiance cubemap is re-rendered on
## every uniform change). Colours come only from Palette.
## Ownership: exposure, fog and sky energy per mode are written here only. A GENESIS light rig
## that receives `environment` may modulate `ambient_light_energy` and nothing else.
## No pops (Loop 4 r1): the world blends every per-mode setting over MODE_BLEND seconds (eased,
## real time, like the camera's own mode transition) — blend_settings/blend_weight — and applies
## an optional exposure trim asked by the camera (World.set_exposure_trim, clamped to TRIM_RANGE,
## eased by smooth_toward with TRIM_TAU): exposure = mode exposure x trim, never a jump.
## Volumetric haze: directional lights fill the whole froxel volume evenly and turn it milky
## (verified with stand-in bodies: the night stone reads brown-grey). Rig directionals must use
## `light_volumetric_fog_energy` ≤ DIRECTIONAL_FOG_ENERGY; local lights (the planet's GOLD glow)
## give the haze its body.

## Sky `motion_time` updates per second (≤ 5 Hz, bible §11). LOW keeps the sky static.
const SKY_MOTION_HZ := 4.0

const AMBIENT_COLOR := Palette.NEBULA
const AMBIENT_ENERGY := 0.3
const FOG_COLOR := Palette.SPACE_DEEP
const VOLUMETRIC_ALBEDO := Palette.PEARL
const VOLUMETRIC_DENSITY := 0.006
## Maximum Light3D.light_volumetric_fog_energy for the GENESIS rig's directional lights.
const DIRECTIONAL_FOG_ENERGY := 0.05
## Radiance cubemap size per quality level (QualityProfiles.Level LOW..ULTRA).
const RADIANCE_SIZE: Array[int] = [Sky.RADIANCE_SIZE_32, Sky.RADIANCE_SIZE_64, Sky.RADIANCE_SIZE_64, Sky.RADIANCE_SIZE_128]
## Depth fog starts this much closer when volumetric fog is off (LOW).
const NO_VOLUMETRIC_FOG_BEGIN_SCALE := 0.75

## Per-mode settings. Environment keys are applied as properties; `sky_energy`,
## `star_intensity` and `nebula_intensity` are uniforms of the sky material.
## FORGE (hero): close, full nebula behind MIKU. UNIVERSE (system): sees the whole system
## (belt 16–19, far planet at 24) and the stars. OBSERVATORY (relational): the nebula recedes so
## the threads read (bible §5).
const MODES := {
	SessionState.Mode.FORGE: {
		"tonemap_exposure": 1.0, "fog_depth_begin": 26.0, "fog_depth_end": 90.0, "fog_density": 0.55,
		"volumetric_fog_length": 48.0, "sky_energy": 1.0, "star_intensity": 0.85, "nebula_intensity": 1.0,
	},
	SessionState.Mode.UNIVERSE: {
		"tonemap_exposure": 1.05, "fog_depth_begin": 60.0, "fog_depth_end": 180.0, "fog_density": 0.45,
		"volumetric_fog_length": 24.0, "sky_energy": 1.0, "star_intensity": 1.0, "nebula_intensity": 0.9,
	},
	SessionState.Mode.OBSERVATORY: {
		"tonemap_exposure": 1.0, "fog_depth_begin": 22.0, "fog_depth_end": 80.0, "fog_density": 0.6,
		"volumetric_fog_length": 40.0, "sky_energy": 0.8, "star_intensity": 0.75, "nebula_intensity": 0.8,
	},
}
const SKY_UNIFORMS: Array[String] = ["sky_energy", "star_intensity", "nebula_intensity"]
## Seconds of the blend between two modes' settings: the camera's mode transition.
const MODE_BLEND := GenesisShots.T_USER
## Exposure trim limits (x the mode exposure) and its smoothing time constant (seconds).
const TRIM_RANGE := Vector2(0.75, 1.35)
const TRIM_TAU := 0.9
const _META_FOG_BEGIN := &"korium_genesis_fog_begin"


## The world's own copy of the GENESIS sky (MaterialLibrary.set_motion_time never touches it:
## the world steps its `motion_time` itself, see sky_motion_step).
static func make_sky_material() -> ShaderMaterial:
	return MaterialLibrary.nebula_sky().duplicate() as ShaderMaterial


static func make_environment(sky_material: ShaderMaterial) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = RADIANCE_SIZE[2]
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	# Clearcoat stone and porcelain reflect the nebula's colour (radiance pass: no stars).
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0

	# Contained glow: a soft, wide halo only around true HDR emission (seed, kintsugi, magma,
	# pulses); nothing below 1.0 blooms, and the cap keeps the core of a spark from exploding.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 1.8
	env.glow_hdr_luminance_cap = 8.0
	var levels: Array[float] = [0.0, 0.35, 0.6, 0.55, 0.35, 0.15, 0.0]
	for i in levels.size():
		env.set_glow_level(i, levels[i])

	# Depth fog: distance sinks into the nebula (aerial perspective), never into grey.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.6

	# Light volumetric haze: forward scattering makes the backlight glow around the silhouettes.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = VOLUMETRIC_DENSITY
	env.volumetric_fog_albedo = VOLUMETRIC_ALBEDO
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_detail_spread = 2.0

	# Gentle SSAO: the sculptures carry baked AO; this only seats hands and planet in each other.
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.2
	env.ssao_power = 1.3
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.0
	env.ssil_enabled = false
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.5

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.0
	env.adjustment_brightness = 1.0

	apply_mode(env, sky_material, SessionState.Mode.FORGE)
	return env


## Costly effects per quality profile (keys of QualityProfiles.get_profile), sky noise octaves
## (MaterialLibrary.SKY_DETAIL) and radiance size.
static func apply_quality(env: Environment, sky_material: ShaderMaterial, profile: Dictionary) -> void:
	var level := clampi(int(profile.get("level", QualityProfiles.Level.HIGH)), 0, RADIANCE_SIZE.size() - 1)
	env.ssao_enabled = bool(profile.get("ssao", true))
	env.ssil_enabled = bool(profile.get("ssil", false))
	env.glow_enabled = bool(profile.get("glow", true))
	env.volumetric_fog_enabled = bool(profile.get("volumetric_fog", true))
	if env.sky:
		env.sky.radiance_size = RADIANCE_SIZE[level]
	if sky_material:
		sky_material.set_shader_parameter("detail", MaterialLibrary.SKY_DETAIL[level])
	_update_depth_fog(env)


## Settings of a mode (FORGE for an unknown mode).
static func mode_settings(mode: int) -> Dictionary:
	return MODES.get(mode, MODES[SessionState.Mode.FORGE])


## Applies a mode's settings at once (composition, snaps). The world blends mode changes.
static func apply_mode(env: Environment, sky_material: ShaderMaterial, mode: int) -> void:
	apply_settings(env, sky_material, mode_settings(mode))


## Applies per-mode settings `s` (MODES layout, possibly blended); `tonemap_exposure` is
## multiplied by `trim` (clamped to TRIM_RANGE).
static func apply_settings(env: Environment, sky_material: ShaderMaterial, s: Dictionary, trim: float = 1.0) -> void:
	for key: String in s:
		if SKY_UNIFORMS.has(key):
			if sky_material:
				sky_material.set_shader_parameter(key, s[key])
		elif key == "tonemap_exposure":
			env.tonemap_exposure = float(s[key]) * clamp_trim(trim)
		elif key in env:
			env.set(key, s[key])
	env.set_meta(_META_FOG_BEGIN, float(s["fog_depth_begin"]))
	_update_depth_fog(env)


## Settings between `a` (k = 0) and `b` (k = 1), key by key (numbers lerp; others switch at 0.5).
static func blend_settings(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	var w := clampf(k, 0.0, 1.0)
	for key: String in b:
		if not a.has(key):
			out[key] = b[key]
		elif typeof(a[key]) in [TYPE_FLOAT, TYPE_INT] and typeof(b[key]) in [TYPE_FLOAT, TYPE_INT]:
			out[key] = lerpf(float(a[key]), float(b[key]), w)
		else:
			out[key] = b[key] if w >= 0.5 else a[key]
	return out


## Eased weight (smoothstep: zero slope at both ends) of a blend at progress u in 0..1.
static func blend_weight(u: float) -> float:
	return smoothstep(0.0, 1.0, u)


static func clamp_trim(trim: float) -> float:
	return clampf(trim, TRIM_RANGE.x, TRIM_RANGE.y)


## One frame of the exposure trim easing towards `target` (exponential, time constant `tau`);
## lands exactly on the target once within 1e-4.
static func smooth_toward(current: float, target: float, delta: float, tau: float = TRIM_TAU) -> float:
	if tau <= 0.0:
		return target
	if delta <= 0.0:
		return current
	var v := lerpf(current, target, 1.0 - exp(-delta / tau))
	return target if absf(v - target) < 1e-4 else v


## True when the sky's `motion_time` should move under this profile (static in LOW).
static func sky_motion_enabled(profile: Dictionary) -> bool:
	return int(profile.get("level", QualityProfiles.Level.HIGH)) > QualityProfiles.Level.LOW


## Motion time quantised to SKY_MOTION_HZ steps: the value only changes `hz` times per second,
## so writing it when it changes re-renders the sky radiance at most that often.
static func sky_motion_step(t: float, hz: float = SKY_MOTION_HZ) -> float:
	if hz <= 0.0:
		return 0.0
	return floorf(t * hz) / hz


static func _update_depth_fog(env: Environment) -> void:
	if not env.has_meta(_META_FOG_BEGIN):
		env.set_meta(_META_FOG_BEGIN, env.fog_depth_begin)
	var base := float(env.get_meta(_META_FOG_BEGIN))
	env.fog_depth_begin = base if env.volumetric_fog_enabled else base * NO_VOLUMETRIC_FOG_BEGIN_SCALE
