extends GutTest
## GENESIS materials (Loop 4): every getter loads its shader, is cached, exposes the contract
## uniforms, gets its colours from Palette, and no v2 shader reads TIME (motion_time instead).

const CONTRACT_UNIFORMS := {
	&"miku_body": ["awaken", "breath", "select", "ao_strength"],
	&"miku_hair": ["reveal", "motion_time"],
	&"miku_gown": ["fade_top", "fade_bottom", "presence", "motion_time"],
	&"halo_arc": ["strength", "breath"],
	&"hand_stone": ["veins", "motion_time", "select", "ao_strength"],
	&"planet_forming": ["heat", "crust", "atmosphere", "formation", "motion_time", "detail"],
	&"moon_doc": ["formation", "glow"],
	&"ring_skill": ["formation"],
	&"asteroid_memory": ["memory"],
	&"orbit_line": ["head", "formation"],
	&"relation_thread": ["pulse", "woven"],
	&"nebula_sky": ["warm_dir", "motion_time", "detail"],
}


func before_each() -> void:
	MaterialLibrary.clear_cache()


func _uniform_names(sh: Shader) -> Array[String]:
	var names: Array[String] = []
	for u: Dictionary in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	return names


func test_every_getter_loads_and_caches() -> void:
	for n: StringName in MaterialLibrary.GENESIS_MATERIALS:
		var m: ShaderMaterial = MaterialLibrary.genesis(n)
		assert_not_null(m, String(n))
		assert_not_null(m.shader, "%s shader" % n)
		assert_same(m, MaterialLibrary.genesis(n), "%s cached" % n)
	assert_eq(MaterialLibrary.GENESIS_MATERIALS.size(), CONTRACT_UNIFORMS.size())
	assert_null(MaterialLibrary.genesis(&"nope"))
	assert_same(MaterialLibrary.genesis(&"hand_stone"), MaterialLibrary.hand_stone())


func test_shader_modes() -> void:
	assert_eq(MaterialLibrary.nebula_sky().shader.get_mode(), Shader.MODE_SKY)
	for n: StringName in MaterialLibrary.GENESIS_MATERIALS:
		if n != &"nebula_sky":
			assert_eq((MaterialLibrary.genesis(n) as ShaderMaterial).shader.get_mode(), Shader.MODE_SPATIAL, String(n))


func test_contract_uniforms_exist() -> void:
	for n: StringName in CONTRACT_UNIFORMS:
		var names := _uniform_names((MaterialLibrary.genesis(n) as ShaderMaterial).shader)
		assert_gt(names.size(), 0, "%s parsed" % n)
		for u: String in CONTRACT_UNIFORMS[n]:
			assert_has(names, u, "%s.%s" % [n, u])


func test_colours_are_injected_from_palette() -> void:
	# Every colour uniform is set by the library (no default/literal colours left in the shaders).
	for n: StringName in MaterialLibrary.GENESIS_MATERIALS:
		var m: ShaderMaterial = MaterialLibrary.genesis(n)
		for u_name in _uniform_names(m.shader):
			if u_name == "color" or u_name.ends_with("_color"):
				var v: Variant = m.get_shader_parameter(u_name)
				assert_true(v is Color, "%s.%s injected from Palette" % [n, u_name])


func test_no_time_builtin_in_v2_shaders() -> void:
	var dir := MaterialLibrary.SHADER_DIR + MaterialLibrary.GENESIS_DIR
	var files := DirAccess.get_files_at(dir)
	assert_gt(files.size(), 0)
	var re := RegEx.create_from_string("\\bTIME\\b")
	for f in files:
		if not (f.ends_with(".gdshader") or f.ends_with(".gdshaderinc")):
			continue
		var src := FileAccess.get_file_as_string(dir + f)
		# Comments may mention TIME; code may not.
		var code := ""
		for line in src.split("\n"):
			code += line.split("//")[0] + "\n"
		assert_null(re.search(code), "%s uses TIME" % f)


func test_motion_time_broadcast() -> void:
	MaterialLibrary.set_motion_time(12.5)
	for n: StringName in [&"miku_hair", &"miku_gown", &"hand_stone", &"planet_forming", &"nebula_sky"]:
		assert_almost_eq(float((MaterialLibrary.genesis(n) as ShaderMaterial).get_shader_parameter("motion_time")), 12.5, 1e-5, String(n))


func test_quality_sets_noise_detail() -> void:
	MaterialLibrary.apply_quality(QualityProfiles.get_profile(QualityProfiles.Level.LOW))
	assert_eq(int(MaterialLibrary.nebula_sky().get_shader_parameter("detail")), MaterialLibrary.SKY_DETAIL[0])
	assert_eq(int(MaterialLibrary.planet_forming().get_shader_parameter("detail")), MaterialLibrary.PLANET_DETAIL[0])
	MaterialLibrary.apply_quality(QualityProfiles.get_profile(QualityProfiles.Level.HIGH))
	assert_eq(int(MaterialLibrary.nebula_sky().get_shader_parameter("detail")), MaterialLibrary.SKY_DETAIL[2])
