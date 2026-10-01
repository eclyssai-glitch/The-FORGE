extends SceneTree
## Sculpt proof with the game's look (run inside the MAIN project, never part of the game):
## the OBJ with its real material (MaterialLibrary.miku_body() / hand_stone(), fully awake), the
## GENESIS environment (nebula sky, AgX, glow, fog) and the GENESIS light rig at its awake levels
## (back DUSK_ROSE, rim ICE, key PEARL = only shadow caster, fill NEBULA), placed with the
## in-game transform (GenesisLayout). Views are given in the sculpture's object space.
##   tools/_display.sh godot --path . --script res://tools/sculpt/preview/game_look.gd -- \
##     --obj=PATH --kind=miku|hand_left|hand_right --views=JSON --out=DIR [--clay=1]

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _load_obj(path: String) -> ArrayMesh:
	var text := FileAccess.get_file_as_string(path)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for line in text.split("\n", false):
		if line.begins_with("v "):
			var p := line.split(" ", false)
			verts.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
			cols.append(Color(p[4].to_float(), p[5].to_float(), p[6].to_float()) if p.size() >= 7 else Color.WHITE)
		elif line.begins_with("vn "):
			var p := line.split(" ", false)
			norms.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
		elif line.begins_with("f "):
			var p := line.split(" ", false)
			idx.append(p[1].get_slice("/", 0).to_int() - 1)
			idx.append(p[3].get_slice("/", 0).to_int() - 1)
			idx.append(p[2].get_slice("/", 0).to_int() - 1)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _dir_light(root: Node3D, c: Color, dir: Vector3, e: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = c
	l.light_energy = e
	l.light_volumetric_fog_energy = 0.04
	var d := dir.normalized()
	l.transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.BACK), Vector3.ZERO)
	root.add_child(l)
	return l


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var kind: String = _args.get("kind", "miku")
	var xf := GenesisLayout.miku_transform()
	var mat: Material
	if kind == "miku":
		mat = MaterialLibrary.miku_body().duplicate()
		(mat as ShaderMaterial).set_shader_parameter("awaken", 1.0)
	else:
		xf = GenesisLayout.hand_rest(kind == "hand_left")
		mat = MaterialLibrary.hand_stone().duplicate()
		(mat as ShaderMaterial).set_shader_parameter("veins", 0.35)
	if _args.get("clay", "0") == "1":
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.8, 0.76, 0.72)
		sm.roughness = 0.62
		sm.vertex_color_use_as_albedo = true
		mat = sm
	var mi := MeshInstance3D.new()
	mi.mesh = _load_obj(_args["obj"])
	mi.material_override = mat
	mi.transform = xf
	root.add_child(mi)

	var sky := GenesisEnvironment.make_sky_material()
	var env := GenesisEnvironment.make_environment(sky)
	env.ambient_light_energy = 0.26
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	_dir_light(root, Palette.DUSK_ROSE, GenesisLightRig.BACK_DIR, 2.3).light_specular = 0.25
	_dir_light(root, Palette.ICE, GenesisLightRig.RIM_DIR, 1.25)
	var key := _dir_light(root, Palette.PEARL, GenesisLightRig.KEY_DIR, 1.05)
	key.light_volumetric_fog_energy = 0.0
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_max_distance = GenesisLightRig.KEY_SHADOW_MAX_DISTANCE
	key.shadow_blur = GenesisLightRig.KEY_SHADOW_BLUR
	key.shadow_normal_bias = GenesisLightRig.KEY_SHADOW_NORMAL_BIAS
	_dir_light(root, Palette.NEBULA, GenesisLightRig.FILL_DIR, 0.12).light_specular = 0.0
	var glow := OmniLight3D.new()
	glow.position = GenesisLayout.PLANET_CENTER
	glow.light_color = Palette.GOLD
	glow.omni_range = GenesisLightRig.PLANET_RANGE
	glow.omni_attenuation = GenesisLightRig.PLANET_ATTENUATION
	glow.light_energy = 0.6
	root.add_child(glow)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(_args["views"]))
	for v: Dictionary in views:
		var pos := xf * _v(v["pos"])
		var tgt := xf * _v(v["target"])
		var upv: Vector3 = (xf.basis * _v(v["up"])).normalized() if v.has("up") else Vector3.UP
		cam.look_at_from_position(pos, tgt, upv)
		cam.fov = float(v.get("fov", 35.0))
		cam.near = 0.02
		for i in 12:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(String(_args["out"]).path_join(String(v["name"]) + ".png"))
		print("saved ", v["name"])
	quit(0)
