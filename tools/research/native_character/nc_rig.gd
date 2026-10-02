class_name NCRig
extends RefCounted
## SPIKE (Loop 5 gate, phase 4) — throwaway. Code-generated skinned test mannequin and puppet hand.
## Not the contract rig (that is the procedural-modeler's MikuRig/HandRig); bone NAMES follow the
## contract (docs/contracts/loop-05.md) so the modifier stack built here maps 1:1 onto it.
## Model space: +Y up, +Z forward (her face), +X her left (.L). Every rest basis is IDENTITY: the
## bone axes are the model axes, so +X rotation = bend forward, +Z on .L = raise/abduct.
## Skirt: 4 chains (skirt.f/b/l/r.0..2) instead of the contract's single skirt.0/1/2 — one chain
## cannot swing a cone; the spike shows why (see docs/research/native-character-runtime.md).

const SKIN_COLOR := Color(0.86, 0.84, 0.80)
const EYE_COLOR := Color(0.06, 0.06, 0.08)
const HAND_COLOR := Color(0.93, 0.90, 0.84)

## [name, parent, offset from parent]
const BODY_BONES: Array = [
	["root", "", Vector3(0, 0, 0)],
	["hips", "root", Vector3(0, 0.95, 0)],
	["spine", "hips", Vector3(0, 0.12, 0)],
	["chest", "spine", Vector3(0, 0.17, 0)],
	["neck", "chest", Vector3(0, 0.21, 0)],
	["head", "neck", Vector3(0, 0.10, 0.01)],
	["eye.L", "head", Vector3(0.034, 0.075, 0.085)],
	["eye.R", "head", Vector3(-0.034, 0.075, 0.085)],
	["hair.0", "head", Vector3(0, 0.12, -0.10)],
	["hair.1", "hair.0", Vector3(0, -0.14, -0.05)],
	["hair.2", "hair.1", Vector3(0, -0.16, -0.01)],
	["hair.3", "hair.2", Vector3(0, -0.16, 0.0)],
	["clavicle.L", "chest", Vector3(0.025, 0.17, 0.0)],
	["upper_arm.L", "clavicle.L", Vector3(0.15, -0.01, 0.0)],
	["forearm.L", "upper_arm.L", Vector3(0.08, -0.26, 0.0)],
	["hand.L", "forearm.L", Vector3(0.05, -0.23, 0.02)],
	["index.L", "hand.L", Vector3(0.01, -0.085, 0.025)],
	["index.L.1", "index.L", Vector3(0.0, -0.045, 0.0)],
	["thumb.L", "hand.L", Vector3(-0.005, -0.025, 0.045)],
	["thumb.L.1", "thumb.L", Vector3(0.0, -0.035, 0.015)],
	["clavicle.R", "chest", Vector3(-0.025, 0.17, 0.0)],
	["upper_arm.R", "clavicle.R", Vector3(-0.15, -0.01, 0.0)],
	["forearm.R", "upper_arm.R", Vector3(-0.08, -0.26, 0.0)],
	["hand.R", "forearm.R", Vector3(-0.05, -0.23, 0.02)],
	["index.R", "hand.R", Vector3(-0.01, -0.085, 0.025)],
	["index.R.1", "index.R", Vector3(0.0, -0.045, 0.0)],
	["thumb.R", "hand.R", Vector3(0.005, -0.025, 0.045)],
	["thumb.R.1", "thumb.R", Vector3(0.0, -0.035, 0.015)],
]
## Skirt chains: [suffix, horizontal direction]
const SKIRT_CHAINS: Array = [
	["f", Vector3(0, 0, 1)], ["l", Vector3(1, 0, 0)], ["b", Vector3(0, 0, -1)], ["r", Vector3(-1, 0, 0)],
]
const SKIRT_TOP_Y := 0.90
const SKIRT_HEM_Y := 0.30
const SKIRT_TOP_R := 0.14
const SKIRT_HEM_R := 0.36

## Puppet hand (contract: wrist, palm, thumb(3), index(3), middle(3), ring(3), little(3)).
## Built pointing DOWN (-Y, fingers), palm facing +Z, at unit scale (the node scales it: giant).
const FINGERS: Array = [
	# name, base offset from palm, segment lengths, sideways splay
	["thumb", Vector3(0.10, 0.02, 0.06), [0.09, 0.07, 0.06], 0.6],
	["index", Vector3(0.065, -0.17, 0.0), [0.10, 0.065, 0.05], 0.08],
	["middle", Vector3(0.02, -0.18, 0.0), [0.11, 0.07, 0.055], 0.0],
	["ring", Vector3(-0.025, -0.17, 0.0), [0.10, 0.065, 0.05], -0.06],
	["little", Vector3(-0.065, -0.15, 0.0), [0.08, 0.05, 0.045], -0.14],
]


