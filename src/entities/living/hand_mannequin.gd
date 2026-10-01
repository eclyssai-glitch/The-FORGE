class_name HandMannequin
extends RefCounted
## DEVELOPMENT STAND-IN for the puppet hand rig (Loop 5). Owner: animator. Used by PuppetHand
## ONLY when the procedural-modeler's `HandRig.build(side)` does not exist in the project
## (docs/ANIMATION.md, "Living — integration"). Skeleton3D with the contract's bones `wrist, palm,
## thumb/index/middle/ring/little.0-2` and rigid primitive segments; palm down, fingers along +Z,
## middle fingertip ~2 units from the wrist (PuppetHand rescales any rig to HAND_LENGTH).

## Right hand (thumb at +X); the left one is mirrored in X.
## [finger, base, direction, segment lengths, radius]
const FINGERS_R: Array = [
	["thumb", Vector3(0.3, -0.06, 0.28), Vector3(0.75, -0.12, 0.65), [0.36, 0.3, 0.24], 0.1],
	["index", Vector3(0.27, 0.0, 0.95), Vector3(0.06, 0.0, 1.0), [0.45, 0.28, 0.21], 0.082],
	["middle", Vector3(0.09, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), [0.5, 0.3, 0.22], 0.085],
	["ring", Vector3(-0.09, 0.0, 0.96), Vector3(-0.04, 0.0, 1.0), [0.46, 0.28, 0.2], 0.08],
	["little", Vector3(-0.26, -0.01, 0.87), Vector3(-0.1, 0.0, 1.0), [0.36, 0.22, 0.17], 0.07],
]
const WRIST := Vector3.ZERO
const PALM := Vector3(0.0, 0.0, 0.18)


static func build(left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "HandMannequin" + ("L" if left else "R")
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	var sx := -1.0 if left else 1.0
	var w := skel.add_bone("wrist")
	skel.set_bone_rest(w, Transform3D(Basis.IDENTITY, WRIST))
	var p := skel.add_bone("palm")
	skel.set_bone_parent(p, w)
	skel.set_bone_rest(p, Transform3D(Basis.IDENTITY, PALM - WRIST))
	var segs_at := {}
	for f in FINGERS_R:
		var base: Vector3 = f[1]
		base.x *= sx
		var dir: Vector3 = (f[2] as Vector3).normalized()
		dir.x *= sx
		var parent := p
		var parent_pos := PALM
		var at := base
		var lens: Array = f[3]
		for k in lens.size():
			var b := skel.add_bone("%s.%d" % [f[0], k])
			skel.set_bone_parent(b, parent)
			skel.set_bone_rest(b, Transform3D(Basis.IDENTITY, at - parent_pos))
			segs_at["%s.%d" % [f[0], k]] = [at, at + dir * float(lens[k]), float(f[4]) * (1.0 - 0.12 * k)]
			parent = b
			parent_pos = at
			at += dir * float(lens[k])
	skel.reset_bone_poses()
	var mat := LivingMaterials.get_material(&"hand")
	# Palm (an ellipsoid slab) and a short wrist that fades into the light.
	_ellipsoid(skel, "palm", PALM, Vector3(0.0, -0.01, 0.42), Vector3(0.38, 0.11, 0.52), mat)
	_capsule(skel, "wrist", WRIST, Vector3(0.0, 0.0, -0.55), Vector3(0.0, 0.0, 0.2), 0.2, mat)
	for k: String in segs_at:
		var s: Array = segs_at[k]
		_capsule(skel, k, s[0], s[0], s[1], s[2], mat)
	return root


static func _att(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = "Att_" + bone.replace(".", "_")
	skel.add_child(att)
	att.bone_name = bone
	return att


static func _capsule(skel: Skeleton3D, bone: String, origin: Vector3, a: Vector3, b: Vector3, r: float,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = (b - a).length() + r * 2.0
	c.radial_segments = 14
	c.rings = 4
	mi.mesh = c
	mi.material_override = mat
	mi.transform = Transform3D(MikuMannequin._basis_y(b - a), (a + b) * 0.5 - origin)
	_att(skel, bone).add_child(mi)


static func _ellipsoid(skel: Skeleton3D, bone: String, origin: Vector3, center: Vector3, radii: Vector3,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	mi.mesh = s
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_scale(radii), center - origin)
	_att(skel, bone).add_child(mi)
