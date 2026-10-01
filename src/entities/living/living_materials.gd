class_name LivingMaterials
extends RefCounted
## Materials of the living prototype (Loop 5). Owner of this file: animator; owner of the looks:
## art-director. Every lookup first asks MaterialLibrary for the art-director's material (by the
## names in CANDIDATES — the first static function that exists wins) and only when none exists
## builds a plain placeholder here (StandardMaterial3D, colours from Palette), so the prototype
## runs before and after the art lands. Placeholders are cached; callers that animate uniforms
## duplicate them.
##
## Uniform contract with the art-director (set by the animator every frame they change):
##   thread:   tension 0..1, presence 0..1
##   hand:     presence 0..1 (summoned -> solid), effort 0..1 (pulled by a thread)
##   world:    build 0..1 (stage progress), crack 0..1 (failure), energy 0..1 (being worked)
##   artifact: presence 0..1, edit 0..1 (glyphs being rewritten), valid 0..1 (validation)
##   body:     glow 0..1 (appearance.glow)
## For placeholders the same values drive albedo alpha / emission (apply_*).

const CANDIDATES := {
	&"hand": [&"living_hand", &"angel_hand", &"puppet_hand"],
	&"thread": [&"intent_thread", &"living_thread"],
	&"world": [&"work_world", &"living_world"],
	&"artifact": [&"config_artifact", &"file_artifact"],
	&"body": [&"living_body", &"miku_mannequin"],
	&"halo": [&"living_halo", &"halo_arc"],
	&"mote": [&"living_mote"],
}

static var _cache: Dictionary = {}


## Material for `kind` (&"hand", &"thread", &"world", &"artifact", &"body", &"halo", &"mote").
static func get_material(kind: StringName) -> Material:
	var from_art := _from_library(kind)
	if from_art != null:
		return from_art
	if not _cache.has(kind):
		_cache[kind] = _placeholder(kind)
	return _cache[kind]


## True when the art-director's material exists for `kind`.
static func has_art(kind: StringName) -> bool:
	return _from_library(kind) != null


## Sets a uniform on a ShaderMaterial (only if it declares it) or maps the known ones of a
## placeholder onto its StandardMaterial3D.
static func set_param(m: Material, uniform: StringName, value: float) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter(uniform, value)
		return
	var sm := m as StandardMaterial3D
	if sm == null:
		return
	match uniform:
		&"presence":
			sm.albedo_color.a = clampf(value, 0.0, 1.0) * float(sm.get_meta(&"alpha", 1.0))
			sm.emission_energy_multiplier = float(sm.get_meta(&"emission", 1.0)) * clampf(value, 0.0, 1.0) \
				* (1.0 + float(sm.get_meta(&"tension", 0.0)) * 2.0)
			sm.set_meta(&"presence", value)
		&"tension", &"effort", &"energy", &"edit", &"glow":
			sm.set_meta(&"tension", value)
			sm.emission_energy_multiplier = float(sm.get_meta(&"emission", 1.0)) \
				* float(sm.get_meta(&"presence", 1.0)) * (1.0 + value * 2.0)
		&"crack":
			sm.emission = Palette.PEARL.lerp(Palette.MAGMA, clampf(value, 0.0, 1.0)) \
				if sm.get_meta(&"crackable", false) else sm.emission
		&"valid":
			sm.emission = Palette.PEARL.lerp(Palette.GOLD, clampf(value, 0.0, 1.0))


static func _from_library(kind: StringName) -> Material:
	var lib := MaterialLibrary as Script
	if lib == null:
		return null
	var names: Array = CANDIDATES.get(kind, [])
	for n: StringName in names:
		for m in lib.get_script_method_list():
			if StringName(m["name"]) == n and (m["args"] as Array).is_empty():
				var mat: Variant = lib.call(n)
				if mat is Material:
					return mat
	return null


static func _placeholder(kind: StringName) -> Material:
	var m := StandardMaterial3D.new()
	m.resource_name = "living_placeholder_%s" % kind
	match kind:
		&"hand":
			m.albedo_color = Palette.PEARL
			m.roughness = 0.42
			m.rim_enabled = true
			m.rim = 0.6
			m.rim_tint = 0.4
			m.emission_enabled = true
			m.emission = Palette.BLUSH
			m.emission_energy_multiplier = 0.06
			m.set_meta(&"emission", 0.06)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		&"thread":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(Palette.PEARL, 0.9)
			m.emission_enabled = true
			m.emission = Palette.GOLD
			m.emission_energy_multiplier = 1.4
			m.set_meta(&"emission", 1.4)
			m.set_meta(&"alpha", 0.9)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		&"world":
			m.albedo_color = Color("#3b3550")
			m.roughness = 0.75
			m.metallic = 0.0
			m.emission_enabled = true
			m.emission = Palette.PEARL
			m.emission_energy_multiplier = 0.05
			m.set_meta(&"emission", 0.05)
			m.set_meta(&"crackable", true)
		&"artifact":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(Palette.PEARL, 0.55)
			m.emission_enabled = true
			m.emission = Palette.PEARL
			m.emission_energy_multiplier = 0.9
			m.set_meta(&"emission", 0.9)
			m.set_meta(&"alpha", 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		&"body":
			m.albedo_color = Palette.PEARL.darkened(0.04)
			m.roughness = 0.5
			m.rim_enabled = true
			m.rim = 0.5
			m.rim_tint = 0.5
			m.emission_enabled = true
			m.emission = Palette.BLUSH
			m.emission_energy_multiplier = 0.05
			m.set_meta(&"emission", 0.05)
		&"halo":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(Palette.GOLD, 0.7)
			m.emission_enabled = true
			m.emission = Palette.GOLD
			m.emission_energy_multiplier = 1.2
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(Palette.PEARL, 0.8)
			m.vertex_color_use_as_albedo = true
			m.emission_enabled = true
			m.emission = Palette.GOLD
			m.emission_energy_multiplier = 2.0
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m
