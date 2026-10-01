extends SceneTree
## Sculpt proof with the game's look (run inside the MAIN project, never part of the game):
## the OBJ with its real material (MaterialLibrary.miku_body() / hand_stone(), fully awake), the
## GENESIS environment (nebula sky, AgX, glow, fog) and the GENESIS light rig at its awake levels
## (back DUSK_ROSE, rim ICE, key PEARL = only shadow caster, fill NEBULA), placed with the
## in-game transform (GenesisLayout). Views are given in the sculpture's object space.
##   tools/_display.sh godot --path . --script res://tools/sculpt/preview/game_look.gd -- \
##     --obj=PATH --kind=miku|hand_left|hand_right --views=JSON --out=DIR [--clay=1] [--shadows=0]
##     [--hair_json=assets/meshes/miku_body.json (MIKU: nebula hair proof)]

var _args := {}

## Mirrors of the animator's constants (GenesisLightRig, Miku.HAIR_DIRECTION,
## RelationThreads.HAIR_SOURCES): those scripts need the autoloads, which a --script run does not
## compile against, so the values are copied here (update when the rig changes).
const BACK_DIR := Vector3(0.05, -0.28, 1.0)
const RIM_DIR := Vector3(-0.85, -0.45, 0.6)
const KEY_DIR := Vector3(0.9, -0.5, -0.28)
const FILL_DIR := Vector3(-0.4, 0.35, -1.0)
const KEY_SHADOW_MAX_DISTANCE := 60.0
const KEY_SHADOW_BLUR := 1.6
const KEY_SHADOW_NORMAL_BIAS := 1.4
const PLANET_RANGE := 7.5
const PLANET_ATTENUATION := 1.6
const HAIR_DIRECTION := Vector3(-0.25, 0.22, -0.94)
const HAIR_SOURCES: Array[Vector3] = [Vector3(-1.1, 2.2, -1.6), Vector3(0.35, 3.2, -2.8),
	Vector3(0.9, 2.6, -2.0), Vector3(-1.6, 3.0, -2.4)]


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


## Proof of HairRibbons.nebula on the sculpture: one mass from hair_root (JSON anchors), heading
## like miku.gd (sculpt tangent blended with its HAIR_DIRECTION), with link strands ending at
## RelationThreads.HAIR_SOURCES (relative to the root).
func _add_hair(body: MeshInstance3D) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_args["hair_json"]))
	var a: Dictionary = meta["anchors"]
	var root := Vector3(a["hair_root"][0], a["hair_root"][1], a["hair_root"][2])
	var tan := Vector3(a["hair_root_tangent"][0], a["hair_root_tangent"][1], a["hair_root_tangent"][2])
	var dir := (tan + HAIR_DIRECTION.normalized() * 1.5).normalized()
	var ends := PackedVector3Array()
	for e in HAIR_SOURCES:
		ends.append(e)
	var layers := [[10, 7101, 9.0, 0.11, 0.45], [8, 7202, 12.0, 0.06, 0.4]]
	for li in layers.size():
		var L: Array = layers[li]
		var m := HairRibbons.nebula(Vector3.ZERO, dir, int(L[1]), int(L[0]), float(L[2]),
			ends if li == 0 else PackedVector3Array())
		var hm := MeshInstance3D.new()
		hm.mesh = HairRibbons.build(m["curves"], float(L[3]), 0.2, 56, Vector3.BACK, true, m["links"], m["groups"])
		var mat := MaterialLibrary.miku_hair().duplicate() as ShaderMaterial
		mat.set_shader_parameter("intensity", float(L[4]))
		mat.set_shader_parameter("seed", float(li) * 1.37 + 0.2)
		hm.material_override = mat
		hm.position = root
		body.add_child(hm)


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

	if _args.has("hair_json"):
		_add_hair(mi)

	var sky := GenesisEnvironment.make_sky_material()
	var env := GenesisEnvironment.make_environment(sky)
	env.ambient_light_energy = 0.26
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	_dir_light(root, Palette.DUSK_ROSE, BACK_DIR, 2.3).light_specular = 0.25
	_dir_light(root, Palette.ICE, RIM_DIR, 1.25)
	var key := _dir_light(root, Palette.PEARL, KEY_DIR, 1.05)
	key.light_volumetric_fog_energy = 0.0
	key.shadow_enabled = _args.get("shadows", "1") != "0"  # --shadows=0: diagnostics
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_max_distance = KEY_SHADOW_MAX_DISTANCE
	key.shadow_blur = KEY_SHADOW_BLUR
	key.shadow_normal_bias = KEY_SHADOW_NORMAL_BIAS
	_dir_light(root, Palette.NEBULA, FILL_DIR, 0.12).light_specular = 0.0
	var glow := OmniLight3D.new()
	glow.position = GenesisLayout.PLANET_CENTER
	glow.light_color = Palette.GOLD
	glow.omni_range = PLANET_RANGE
	glow.omni_attenuation = PLANET_ATTENUATION
	glow.light_energy = 0.6
	root.add_child(glow)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(_args["views"]))
	for v: Dictionary in views:
		# "world": true -> pos/target are world coordinates (in-game camera positions)
		var w := bool(v.get("world", false))
		var pos := _v(v["pos"]) if w else xf * _v(v["pos"])
		var tgt := _v(v["target"]) if w else xf * _v(v["target"])
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
