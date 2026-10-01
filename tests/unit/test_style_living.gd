extends GutTest
## LIVING materials (Loop 5, MIKU LIVING CHARACTER prototype): every getter loads its shader, is
## cached, exposes the contract uniforms the animator drives, gets its colours from Palette, never
## reads TIME, and the intent thread's reference strip encoder follows the mesh contract.
## (NaN safety of the shaders is covered by test_style_shader_safety, which walks every subfolder.)

const CONTRACT_UNIFORMS := {
	&"angelic_hand": ["drive", "presence", "select", "motion_time", "hand_size", "flow_axis",
		"presence_origin", "presence_reach", "wrist_point", "forearm_end", "wrist_fade", "ao_strength"],
	&"intent_thread": ["tension", "presence", "release", "anger", "motion_time", "seed", "intensity",
		"width_px", "glow_px", "vibration_px", "ribbon_px"],
	&"config_artifact": ["presence", "edit", "validated", "edit_row", "aspect", "rows", "seed",
		"motion_time", "intensity"],
	&"work_world": ["formation", "stress", "compression", "heal", "build_axis", "press_dir", "seed",
		"detail", "motion_time", "select"],
}


func before_each() -> void:
	MaterialLibrary.clear_cache()


func _uniform_names(sh: Shader) -> Array[String]:
	var names: Array[String] = []
	for u: Dictionary in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	return names


func _code_without_comments(src: String) -> String:
	var code := ""
	for line in src.split("\n"):
		code += line.split("//")[0] + "\n"
	return code


func test_every_getter_loads_and_caches() -> void:
	assert_eq(MaterialLibrary.LIVING_MATERIALS.size(), CONTRACT_UNIFORMS.size())
	for n: StringName in MaterialLibrary.LIVING_MATERIALS:
		var m: ShaderMaterial = MaterialLibrary.living(n)
		assert_not_null(m, String(n))
		assert_not_null(m.shader, "%s shader" % n)
		assert_eq(m.shader.get_mode(), Shader.MODE_SPATIAL, String(n))
		assert_same(m, MaterialLibrary.living(n), "%s cached" % n)
	assert_null(MaterialLibrary.living(&"nope"))
	assert_same(MaterialLibrary.living(&"angelic_hand"), MaterialLibrary.angelic_hand())
	assert_same(MaterialLibrary.living(&"intent_thread"), MaterialLibrary.intent_thread())
	assert_same(MaterialLibrary.living(&"config_artifact"), MaterialLibrary.config_artifact())
	assert_same(MaterialLibrary.living(&"work_world"), MaterialLibrary.work_world())


func test_contract_uniforms_exist() -> void:
	for n: StringName in CONTRACT_UNIFORMS:
		var names := _uniform_names(MaterialLibrary.living(n).shader)
		assert_gt(names.size(), 0, "%s parsed" % n)
		for u: String in CONTRACT_UNIFORMS[n]:
			assert_has(names, u, "%s.%s" % [n, u])


func test_resting_defaults() -> void:
	# A fresh instance is a usable resting state: present, relaxed, unedited, whole and sound.
	var hand := MaterialLibrary.angelic_hand()
	assert_eq(hand.get_shader_parameter("drive"), 0.0)
	assert_eq(hand.get_shader_parameter("presence"), 1.0)
	var thread := MaterialLibrary.intent_thread()
	for u: String in ["tension", "release", "anger"]:
		assert_eq(thread.get_shader_parameter(u), 0.0, "thread.%s" % u)
	assert_eq(thread.get_shader_parameter("presence"), 1.0)
	var art := MaterialLibrary.config_artifact()
	assert_eq(art.get_shader_parameter("edit"), 0.0)
	assert_eq(art.get_shader_parameter("validated"), 0.0)
	assert_eq(art.get_shader_parameter("presence"), 1.0)
	var world := MaterialLibrary.work_world()
	assert_eq(world.get_shader_parameter("formation"), 1.0)
	for u: String in ["stress", "compression", "heal"]:
		assert_eq(world.get_shader_parameter(u), 0.0, "world.%s" % u)


func test_colours_are_injected_from_palette() -> void:
	for n: StringName in MaterialLibrary.LIVING_MATERIALS:
		var m: ShaderMaterial = MaterialLibrary.living(n)
		for u_name in _uniform_names(m.shader):
			if u_name == "color" or u_name.ends_with("_color"):
				assert_true(m.get_shader_parameter(u_name) is Color, "%s.%s injected from Palette" % [n, u_name])


