class_name MaterialLibrary
extends RefCounted
## Shared surface materials of the KORIUM UNIVERSE. Owner: art-director.
## Every getter returns the same cached instance on each call, so a uniform set by one entity
## (e.g. `finish` on structure()) is seen by every user of that material. Entities that need an
## independent copy (e.g. several halos with different strength) call `.duplicate()` on it.
## All colours come from Palette; no textures. Rules and rationale: docs/VISUAL_DIRECTION.md.

const SHADER_DIR := "res://src/style/shaders/"

static var _cache: Dictionary = {}


## Structure segments (FragmentStructure MultiMesh with use_custom_data = true).
## INSTANCE_CUSTOM: r = assembly, g = verify flash, b = selection/hover, a = build energy.
## Uniforms: finish, scan_y, scan_strength, final_lock, energy (all floats, see shader header).
static func structure() -> ShaderMaterial:
	if not _cache.has(&"structure"):
		var m := _shader_material("structure")
		m.set_shader_parameter("raw_color", Palette.ASH.lerp(Palette.BONE, 0.55))
		m.set_shader_parameter("finished_color", Palette.SLATE.lerp(Palette.ASH, 0.65))
		m.set_shader_parameter("edge_color", Palette.BONE)
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("pale_color", Palette.PALE)
		m.set_shader_parameter("select_color", Palette.BONE)
		m.set_shader_parameter("finish", 0.0)
		m.set_shader_parameter("scan_y", -100.0)
		m.set_shader_parameter("scan_strength", 0.0)
		m.set_shader_parameter("final_lock", 0.0)
		m.set_shader_parameter("energy", 1.0)
		_cache[&"structure"] = m
	return _cache[&"structure"]


## Faceted dark shell of the origin core; uniform `energy` 0..1 (0 = dormant, no EMBER).
static func core_shell() -> ShaderMaterial:
	if not _cache.has(&"core_shell"):
		var m := _shader_material("core_shell")
		m.set_shader_parameter("shell_color", Palette.GRAPHITE)
		m.set_shader_parameter("rim_color", Palette.BONE)
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("energy", 0.0)
		_cache[&"core_shell"] = m
	return _cache[&"core_shell"]


## Emissive EMBER heart of the core; uniforms `energy` 0..1 and `pulse` 0..1.
static func core_heart() -> ShaderMaterial:
	if not _cache.has(&"core_heart"):
		var m := _shader_material("core_heart")
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("ember_deep_color", Palette.EMBER_DEEP)
		m.set_shader_parameter("energy", 0.0)
		m.set_shader_parameter("pulse", 0.0)
		_cache[&"core_heart"] = m
	return _cache[&"core_heart"]


## Verification sweep ring: PALE, additive; uniform `strength` 0..1.
static func scan_ring() -> ShaderMaterial:
	if not _cache.has(&"scan_ring"):
		var m := _shader_material("emissive_band")
		m.set_shader_parameter("color", Palette.PALE)
		m.set_shader_parameter("strength", 0.0)
		m.set_shader_parameter("intensity", 1.0)
		m.set_shader_parameter("softness", 0.85)
		_cache[&"scan_ring"] = m
	return _cache[&"scan_ring"]


## Subtle emissive halo ring; uniforms `color` (a Palette colour) and `strength` 0..1.
## Default colour BONE; set EMBER only for halos that mark energy (activation, final form).
static func halo() -> ShaderMaterial:
	if not _cache.has(&"halo"):
		var m := _shader_material("emissive_band")
		m.set_shader_parameter("color", Palette.BONE)
		m.set_shader_parameter("strength", 0.0)
		m.set_shader_parameter("intensity", 0.6)
		m.set_shader_parameter("softness", 0.9)
		_cache[&"halo"] = m
	return _cache[&"halo"]


## Chamber floor: almost black, rough, with a faint glossy reflection of the lit structure.
## (Named floor_material in GDScript would be clearer, but the contract name is kept.)
static func floor() -> StandardMaterial3D:
	if not _cache.has(&"floor"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Palette.ABYSS
		m.metallic = 0.0
		m.metallic_specular = 0.18
		m.roughness = 0.55
		_cache[&"floor"] = m
	return _cache[&"floor"]


## Pillars, columns and the oculus frame: dark architectural stone-metal, never shinier than
## the structure so the eye stays on the core.
static func architecture() -> StandardMaterial3D:
	if not _cache.has(&"architecture"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Palette.GRAPHITE
		m.metallic = 0.25
		m.metallic_specular = 0.4
		m.roughness = 0.72
		_cache[&"architecture"] = m
	return _cache[&"architecture"]


## Dormant seed of a future construct (UNIVERSE); uniform `energy` 0..1 (0 = cold, no EMBER).
static func dormant_seed() -> ShaderMaterial:
	if not _cache.has(&"dormant_seed"):
		var m := _shader_material("dormant_seed")
		m.set_shader_parameter("body_color", Palette.ABYSS)
		m.set_shader_parameter("cold_color", Palette.ASH)
		m.set_shader_parameter("ember_color", Palette.EMBER)
		m.set_shader_parameter("energy", 0.0)
		_cache[&"dormant_seed"] = m
	return _cache[&"dormant_seed"]


## Mote material for billboarded particles (GPUParticles3D draw pass on a QuadMesh): unshaded,
## additive, round soft disc (shaders/particle_mote.gdshader), alpha from the particle colour
## ramp (vertex colour). Uniform `near_fade` (Vector2, view metres: hidden -> visible), default
## (3.5, 8.0). `color` must be a Palette colour; cached per colour — duplicate() to tune near_fade.
static func mote(color: Color) -> ShaderMaterial:
	var key := StringName("mote_" + color.to_html(true))
	if not _cache.has(key):
		var m := _shader_material("particle_mote")
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("near_fade", Vector2(3.5, 8.0))
		_cache[key] = m
	return _cache[key]


## Solid emissive shard (non-billboard meshes such as the emission sparks): unshaded, additive,
## double-sided, colour from the material only. `color` must be a Palette colour; cached per colour.
static func spark(color: Color) -> StandardMaterial3D:
	var key := StringName("spark_" + color.to_html(true))
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = color
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.disable_receive_shadows = true
		_cache[key] = m
	return _cache[key]


## Drops every cached material (tests / hot reload). Existing users keep their instances.
static func clear_cache() -> void:
	_cache.clear()


static func _shader_material(shader_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + shader_name + ".gdshader") as Shader
	return m
