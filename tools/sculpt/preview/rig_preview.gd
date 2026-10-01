extends SceneTree
## Rig proofs (Loop 5) in the real renderer (Forward+, xvfb when headless): MikuRig / HandRig
## built exactly like the game builds them, posed at their limits and rendered in clay x baked
## AO (or with weight colours), two views per image. Run inside the MAIN project (never part of
## the game; this folder is .gdignore'd):
##   tools/_display.sh tools/godot.sh --path . --script res://tools/sculpt/preview/rig_preview.gd \
##     -- --out=tools/sculpt/previews [--only=miku|hand]

const VIEW_SIZE := Vector2i(800, 900)
const CLAY := Color(0.8, 0.76, 0.72)

var _args := {}
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


# ------------------------------------------------------------------ scene

func _setup() -> void:
	_vp = SubViewport.new()
	_vp.size = VIEW_SIZE
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	get_root().add_child(_vp)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.047, 0.055, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.current = true
	_cam.near = 0.02
	_light(Vector3(0.7, -0.6, -0.7), Color(1.0, 0.93, 0.85), 1.3, true)
	_light(Vector3(-0.8, -0.2, 0.9), Color(0.66, 0.78, 1.0), 0.9, false)
	_light(Vector3(-0.6, -0.1, -0.8), Color(0.75, 0.8, 0.95), 0.35, false)


func _light(dir: Vector3, c: Color, e: float, shadow: bool) -> void:
	var l := DirectionalLight3D.new()
	_vp.add_child(l)
	var d := dir.normalized()
	l.look_at_from_position(Vector3.ZERO, d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	l.light_color = c
	l.light_energy = e
	l.shadow_enabled = shadow
	l.shadow_blur = 1.6
	l.shadow_normal_bias = 2.0
	l.directional_shadow_max_distance = 30.0


func _clay() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = CLAY
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.62
	return m


## Same skinned surface with COLOR = weighted bone colours (AO kept as shading).
func _weights_mesh(d: RigData) -> ArrayMesh:
	var cols := PackedColorArray()
	cols.resize(d.vertices.size())
	var pal: Array[Color] = []
	for i in d.bone_count():
		pal.append(Color.from_hsv(fmod(float(i) * 0.618034, 1.0), 0.75, 0.95))
	for v in d.vertices.size():
		var c := Color(0, 0, 0)
		for j in 4:
			var w := d.weights[4 * v + j]
			c += pal[d.bones[4 * v + j]] * w
		var ao := d.colors[v].r
		cols[v] = Color(c.r * ao, c.g * ao, c.b * ao)
	var arr := d.mesh().surface_get_arrays(0)
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _clear_stage() -> void:
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()


func _shoot(file: String, views: Array) -> void:
	var sheet := Image.create(VIEW_SIZE.x * views.size(), VIEW_SIZE.y, false, Image.FORMAT_RGB8)
	for i in views.size():
		var v: Array = views[i]
		_cam.fov = float(v[2]) if v.size() > 2 else 34.0
		_cam.look_at_from_position(v[0], v[1], Vector3.UP)
		for f in 8:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		var img := _vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, VIEW_SIZE), Vector2i(VIEW_SIZE.x * i, 0))
	sheet.save_jpg(String(_args.get("out", "tools/sculpt/previews")).path_join(file + ".jpg"), 0.88)
	print("saved ", file)


# ------------------------------------------------------------------ posing helpers

func _b(sk: Skeleton3D, n: String) -> int:
	var i := sk.find_bone(n)
	assert(i >= 0, n)
	return i


func _g(sk: Skeleton3D, n: String, axis: Vector3, angle: float) -> void:
	RigData.rotate_global(sk, _b(sk, n), axis, angle)


func _l(sk: Skeleton3D, n: String, euler: Vector3) -> void:
	RigData.pose_local(sk, _b(sk, n), euler)


## Points `bone` (its joint -> `child` joint) along `dir` (skeleton space).
func _aim(sk: Skeleton3D, bone: String, child: String, dir: Vector3) -> void:
	var g := RigData.global_poses(sk)
	var cur := (g[_b(sk, child)].origin - g[_b(sk, bone)].origin).normalized()
	var axis := cur.cross(dir.normalized())
	if axis.length() < 1e-5:
		return
	RigData.rotate_global(sk, _b(sk, bone), axis, cur.angle_to(dir.normalized()))


func _pos(sk: Skeleton3D, n: String) -> Vector3:
	return RigData.global_poses(sk)[_b(sk, n)].origin