static func build_body() -> Node3D:
	var root := Node3D.new()
	root.name = "Mannequin"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	for b: Array in BODY_BONES:
		_add_bone(sk, b[0], b[1], b[2])
	for c: Array in SKIRT_CHAINS:
		var dir: Vector3 = c[1]
		var top := Vector3(0, SKIRT_TOP_Y - 0.95, 0) + dir * SKIRT_TOP_R
		var step := (Vector3(0, SKIRT_HEM_Y - SKIRT_TOP_Y, 0) + dir * (SKIRT_HEM_R - SKIRT_TOP_R)) / 3.0
		_add_bone(sk, "skirt.%s.0" % c[0], "hips", top)
		_add_bone(sk, "skirt.%s.1" % c[0], "skirt.%s.0" % c[0], step)
		_add_bone(sk, "skirt.%s.2" % c[0], "skirt.%s.1" % c[0], step)
	sk.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _body_mesh(sk)
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()
	return root


static func build_hand() -> Node3D:
	var root := Node3D.new()
	root.name = "PuppetHandRig"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	_add_bone(sk, "wrist", "", Vector3.ZERO)
	_add_bone(sk, "palm", "wrist", Vector3(0, -0.06, 0))
	for f: Array in FINGERS:
		var n: String = f[0]
		var lens: Array = f[2]
		var splay: float = f[3]
		var dir := Vector3(sin(splay), -cos(splay), 0.0)
		if n == "thumb":
			dir = Vector3(0.55, -0.6, 0.45).normalized()
		_add_bone(sk, "%s.0" % n, "palm", f[1])
		_add_bone(sk, "%s.1" % n, "%s.0" % n, dir * float(lens[0]))
		_add_bone(sk, "%s.2" % n, "%s.1" % n, dir * float(lens[1]))
	sk.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "HandMesh"
	mi.mesh = _hand_mesh(sk)
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()
	return root


static func _add_bone(sk: Skeleton3D, n: String, parent: String, offset: Vector3) -> void:
	var i := sk.get_bone_count()
	sk.add_bone(n)
	if parent != "":
		sk.set_bone_parent(i, sk.find_bone(parent))
	sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, offset))


## ---------------------------------------------------------------- mesh generation (weighted tubes)

class MeshAcc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()

	func add_vertex(p: Vector3, nor: Vector3, bw: Dictionary) -> void:
		v.append(p)
		n.append(nor)
		var keys: Array = bw.keys()
		keys.sort_custom(func(a: int, b: int) -> bool: return float(bw[a]) > float(bw[b]))
		var total := 0.0
		for k in range(mini(4, keys.size())):
			total += float(bw[keys[k]])
		for k in range(4):
			if k < keys.size():
				bones.append(int(keys[k]))
				weights.append(float(bw[keys[k]]) / total)
			else:
				bones.append(0)
				weights.append(0.0)

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights
		a[Mesh.ARRAY_INDEX] = idx
		return a


static func _gpos(sk: Skeleton3D, n: String) -> Vector3:
	return sk.get_bone_global_rest(sk.find_bone(n)).origin