func test_no_neon_and_one_family() -> void:
	# Low saturation like the v2 palette; the thread leaves MIKU with the hair's link-tip colour;
	# anger is colder (bluer) and whiter than the taut thread, never warmer.
	for n: StringName in MaterialLibrary.LIVING_MATERIALS:
		var m: ShaderMaterial = MaterialLibrary.living(n)
		for u_name in _uniform_names(m.shader):
			var v: Variant = m.get_shader_parameter(u_name)
			if v is Color:
				assert_lte((v as Color).s, 0.6, "%s.%s saturation" % [n, u_name])
	var thread := MaterialLibrary.intent_thread()
	assert_eq(thread.get_shader_parameter("origin_color"), MaterialLibrary.hair_link_tip())
	var taut: Color = thread.get_shader_parameter("taut_color")
	var angry: Color = thread.get_shader_parameter("anger_color")
	assert_gt(angry.b - angry.r, taut.b - taut.r, "anger is colder")
	assert_gt(angry.v, 0.85, "anger is white light")


func test_no_time_builtin() -> void:
	var dir := MaterialLibrary.SHADER_DIR + MaterialLibrary.LIVING_DIR
	var files := DirAccess.get_files_at(dir)
	var re := RegEx.create_from_string("\\bTIME\\b")
	var count := 0
	for f in files:
		if not f.ends_with(".gdshader"):
			continue
		count += 1
		assert_null(re.search(_code_without_comments(FileAccess.get_file_as_string(dir + f))), "%s uses TIME" % f)
	assert_eq(count, MaterialLibrary.LIVING_MATERIALS.size())


func test_motion_time_and_quality_reach_living_materials() -> void:
	MaterialLibrary.set_motion_time(7.25)
	for n: StringName in MaterialLibrary.LIVING_MATERIALS:
		assert_almost_eq(float(MaterialLibrary.living(n).get_shader_parameter("motion_time")), 7.25, 1e-5, String(n))
	MaterialLibrary.apply_quality(QualityProfiles.get_profile(QualityProfiles.Level.LOW))
	assert_eq(int(MaterialLibrary.work_world().get_shader_parameter("detail")), MaterialLibrary.PLANET_DETAIL[0])
	MaterialLibrary.apply_quality(QualityProfiles.get_profile(QualityProfiles.Level.HIGH))
	assert_eq(int(MaterialLibrary.work_world().get_shader_parameter("detail")), MaterialLibrary.PLANET_DETAIL[2])
	MaterialLibrary.set_motion_time(0.0)


func test_duplicates_are_independent() -> void:
	# N hands / threads: one family, each its own state.
	var a := MaterialLibrary.angelic_hand().duplicate() as ShaderMaterial
	var b := MaterialLibrary.angelic_hand().duplicate() as ShaderMaterial
	a.set_shader_parameter("drive", 1.0)
	assert_eq(b.get_shader_parameter("drive"), 0.0)
	assert_eq(a.shader, b.shader, "same family: one shader")
	MaterialLibrary.set_hand_wrist(a, Vector3(-2, 0, 0), Vector3(-5, 0, 0))
	assert_eq(a.get_shader_parameter("wrist_point"), Vector3(-2, 0, 0))


func test_thread_is_additive_unshaded_and_pixel_wide() -> void:
	var code: String = MaterialLibrary.intent_thread().shader.code
	for mode: String in ["unshaded", "blend_add", "depth_draw_never"]:
		assert_true(code.contains(mode), mode)
	assert_true(code.contains("VIEWPORT_SIZE"), "width in pixels (screen-space strip)")
	assert_true(code.contains("POSITION"), "the vertex stage widens the strip")


func test_strip_encoder_follows_the_contract() -> void:
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0)])
	var mesh := ImmediateMesh.new()
	var box := IntentThreadStrip.fill(mesh, pts, MaterialLibrary.intent_thread())
	assert_eq(mesh.get_surface_count(), 1)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(verts.size(), 6, "two vertices per sample")
	for i in pts.size():
		assert_eq(verts[i * 2], pts[i])
		assert_eq(verts[i * 2 + 1], pts[i], "both at the curve point (no width)")
		assert_almost_eq(uvs[i * 2].y, 0.0, 1e-6)
		assert_almost_eq(uvs[i * 2 + 1].y, 1.0, 1e-6)
		assert_almost_eq(normals[i * 2].x, 1.0, 1e-3, "normal = tangent")
	assert_almost_eq(uvs[0].x, 0.0, 1e-6, "u = 0 at the origin")
	assert_almost_eq(uvs[2].x, 1.0 / 3.0, 1e-4, "u by arc length")
	assert_almost_eq(uvs[4].x, 1.0, 1e-6, "u = 1 at the hand")
	assert_true(box.has_point(Vector3(1.5, 0.0, 0.0)), "AABB covers the curve")
	assert_gt(box.size.y, 0.0, "AABB grown around a flat curve")
	IntentThreadStrip.fill(mesh, PackedVector3Array([Vector3.ZERO]), null)
	assert_eq(mesh.get_surface_count(), 0, "fewer than two points: empty")
	assert_eq(IntentThreadStrip.tangent(PackedVector3Array([Vector3.ONE, Vector3.ONE]), 0), Vector3.UP, "degenerate: never null")