func _axis(sk: Skeleton3D, n: String, col: int) -> Vector3:
	return RigData.global_poses(sk)[_b(sk, n)].basis[col].normalized()


## Two views of a hand of MIKU: from the palm side and from the back/side, framed on the bones.
func _miku_hand_views(sk: Skeleton3D, sfx: String) -> Array:
	var c := (_pos(sk, "hand" + sfx) + _pos(sk, "middle.1" + sfx)) * 0.5
	var n := _axis(sk, "hand" + sfx, 2)
	var x := _axis(sk, "hand" + sfx, 0)
	return [[c + (n * 1.5 + Vector3.UP * 0.35), c, 26.0], [c + (-n * 0.9 + x * 1.1 + Vector3.UP * 0.3), c, 26.0]]


func _miku_fingers(sk: Skeleton3D, sfx: String, curl: float, spread: float) -> void:
	var s := -1.0 if sfx == ".R" else 1.0
	var ang := {"thumb": [0.45, 0.8], "index": [1.3, 1.7], "middle": [1.3, 1.75],
		"ring": [1.25, 1.75], "little": [1.2, 1.7]}
	var fan := {"thumb": 0.0, "index": 1.0, "middle": 0.2, "ring": -0.6, "little": -1.2}
	for f: String in ang:
		var a: Array = ang[f]
		_l(sk, f + ".0" + sfx, Vector3(float(a[0]) * curl, 0.0, float(fan[f]) * spread * s))
		_l(sk, f + ".1" + sfx, Vector3(float(a[1]) * curl, 0.0, 0.0))


# ------------------------------------------------------------------ MIKU