## Tube along joints `pts` (owner bone of segment i = bones[i]); weights blend at the joints.
static func _tube(acc: MeshAcc, pts: Array, bones: Array, radii: Array, sides: int = 10, rings_per_seg: int = 4,
		cap_end: bool = true) -> void:
	var start := acc.v.size()
	var rings := 0
	var nseg := pts.size() - 1
	for i in range(nseg):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var axis := (b - a).normalized()
		var ref := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var u := axis.cross(ref).normalized()
		var w := axis.cross(u).normalized()
		var last := 1 if i == nseg - 1 else 0
		for r in range(rings_per_seg + last):
			var t := float(r) / float(rings_per_seg)
			var c := a.lerp(b, t)
			var rad := lerpf(float(radii[i]), float(radii[i + 1]), t)
			var bw := {}
			var cur: int = bones[i]
			var wc := 1.0
			if t < 0.3 and i > 0:
				var wp := 0.5 * (1.0 - t / 0.3)
				bw[int(bones[i - 1])] = wp
				wc -= wp
			if t > 0.7 and i < nseg - 1:
				var wn := 0.5 * ((t - 0.7) / 0.3)
				bw[int(bones[i + 1])] = float(bw.get(int(bones[i + 1]), 0.0)) + wn
				wc -= wn
			bw[cur] = float(bw.get(cur, 0.0)) + wc
			for s in range(sides):
				var ang := TAU * float(s) / float(sides)
				var dir := u * cos(ang) + w * sin(ang)
				acc.add_vertex(c + dir * rad, dir, bw)
			rings += 1
	for r in range(rings - 1):
		for s in range(sides):
			var s2 := (s + 1) % sides
			var i0 := start + r * sides + s
			var i1 := start + r * sides + s2
			var i2 := start + (r + 1) * sides + s
			var i3 := start + (r + 1) * sides + s2
			acc.idx.append_array([i0, i2, i1, i1, i2, i3])
	if cap_end:
		var tip: Vector3 = pts[nseg]
		var ci := acc.v.size()
		acc.add_vertex(tip + (tip - Vector3(pts[nseg - 1])).normalized() * float(radii[nseg]) * 0.6,
				(tip - Vector3(pts[nseg - 1])).normalized(), {int(bones[nseg - 1]): 1.0})
		var lr := start + (rings - 1) * sides
		for s in range(sides):
			acc.idx.append_array([lr + s, ci, lr + (s + 1) % sides])


static func _sphere(acc: MeshAcc, c: Vector3, radii: Vector3, bone: int, lat: int = 8, lon: int = 12) -> void:
	var start := acc.v.size()
	for i in range(lat + 1):
		var th := PI * float(i) / float(lat)
		for j in range(lon):
			var ph := TAU * float(j) / float(lon)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			acc.add_vertex(c + d * radii, d, {bone: 1.0})
	for i in range(lat):
		for j in range(lon):
			var j2 := (j + 1) % lon
			var a := start + i * lon + j
			var b := start + i * lon + j2
			var cc := start + (i + 1) * lon + j
			var d2 := start + (i + 1) * lon + j2
			acc.idx.append_array([a, b, cc, b, d2, cc])


static func _mat(c: Color, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _body_mesh(sk: Skeleton3D) -> ArrayMesh:
	var acc := MeshAcc.new()
	var bi := func(n: String) -> int: return sk.find_bone(n)
	# torso: hips -> spine -> chest -> neck -> head base
	var torso_pts := [_gpos(sk, "hips") + Vector3(0, -0.04, 0), _gpos(sk, "spine"), _gpos(sk, "chest"),
			_gpos(sk, "neck"), _gpos(sk, "head")]
	_tube(acc, torso_pts, [bi.call("hips"), bi.call("spine"), bi.call("chest"), bi.call("neck")],
			[0.14, 0.105, 0.125, 0.05, 0.045], 14, 4, false)
	_sphere(acc, _gpos(sk, "head") + Vector3(0, 0.09, 0.0), Vector3(0.085, 0.11, 0.095), bi.call("head"), 10, 14)
	# chignon (sculpted hair knot, rigid on the head) + hair tail (spring chain)
	_sphere(acc, _gpos(sk, "hair.0") + Vector3(0, 0.0, 0.0), Vector3(0.05, 0.05, 0.05), bi.call("head"), 6, 10)
	var hair_tip := _gpos(sk, "hair.3") + Vector3(0, -0.12, 0)
	_tube(acc, [_gpos(sk, "hair.0"), _gpos(sk, "hair.1"), _gpos(sk, "hair.2"), _gpos(sk, "hair.3"), hair_tip],
			[bi.call("hair.0"), bi.call("hair.1"), bi.call("hair.2"), bi.call("hair.3")],
			[0.035, 0.04, 0.035, 0.025, 0.01], 8, 3)
	for side in ["L", "R"]:
		var tip := _gpos(sk, "index.%s.1" % side) + (_gpos(sk, "index.%s.1" % side) - _gpos(sk, "index.%s" % side)).normalized() * 0.04
		_tube(acc, [_gpos(sk, "clavicle.%s" % side), _gpos(sk, "upper_arm.%s" % side), _gpos(sk, "forearm.%s" % side),
				_gpos(sk, "hand.%s" % side), _gpos(sk, "index.%s" % side), _gpos(sk, "index.%s.1" % side), tip],
				[bi.call("clavicle.%s" % side), bi.call("upper_arm.%s" % side), bi.call("forearm.%s" % side),
				bi.call("hand.%s" % side), bi.call("index.%s" % side), bi.call("index.%s.1" % side)],
				[0.045, 0.042, 0.033, 0.026, 0.014, 0.011, 0.009], 10, 4)
		var ttip := _gpos(sk, "thumb.%s.1" % side) + (_gpos(sk, "thumb.%s.1" % side) - _gpos(sk, "thumb.%s" % side)).normalized() * 0.03
		_tube(acc, [_gpos(sk, "hand.%s" % side), _gpos(sk, "thumb.%s" % side), _gpos(sk, "thumb.%s.1" % side), ttip],
				[bi.call("hand.%s" % side), bi.call("thumb.%s" % side), bi.call("thumb.%s.1" % side)],
				[0.018, 0.013, 0.011, 0.009], 8, 3)
	# skirt: cone, each vertex weighted by angular sector to the 4 chains and by height along them
	_skirt(acc, sk)
	var body := ArrayMesh.new()
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
	body.surface_set_material(0, _mat(SKIN_COLOR, 0.55))
	var eyes := MeshAcc.new()
	for side in ["L", "R"]:
		# pupils: a flattened sphere ahead of the eye bone (the eye bone rotates it)
		_sphere(eyes, _gpos(sk, "eye.%s" % side) + Vector3(0, 0, 0.012), Vector3(0.016, 0.02, 0.008),
				bi.call("eye.%s" % side), 6, 10)
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, eyes.arrays())
	body.surface_set_material(1, _mat(EYE_COLOR, 0.2))
	return body


