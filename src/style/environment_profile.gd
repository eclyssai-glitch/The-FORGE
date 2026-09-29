class_name EnvironmentProfile
extends RefCounted
## The single atmosphere of the KORIUM UNIVERSE: background, tonemapping, contained glow, depth
## fog, thin volumetric fog, SSAO — plus the light levels per story stage. Owner: art-director.
## Light tells the story: the chamber starts almost dark and rises with the events
## (dormant -> active -> lit -> verify -> final). Rationale: docs/VISUAL_DIRECTION.md.

## Light colours (derived from Palette). Key is warm-neutral, fill is cool and low, rim separates
## silhouettes from the void. The core light is the only EMBER source and only exists with energy.
const KEY_COLOR := Palette.BONE
const FILL_COLOR := Palette.ASH
const RIM_COLOR := Palette.ASH
const CORE_COLOR := Palette.EMBER
## Ambient is ASH (not SLATE): the walls facing the FORGE camera get almost no key, so the lit
## stages need a real ambient term to reveal them; at dormant energy it stays negligible.
const AMBIENT_COLOR := Palette.ASH
const FOG_COLOR := Palette.VOID
const VOLUMETRIC_ALBEDO := Palette.ASH

## Levels per stage, interpolated by LightRig.
## key/fill/rim = DirectionalLight3D.light_energy; core = OmniLight3D.light_energy at the core
## (EMBER); ambient = Environment.ambient_light_energy; exposure = Environment.tonemap_exposure;
## fog = Environment.volumetric_fog_density (depth fog compensates when volumetric is off).
const LIGHT := {
	"dormant": {"key": 0.0, "fill": 0.04, "rim": 0.45, "core": 0.0, "ambient": 0.05, "exposure": 0.9, "fog": 0.006},
	"active": {"key": 0.12, "fill": 0.06, "rim": 0.3, "core": 2.2, "ambient": 0.07, "exposure": 0.95, "fog": 0.012},
	"lit": {"key": 2.2, "fill": 0.9, "rim": 0.7, "core": 1.4, "ambient": 0.3, "exposure": 1.1, "fog": 0.014},
	"verify": {"key": 1.3, "fill": 0.6, "rim": 0.8, "core": 1.1, "ambient": 0.24, "exposure": 1.0, "fog": 0.014},
	"final": {"key": 2.0, "fill": 0.8, "rim": 0.95, "core": 1.8, "ambient": 0.32, "exposure": 1.05, "fog": 0.016},
}

## Light3D.light_volumetric_fog_energy per light (constant across stages). Directional lights
## fill the whole fog volume evenly — that is what makes fog "milky" — so they barely touch it;
## the fog takes its body from the core light, localised around the energy source.
const FOG_LIGHT := {"key": 0.08, "fill": 0.0, "rim": 0.0, "core": 1.0}

## Stage order (for LightRig and tests).
const STAGES: Array[String] = ["dormant", "active", "lit", "verify", "final"]

## UNIVERSE: the volumetric volume only fills the near air in front of the camera. Seen from
## ~80 units, a volume reaching the chamber absorbed most of its light (HIGH read far darker than
## LOW, which has no volumetric); ending the volume short keeps HIGH and LOW on the same key.
const UNIVERSE_VOLUMETRIC_LENGTH := 12.0

## Depth fog starts closer when volumetric fog is off (LOW): multiplier over fog_depth_begin.
const NO_VOLUMETRIC_FOG_BEGIN_SCALE := 0.7
const _META_FOG_BEGIN := &"korium_fog_begin"


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.VOID

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = LIGHT["dormant"]["ambient"]
	# Explicit: the finished metal reflects the universe sky's radiance (dim VOID with a faint band),
	# not a black BG colour — otherwise metal reads as holes in the lit phase.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = LIGHT["dormant"]["exposure"]

	# Contained glow: only true HDR emission (thin EMBER/PALE lines, the heart) blooms, softly.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.25
	env.glow_hdr_scale = 1.6
	env.glow_hdr_luminance_cap = 6.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.5)
	env.set_glow_level(3, 0.35)
	env.set_glow_level(4, 0.15)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)

	# Depth fog: distance sinks into near-black (fog colour ~ background), never into milky grey;
	# the far edge of any floor or pillar dissolves instead of cutting a horizon line.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_sky_affect = 1.0

	# Thin volumetric fog: gives the lights a body (shafts, core glow) without haze.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = LIGHT["dormant"]["fog"]
	env.volumetric_fog_albedo = VOLUMETRIC_ALBEDO
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_detail_spread = 2.0

	# SSAO: grounds the segments in their rings and the pillars on the floor.
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.05

	env.ssil_enabled = false
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.6

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	env.adjustment_brightness = 1.0

	apply_mode_fog(env, SessionState.Mode.FORGE)
	return env


## Switches the costly effects per quality profile (keys from QualityProfiles.get_profile).
## With volumetric fog off, depth fog is thickened to keep the sense of depth.
static func apply_quality(env: Environment, profile: Dictionary) -> void:
	env.ssao_enabled = bool(profile.get("ssao", true))
	env.ssil_enabled = bool(profile.get("ssil", false))
	env.glow_enabled = bool(profile.get("glow", true))
	env.volumetric_fog_enabled = bool(profile.get("volumetric_fog", true))
	_update_depth_fog(env)


## Fog/depth settings per Session mode. Keys are Environment property names (depth fog:
## fog_density is the maximum opacity reached at fog_depth_end), plus "exposure_scale", which is
## not an Environment property: LightRig multiplies the stage exposure by it (default 1.0).
## FORGE: close chamber air. UNIVERSE: sees far (seeds beyond the chamber, 60–70 units, stay
## legible) and is slightly brighter. OBSERVATORY: the world recedes slightly behind the left panel.
static func mode_fog(mode: int) -> Dictionary:
	match mode:
		SessionState.Mode.UNIVERSE:
			return {"fog_density": 1.0, "fog_depth_begin": 45.0, "fog_depth_end": 220.0, "fog_depth_curve": 1.3, "volumetric_fog_length": UNIVERSE_VOLUMETRIC_LENGTH, "exposure_scale": 1.5}
		SessionState.Mode.OBSERVATORY:
			return {"fog_density": 1.0, "fog_depth_begin": 9.0, "fog_depth_end": 30.0, "fog_depth_curve": 1.2, "volumetric_fog_length": 40.0, "exposure_scale": 1.0}
		_:
			return {"fog_density": 1.0, "fog_depth_begin": 11.0, "fog_depth_end": 34.0, "fog_depth_curve": 1.4, "volumetric_fog_length": 40.0, "exposure_scale": 1.0}


## Applies mode_fog(mode) to env, keeping the quality compensation of the depth fog. Keys that
## are not Environment properties (exposure_scale) are skipped; LightRig consumes them.
static func apply_mode_fog(env: Environment, mode: int) -> void:
	var f := mode_fog(mode)
	for key: String in f:
		if key in env:
			env.set(key, f[key])
	env.set_meta(_META_FOG_BEGIN, float(f["fog_depth_begin"]))
	_update_depth_fog(env)


static func _update_depth_fog(env: Environment) -> void:
	if not env.has_meta(_META_FOG_BEGIN):
		env.set_meta(_META_FOG_BEGIN, env.fog_depth_begin)
	var base := float(env.get_meta(_META_FOG_BEGIN))
	env.fog_depth_begin = base if env.volumetric_fog_enabled else base * NO_VOLUMETRIC_FOG_BEGIN_SCALE