func _miku_shots() -> void:
	var rig := MikuRig.build(_clay())
	_stage.add_child(rig)
	var sk := MikuRig.get_skeleton(rig)
	var front := [Vector3(0, -0.9, 12.5), Vector3(0, -1.25, 0), 36.0]
	var q34 := [Vector3(7.6, 0.4, 9.4), Vector3(0, -1.1, 0), 36.0]
	var back := [Vector3(-3.5, 0.2, -11.5), Vector3(0, -1.2, -0.2), 36.0]
	var bust := [Vector3(2.2, 1.7, 3.6), Vector3(0.05, 0.95, 0.1), 36.0]
	var bust_l := [Vector3(-2.6, 1.5, 3.2), Vector3(0.0, 0.95, 0.1), 36.0]
	var side := [Vector3(4.2, 1.0, 0.4), Vector3(0, 0.9, 0.0), 36.0]

	# weights (rest pose)
	var mi := MikuRig.get_mesh_instance(rig)
	var wmesh := _weights_mesh(MikuRig.data())
	var clay_mesh := mi.mesh
	mi.mesh = wmesh
	await _shoot("rig_miku_weights", [front, back])
	await _shoot("rig_miku_weights_bust", [bust, [Vector3(1.6, -0.3, 2.0), Vector3(1.1, -0.55, 0.85), 26.0]])
	mi.mesh = clay_mesh
	await _shoot("rig_miku_rest", [front, q34])

	# head turned + tilted, nod; then looking up and back
	sk.reset_bone_poses()
	_g(sk, "neck", Vector3.UP, 0.35)
	_g(sk, "head", Vector3.UP, 0.55)
	var g := RigData.global_poses(sk)
	_g(sk, "head", g[_b(sk, "head")].basis.z, 0.35)
	await _shoot("rig_miku_head_turn_tilt", [bust, side])
	sk.reset_bone_poses()
	_l(sk, "neck", Vector3(-0.35, 0.0, 0.0))
	_l(sk, "head", Vector3(-0.55, -0.4, 0.0))
	await _shoot("rig_miku_head_up_back", [bust, bust_l])

	# arms raised overhead (clavicles elevated, elbows soft)
	sk.reset_bone_poses()
	for s in [1.0, -1.0]:
		var sfx := ".L" if s > 0.0 else ".R"
		_g(sk, "clavicle" + sfx, Vector3(0, 0, 1), 0.22 * s)
		_aim(sk, "upper_arm" + sfx, "forearm" + sfx, Vector3(0.38 * s, 1.0, 0.12))
		_l(sk, "forearm" + sfx, Vector3(0.35, 0.0, 0.0))
		_l(sk, "hand" + sfx, Vector3(0.3, 0.0, 0.0))
	_l(sk, "head", Vector3(-0.3, 0.0, 0.0))
	await _shoot("rig_miku_arms_up", [[Vector3(0, 0.6, 9.5), Vector3(0, 0.2, 0), 40.0], [Vector3(5.0, 1.6, 6.5), Vector3(0, 0.6, 0), 40.0]])
	var sh := _pos(sk, "upper_arm.L")
	await _shoot("rig_miku_arms_up_shoulder", [[sh + Vector3(0.6, -0.1, 1.3), sh + Vector3(0, -0.05, 0), 34.0], [sh + Vector3(1.0, -0.55, -0.9), sh + Vector3(0, -0.1, 0), 34.0]])

	# arms crossing in front of the chest, elbows folded
	sk.reset_bone_poses()
	_aim(sk, "upper_arm.L", "forearm.L", Vector3(0.3, -0.55, 1.0))
	_aim(sk, "upper_arm.R", "forearm.R", Vector3(-0.3, -0.35, 1.0))
	_aim(sk, "forearm.L", "hand.L", Vector3(-1.0, 0.12, 0.15))
	_aim(sk, "forearm.R", "hand.R", Vector3(1.0, 0.3, 0.25))
	_miku_fingers(sk, ".L", 0.35, 0.0)
	_miku_fingers(sk, ".R", 0.35, 0.0)
	await _shoot("rig_miku_arms_cross", [[Vector3(0.6, 1.0, 5.0), Vector3(0, 0.45, 0.4), 38.0], [Vector3(3.6, 0.9, 3.4), Vector3(0, 0.45, 0.3), 38.0]])
	var el := _pos(sk, "forearm.L")
	var el2 := _pos(sk, "forearm.R")
	await _shoot("rig_miku_arms_cross_elbows", [[el + Vector3(0.9, 0.1, 0.6), el, 30.0], [el2 + Vector3(-0.9, -0.2, 0.6), el2, 30.0]])

	# torso: forward bend + twist + side bend
	sk.reset_bone_poses()
	_l(sk, "spine", Vector3(0.22, 0.25, 0.1))
	_l(sk, "chest", Vector3(0.18, 0.2, 0.12))
	_l(sk, "hips", Vector3(-0.08, 0.0, -0.06))
	await _shoot("rig_miku_torso_bend_twist", [q34, [Vector3(6.0, 0.2, -3.5), Vector3(0, 0.0, 0), 36.0]])

	# skirt swinging forward and to the side
	sk.reset_bone_poses()
	_l(sk, "skirt.0", Vector3(0.12, 0.0, 0.1))
	_l(sk, "skirt.1", Vector3(0.16, 0.0, 0.12))
	_l(sk, "skirt.2", Vector3(0.2, 0.0, 0.14))
	await _shoot("rig_miku_skirt_swing", [front, [Vector3(11.5, -0.9, -0.2), Vector3(0, -1.3, -0.2), 36.0]])

	# fingers: left fist, right open and spread
	sk.reset_bone_poses()
	_miku_fingers(sk, ".L", 1.0, 0.0)
	_l(sk, "hand.L", Vector3(0.35, 0.0, 0.0))
	_miku_fingers(sk, ".R", -0.12, 1.0)
	await _shoot("rig_miku_fingers_fist_L", _miku_hand_views(sk, ".L"))
	await _shoot("rig_miku_fingers_open_R", _miku_hand_views(sk, ".R"))

	# appearance extremes (min | max), combined with a small pose
	sk.reset_bone_poses()
	var lo := {}
	var hi := {}
	for k: String in MikuRig.APPEARANCE:
		lo[k] = MikuRig.APPEARANCE[k]["min"]
		hi[k] = MikuRig.APPEARANCE[k]["max"]
	lo["height"] = 1.0
	hi["height"] = 1.0
	MikuRig.apply_appearance(rig, lo)
	await _shoot("rig_miku_appearance_min", [bust, front])
	MikuRig.apply_appearance(rig, hi)
	await _shoot("rig_miku_appearance_max", [bust, front])
	MikuRig.apply_appearance(rig, {})
	rig.queue_free()


# ------------------------------------------------------------------ hand