static func _skirt(acc: MeshAcc, sk: Skeleton3D) -> void:
	var sides := 24
	var rings := 10
	var start := acc.v.size()
	var hips := sk.find_bone("hips")
	for r in range(rings + 1):
		var t := float(r) / float(rings)
		var y := lerpf(SKIRT_TOP_Y, SKIRT_HEM_Y, t)
		var rad := lerpf(SKIRT_TOP_R, SKIRT_HEM_R, t)
		for s in range(sides):
			var ang := TAU * float(s) / float(sides)
			var dir := Vector3(sin(ang), 0, cos(ang))
			var bw := {}
			var seg := t * 3.0
			var level := mini(int(seg), 2)
			for c: Array in SKIRT_CHAINS:
				var cd: Vector3 = c[1]
				var share := maxf(dir.dot(cd), 0.0)
				share = share * share
				if share < 1e-4:
					continue
				var b := sk.find_bone("skirt.%s.%d" % [c[0], level])
				bw[b] = float(bw.get(b, 0.0)) + share * minf(t * 4.0, 1.0)
			if t < 0.25:
				bw[hips] = float(bw.get(hips, 0.0)) + (1.0 - t * 4.0)
			acc.add_vertex(Vector3(0, y, 0) + dir * rad, (dir + Vector3(0, 0.35, 0)).normalized(), bw)
	for r in range(rings):
		for s in range(sides):
			var s2 := (s + 1) % sides
			var i0 := start + r * sides + s
			var i1 := start + r * sides + s2
			var i2 := start + (r + 1) * sides + s
			var i3 := start + (r + 1) * sides + s2
			acc.idx.append_array([i0, i2, i1, i1, i2, i3])
			acc.idx.append_array([i0, i1, i2, i1, i3, i2])  # double-sided (inside visible from below)


static func _hand_mesh(sk: Skeleton3D) -> ArrayMesh:
	var acc := MeshAcc.new()
	var palm := sk.find_bone("palm")
	var wrist := sk.find_bone("wrist")
	_tube(acc, [Vector3(0, 0.08, 0), Vector3(0, -0.04, 0)], [wrist], [0.05, 0.065], 12, 3, false)
	_sphere(acc, Vector3(0, -0.11, 0), Vector3(0.10, 0.09, 0.035), palm, 8, 14)
	for f: Array in FINGERS:
		var n: String = f[0]
		var p0 := _gpos(sk, "%s.0" % n)
		var p1 := _gpos(sk, "%s.1" % n)
		var p2 := _gpos(sk, "%s.2" % n)
		var lens: Array = f[2]
		var tip := p2 + (p2 - p1).normalized() * float(lens[2])
		_tube(acc, [p0, p1, p2, tip], [sk.find_bone("%s.0" % n), sk.find_bone("%s.1" % n), sk.find_bone("%s.2" % n)],
				[0.024, 0.021, 0.018, 0.014], 8, 3)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
	var mat := _mat(HAND_COLOR, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.92, 0.78)
	mat.emission_energy_multiplier = 0.25
	m.surface_set_material(0, mat)
	return m
