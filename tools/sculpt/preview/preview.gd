extends SceneTree
## Offline sculpt preview: loads an OBJ (v x y z r g b / vn / f a//a) and renders views to PNG.
## args: --obj=PATH --out=DIR --views=JSON_PATH

var _args := {}


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


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
			# OBJ is CCW from outside; Godot front faces are CW
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


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _run() -> void:
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(_args["views"]))
	var mesh := _load_obj(_args["obj"])
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_back;
uniform vec3 clay = vec3(0.80, 0.76, 0.72);
uniform float ao_amount = 0.85;
void fragment() {
	ALBEDO = clay * mix(1.0, COLOR.r, ao_amount);
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("ao_amount", float(_args.get("ao", "0.85")))
	mi.material_override = mat
	root3d.add_child(mi)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.047, 0.055, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.current = true
	var lights: Array[DirectionalLight3D] = []
	for i in 3:
		var l := DirectionalLight3D.new()
		l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		l.directional_shadow_max_distance = 30.0
		root3d.add_child(l)
		lights.append(l)
	for v: Dictionary in views:
		var tgt := _v(v["target"])
		var upv: Vector3 = _v(v["up"]) if v.has("up") else Vector3.UP
		cam.look_at_from_position(_v(v["pos"]), tgt, upv)
		cam.fov = float(v.get("fov", 35.0))
		cam.near = 0.02
		var mode: String = v.get("light", "studio")
		var fwd: Vector3 = (tgt - cam.global_position).normalized()
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		var key_dir: Vector3
		var rim_dir: Vector3
		var fill_dir: Vector3
		if mode == "hard":
			# hard light from the camera side, slightly above: exposes every crease
			key_dir = (fwd + Vector3.DOWN * 0.8 - right * 0.25).normalized()
			env.ambient_light_energy = 0.12
			_set_light(lights[0], key_dir, Color(1.0, 0.96, 0.9), 1.5, true, 1.0)
			_set_light(lights[1], fwd, Color(1, 1, 1), 0.0, false, 0.0)
			_set_light(lights[2], fwd, Color(1, 1, 1), 0.0, false, 0.0)
		elif mode == "soft_side":
			key_dir = (fwd * 0.45 + right * 1.0 + Vector3.DOWN * 0.35).normalized()
			fill_dir = (fwd * 0.8 - right * 0.6 + Vector3.DOWN * 0.1).normalized()
			rim_dir = (-fwd * 1.0 - right * 0.4 + Vector3.DOWN * 0.3).normalized()
			env.ambient_light_energy = 0.3
			_set_light(lights[0], key_dir, Color(1.0, 0.93, 0.86), 1.25, true, 3.0)
			_set_light(lights[1], fill_dir, Color(0.78, 0.84, 1.0), 0.35, false, 0.0)
			_set_light(lights[2], rim_dir, Color(0.7, 0.8, 1.0), 0.9, false, 0.0)
		else:
			key_dir = (fwd * 0.7 + right * 0.7 + Vector3.DOWN * 0.6).normalized()
			rim_dir = (-fwd * 1.0 - right * 0.6 + Vector3.DOWN * 0.2).normalized()
			fill_dir = (fwd * 0.6 - right * 0.8).normalized()
			env.ambient_light_energy = 0.25
			_set_light(lights[0], key_dir, Color(1.0, 0.92, 0.82), 1.35, true, 1.8)
			_set_light(lights[1], rim_dir, Color(0.66, 0.78, 1.0), 1.3, false, 0.0)
			_set_light(lights[2], fill_dir, Color(0.75, 0.8, 0.95), 0.3, false, 0.0)
		for i in 6:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(String(_args["out"]).path_join(String(v["name"]) + ".png"))
		print("saved ", v["name"])
	quit(0)


## Shadows are PCF softened with shadow_blur (like the game's LightRig), never PCSS: a non-zero
## light_angular_distance samples the penumbra with per-pixel rotated noise, and a single captured
## frame (no TAA to average it) shows it as a regular dot/checker pattern in every penumbra (chin
## on the neck, nose on the cheek, between the fingers) that is not in the mesh.
func _set_light(l: DirectionalLight3D, dir: Vector3, c: Color, e: float, shadow: bool, blur: float) -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	l.look_at_from_position(Vector3.ZERO, dir, up)
	l.light_color = c
	l.light_energy = e
	l.shadow_enabled = shadow and e > 0.0
	l.light_angular_distance = 0.0
	l.shadow_blur = blur
	l.shadow_normal_bias = 2.0
	l.visible = e > 0.0