func _hand_shots() -> void:
	for side in [HandRig.Side.LEFT, HandRig.Side.RIGHT]:
		var tag := "left" if side == HandRig.Side.LEFT else "right"
		var zs := 1.0 if side == HandRig.Side.LEFT else -1.0
		var rig := HandRig.build(side, _clay())
		_stage.add_child(rig)
		var sk := HandRig.get_skeleton(rig)
		var c := Vector3(1.0, 0.5, -0.3 * zs)
		var pv := [c + Vector3(-1.0, 10.5, 1.5 * zs), c, 44.0]          # palm side
		var dv := [c + Vector3(-1.0, -10.5, 1.5 * zs), c, 44.0]         # back of the hand
		var qv := [c + Vector3(8.0, 4.5, -6.0 * zs), c, 44.0]           # fingertips + thumb side
		var tv := [c + Vector3(1.0, 1.5, -11.0 * zs), c, 44.0]          # thumb side
		if side == HandRig.Side.LEFT:
			var mi := HandRig.get_mesh_instance(rig)
			var cm := mi.mesh
			mi.mesh = _weights_mesh(HandRig.data())
			await _shoot("rig_hand_weights", [pv, dv])
			mi.mesh = cm
		# open: fingers extended back a little and fanned
		sk.reset_bone_poses()
		var fan := {"thumb": 0.25, "index": 0.18, "middle": 0.0, "ring": -0.16, "little": -0.32}
		for f: String in HandRig.FINGERS:
			HandRig.pose_finger(rig, f, -0.15, float(fan[f]))
		await _shoot("rig_hand_%s_open" % tag, [pv, qv])
		# fist: fingers closed, thumb folded over them
		sk.reset_bone_poses()
		for f: String in HandRig.FINGERS:
			HandRig.pose_finger(rig, f, 1.0)
		_l(sk, "thumb.0", Vector3(0.55, 0.0, -0.5 * zs))
		_l(sk, "thumb.1", Vector3(0.55, 0.0, 0.0))
		_l(sk, "thumb.2", Vector3(0.65, 0.0, 0.0))
		await _shoot("rig_hand_%s_fist" % tag, [qv, dv])
		# pinch: index curled until its tip is within the thumb's reach, thumb aimed at it
		sk.reset_bone_poses()
		var reach := (_pos(sk, "thumb.tip") - _pos(sk, "thumb.0")).length() * 0.97
		var curl := 0.2
		while curl < 1.2:
			HandRig.pose_finger(rig, "index", curl)
			if (_pos(sk, "index.tip") - _pos(sk, "thumb.0")).length() <= reach:
				break
			curl += 0.02
		HandRig.pose_finger(rig, "middle", curl + 0.15)
		HandRig.pose_finger(rig, "ring", curl + 0.3)
		HandRig.pose_finger(rig, "little", curl + 0.4)
		_l(sk, "thumb.1", Vector3(0.12, 0.0, 0.0))
		_l(sk, "thumb.2", Vector3(0.18, 0.0, 0.0))
		for it in 3:
			var aim := _pos(sk, "index.tip") + _axis(sk, "index.2", 2) * 0.25
			var cur := (_pos(sk, "thumb.tip") - _pos(sk, "thumb.0")).normalized()
			var want := (aim - _pos(sk, "thumb.0")).normalized()
			if cur.cross(want).length() > 1e-5:
				RigData.rotate_global(sk, _b(sk, "thumb.0"), cur.cross(want), cur.angle_to(want))
		await _shoot("rig_hand_%s_pinch" % tag, [qv, tv])
		# cup (concha): every finger softly curled and closed together, thumb raised as the rim
		sk.reset_bone_poses()
		var close := {"thumb": 0.0, "index": -0.08, "middle": 0.0, "ring": 0.06, "little": 0.14}
		for f: String in HandRig.FINGERS:
			HandRig.pose_finger(rig, f, 0.42, float(close[f]))
		_l(sk, "thumb.0", Vector3(0.2, 0.0, -0.2 * zs))
		await _shoot("rig_hand_%s_cup" % tag, [pv, tv])
		# wrist flexed (palm towards the forearm) with the fingers relaxed
		sk.reset_bone_poses()
		_l(sk, "palm", Vector3(0.95, 0.0, 0.25 * zs))
		for f: String in HandRig.FINGERS:
			HandRig.pose_finger(rig, f, 0.25)
		await _shoot("rig_hand_%s_wrist" % tag, [[Vector3(-1.0, 1.5, -11.0 * zs), Vector3(-1.0, 0.0, 0.0), 48.0], [Vector3(-2.0, -9.5, -4.0 * zs), Vector3(-1.0, 0.0, 0.0), 48.0]])
		rig.queue_free()
		await process_frame


func _run() -> void:
	_setup()
	var only: String = _args.get("only", "")
	if only == "" or only == "miku":
		await _miku_shots()
	_clear_stage()
	if only == "" or only == "hand":
		await _hand_shots()
	quit(0)
