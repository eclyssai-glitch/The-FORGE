class_name MikuMannequin
extends RefCounted
## DEVELOPMENT STAND-IN for MIKU's rig (Loop 5). Owner: animator. Used by MikuBody ONLY when the
## procedural-modeler's `MikuRig.build()` does not exist in the project (parallel development:
## docs/ANIMATION.md, "Living — integration"). It builds a Skeleton3D with the contract's bone
## names (`root, hips, spine, chest, neck, head, clavicle.L/R, upper_arm.L/R, forearm.L/R,
## hand.L/R, thumb/index/middle/ring/little.L/R.0-1, skirt.0/1/2`) and rigid primitive segments
## (BoneAttachment3D) — enough to develop and test the motion; it is not a look and never ships
## as one. Proportions follow the votive sculpt (head top ~1.75, hem ~-4.1, faces +Z, her left
## hand at +X), so the layout reads the same once the real rig lands.

## Bone: [name, parent, rest position in model space]. Rest rotations are identity.
const BONES: Array = [
	["root", "", Vector3(0.0, -0.35, 0.0)],
	["hips", "root", Vector3(0.0, -0.35, 0.0)],
	["spine", "hips", Vector3(0.0, -0.06, 0.0)],
	["chest", "spine", Vector3(0.0, 0.36, 0.0)],
	["neck", "chest", Vector3(0.0, 0.98, -0.02)],
	["head", "neck", Vector3(0.0, 1.16, 0.0)],
	["skirt.0", "hips", Vector3(0.0, -0.42, 0.0)],
	["skirt.1", "skirt.0", Vector3(0.0, -1.66, 0.04)],
	["skirt.2", "skirt.1", Vector3(0.0, -2.9, 0.08)],
]
## Arm chain of the left side (the right one is mirrored in X).
const ARM_L: Array = [
	["clavicle.L", "chest", Vector3(0.05, 0.9, 0.03)],
	["upper_arm.L", "clavicle.L", Vector3(0.31, 0.92, -0.01)],
	["forearm.L", "upper_arm.L", Vector3(0.39, 0.33, 0.03)],
	["hand.L", "forearm.L", Vector3(0.43, -0.18, 0.12)],
]
## Fingers of the left hand: [name, base, direction] (two segments each: SEG lengths).
const FINGERS_L: Array = [
	["thumb", Vector3(0.425, -0.215, 0.155), Vector3(0.05, -0.6, 0.8)],
	["index", Vector3(0.445, -0.285, 0.148), Vector3(0.02, -1.0, 0.12)],
	["middle", Vector3(0.448, -0.292, 0.125), Vector3(0.02, -1.0, 0.03)],
	["ring", Vector3(0.446, -0.286, 0.103), Vector3(0.02, -1.0, -0.06)],
	["little", Vector3(0.442, -0.272, 0.084), Vector3(0.02, -1.0, -0.14)],
]
const SEG: Array[float] = [0.052, 0.042]
const SKIRT_END := Vector3(0.0, -4.1, 0.12)
const HEAD_TOP := 1.74


## Node3D "MikuMannequin" with a Skeleton3D child named "Skeleton3D" and its segments.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "MikuMannequin"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	var rest_pos := {}
	for b in all_bones():
		var parent: String = b[1]
		var i := skel.add_bone(b[0])
		var p: Vector3 = b[2]
		rest_pos[b[0]] = p
		if parent != "":
			var pi := skel.find_bone(parent)
			skel.set_bone_parent(i, pi)
			skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, p - (rest_pos[parent] as Vector3)))
		else:
			skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, p))
	skel.reset_bone_poses()
	_dress(skel, rest_pos)
	return root


## Every bone [name, parent, rest model position] in parent-first order.
static func all_bones() -> Array:
	var out: Array = BONES.duplicate(true)
	for side: String in ["L", "R"]:
		var sx := 1.0 if side == "L" else -1.0
		for a in ARM_L:
			var n := String(a[0]).replace(".L", "." + side)
			var par := String(a[1]).replace(".L", "." + side)
			var p: Vector3 = a[2]
			out.append([n, par, Vector3(p.x * sx, p.y, p.z)])
		for f in FINGERS_L:
			var base: Vector3 = f[1]
			var dir: Vector3 = (f[2] as Vector3).normalized()
			base.x *= sx
			dir.x *= sx
			var parent: String = "hand." + side
			var at := base
			for k in SEG.size():
				var n2 := "%s.%s.%d" % [f[0], side, k]
				out.append([n2, parent, at])
				parent = n2
				at += dir * SEG[k]
	return out


## Primitive segments on BoneAttachment3D nodes (rigid: the stand-in has no skin).
static func _dress(skel: Skeleton3D, rest: Dictionary) -> void:
	var mat := LivingMaterials.get_material(&"body")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Palette.NEBULA.darkened(0.35)
	dark.roughness = 0.6
	dark.rim_enabled = true
	dark.rim = 0.7
	var mark := StandardMaterial3D.new()
	mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.albedo_color = Palette.GOLD
	mark.emission_enabled = true
	mark.emission = Palette.GOLD
	mark.emission_energy_multiplier = 2.5
	# Torso masses.
	_blob(skel, "hips", rest, Vector3(0.0, 0.02, 0.0), Vector3(0.25, 0.2, 0.18), mat)
	_blob(skel, "spine", rest, Vector3(0.0, 0.2, 0.0), Vector3(0.165, 0.27, 0.13), mat)
	_blob(skel, "chest", rest, Vector3(0.0, 0.3, 0.0), Vector3(0.235, 0.3, 0.155), mat)
	_blob(skel, "chest", rest, Vector3(0.075, 0.22, 0.09), Vector3(0.085, 0.08, 0.075), mat)
	_blob(skel, "chest", rest, Vector3(-0.075, 0.22, 0.09), Vector3(0.085, 0.08, 0.075), mat)
	_seg(skel, "neck", rest, rest["neck"], rest["head"] + Vector3(0, 0.05, 0), 0.052, mat)
	_blob(skel, "head", rest, Vector3(0.0, 0.25, 0.025), Vector3(0.155, 0.205, 0.175), mat)
	# Hair mass (back of the head) and the brow mark: they make the facing readable.
	_blob(skel, "head", rest, Vector3(0.0, 0.33, -0.09), Vector3(0.18, 0.19, 0.17), dark)
	_blob(skel, "head", rest, Vector3(0.0, 0.42, -0.24), Vector3(0.11, 0.11, 0.13), dark)
	_blob(skel, "head", rest, Vector3(0.0, 0.31, 0.19), Vector3(0.018, 0.018, 0.012), mark)
	# Skirt: three flaring cones.
	var skirt_r: Array[float] = [0.25, 0.52, 0.76, 0.98]
	var ends: Array[Vector3] = [rest["skirt.1"], rest["skirt.2"], SKIRT_END]
	for k in 3:
		var bn := "skirt.%d" % k
		_cone(skel, bn, rest, rest[bn], ends[k], skirt_r[k], skirt_r[k + 1], mat)
	for side: String in ["L", "R"]:
		_seg(skel, "clavicle." + side, rest, rest["clavicle." + side], rest["upper_arm." + side], 0.045, mat)
		_seg(skel, "upper_arm." + side, rest, rest["upper_arm." + side], rest["forearm." + side], 0.05, mat)
		_seg(skel, "forearm." + side, rest, rest["forearm." + side], rest["hand." + side], 0.04, mat)
		var hand: Vector3 = rest["hand." + side]
		var mid: Vector3 = rest["middle.%s.0" % side]
		var palm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.026, 1.0, 0.075)
		palm.mesh = box
		palm.material_override = mat
		var att := _attachment(skel, "hand." + side)
		var d := mid - hand
		palm.transform = Transform3D(_basis_y(d).scaled_local(Vector3(1.0, d.length(), 1.0)), d * 0.5)
		att.add_child(palm)
		for f in FINGERS_L:
			for k in SEG.size():
				var bn2 := "%s.%s.%d" % [f[0], side, k]
				var a: Vector3 = rest[bn2]
				var dir: Vector3 = (f[2] as Vector3).normalized()
				if side == "R":
					dir.x = -dir.x
				_seg(skel, bn2, rest, a, a + dir * SEG[k], 0.0115 if k == 0 else 0.0105, mat)


static func _attachment(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = "Att_" + bone.replace(".", "_")
	skel.add_child(att)
	att.bone_name = bone
	return att


static func _blob(skel: Skeleton3D, bone: String, rest: Dictionary, offset: Vector3, radii: Vector3,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	mi.mesh = s
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_scale(radii), offset)
	_attachment(skel, bone).add_child(mi)


static func _seg(skel: Skeleton3D, bone: String, rest: Dictionary, a: Vector3, b: Vector3, radius: float,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf((b - a).length() + radius * 2.0, radius * 2.0 + 0.001)
	c.radial_segments = 12
	c.rings = 4
	mi.mesh = c
	mi.material_override = mat
	var origin: Vector3 = rest[bone]
	mi.transform = Transform3D(_basis_y(b - a), (a + b) * 0.5 - origin)
	_attachment(skel, bone).add_child(mi)


static func _cone(skel: Skeleton3D, bone: String, rest: Dictionary, a: Vector3, b: Vector3, r_top: float,
		r_bottom: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = (b - a).length()
	c.radial_segments = 28
	c.rings = 2
	c.cap_top = false
	c.cap_bottom = false
	mi.mesh = c
	mi.material_override = mat
	var origin: Vector3 = rest[bone]
	# The cylinder's +Y points to its top: from b (bottom) to a (top).
	mi.transform = Transform3D(_basis_y(a - b), (a + b) * 0.5 - origin)
	_attachment(skel, bone).add_child(mi)


## Basis whose Y axis points along `d`.
static func _basis_y(d: Vector3) -> Basis:
	var y := d.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
