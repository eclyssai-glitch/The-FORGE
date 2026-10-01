class_name MikuRig
extends RefCounted
## MIKU's skinned body (Loop 5): the sculpture assets/meshes/miku_body.obj on a skeleton baked by
## tools/sculpt/rig_bake.py (assets/meshes/miku_rig.json + miku_rig.skin.json). The rest pose IS
## the sculpted pose. The current sculpture is a technical mannequin: the skeleton names and
## conventions below are the contract a future model must follow (docs/PROCEDURAL.md, "Rig").
##
## Tree: Node3D "MikuRig" > Skeleton3D "Skeleton3D" > MeshInstance3D "Mesh" (skin, material set by
## the caller). Mesh frame = the static sculpture's: +Y up, +Z front, origin = waist centre,
## her left = +X (.L bones).
##
## Bones (parent first): root > hips > spine > chest > {ribcage, neck > head > hair_root,
## clavicle.L/R > upper_arm > forearm > hand > {thumb, index, middle, ring, little}.0 > .1 > .tip}
## and hips > skirt.0 > skirt.1 > skirt.2. Non-deforming: root, chest (its skin is carried by
## ribcage, so chest_volume can scale it without scaling the children), hair_root and *.tip
## (attachment points). Rotate bones with RigData.pose_local (+X flexes: nod forward, elbow
## bends, fingers curl, skirt swings forward; for .R bones negate Y/Z angles to mirror a .L motion).

const RIG := "miku_rig"
const NODE_NAME := "MikuRig"

## Minimum bone set of the Loop 5 contract (docs/contracts/loop-05.md).
const CONTRACT_BONES: Array[String] = [
	"root", "hips", "spine", "chest", "neck", "head",
	"clavicle.L", "clavicle.R", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R",
	"hand.L", "hand.R",
	"thumb.0.L", "thumb.1.L", "thumb.0.R", "thumb.1.R",
	"index.0.L", "index.1.L", "index.0.R", "index.1.R",
	"middle.0.L", "middle.1.L", "middle.0.R", "middle.1.R",
	"ring.0.L", "ring.1.L", "ring.0.R", "ring.1.R",
	"skirt.0", "skirt.1", "skirt.2", "hair_root",
]
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "little"]

## appearance -> bones. Factors (1 = the sculpture). Applied to the bone REST (and the pose
## position/scale) so they survive reset_bone_poses and never fight pose rotations.
##   height          root: uniform scale (the whole figure about the waist origin)
##   shoulder_width  upper_arm.L/R: position along the clavicle x factor (shoulders move out)
##   neck_length     neck: moved up its axis by half the change; head: the other half (both seams
##                   of the neck stretch)
##   chest_volume    ribcage: scale (factor, 1, factor) about the chest centre (width and depth)
const APPEARANCE := {
	"height": {"min": 0.85, "max": 1.15, "default": 1.0},
	"shoulder_width": {"min": 0.9, "max": 1.15, "default": 1.0},
	"neck_length": {"min": 0.85, "max": 1.3, "default": 1.0},
	"chest_volume": {"min": 0.85, "max": 1.2, "default": 1.0},
}


static func data() -> RigData:
	return RigData.load_rig(RIG)


## A fresh MIKU instance (shares mesh and skin with every other instance).
static func build(material: Material = null) -> Node3D:
	var d := data()
	if d == null:
		return null
	var rig := d.instantiate(NODE_NAME, material)
	rig.set_meta(&"rig", RIG)
	return rig


static func get_skeleton(rig: Node) -> Skeleton3D:
	return RigData.skeleton_of(rig)


static func get_mesh_instance(rig: Node) -> MeshInstance3D:
	return RigData.mesh_instance_of(rig)


## Bone index by name in the rig (-1 if absent). Same index in every instance.
static func bone_index(bone: String) -> int:
	var d := data()
	return -1 if d == null else d.bone_index(bone)


## +1 for .L and centre bones, -1 for .R: multiply Y/Z rotation angles by it to mirror a motion.
static func side_sign(bone: String) -> float:
	return -1.0 if bone.ends_with(".R") else 1.0


## BoneAttachment3D following `bone` (e.g. "hair_root": +Y = the sculpted hair exit tangent, origin
## = the tip of the knot; build HairRibbons around Vector3.ZERO in that frame).
static func attach(rig: Node, bone: String, node: Node3D = null) -> BoneAttachment3D:
	return RigData.attach(rig, bone, node)


## Sculpture anchor (miku_body.json name: head_top, forehead, hair_root, palm_left, chest,
## gown_hem_center, ...) in skeleton space for the CURRENT pose; directions for *_normal/_tangent.
static func anchor(rig: Node, anchor_name: String) -> Vector3:
	var d := data()
	var sk := get_skeleton(rig)
	var a: Dictionary = d.meta["anchors_local"].get(anchor_name, {})
	if a.is_empty() or sk == null:
		return Vector3.ZERO
	var g := RigData.global_poses(sk)[d.bone_index(String(a["bone"]))]
	var loc := RigData._v3(a["local"])
	return (g.basis * loc).normalized() if String(a["kind"]) == "direction" else g * loc


## Clamped appearance values (missing keys = default).
static func clamp_appearance(appearance: Dictionary) -> Dictionary:
	var out := {}
	for key: String in APPEARANCE:
		var r: Dictionary = APPEARANCE[key]
		out[key] = clampf(float(appearance.get(key, r["default"])), float(r["min"]), float(r["max"]))
	return out


## Applies `appearance` (see APPEARANCE) to the rig's skeleton; returns the clamped values used.
## Idempotent (always relative to the baked rest); pose rotations are kept.
static func apply_appearance(rig: Node, appearance: Dictionary) -> Dictionary:
	var d := data()
	var sk := get_skeleton(rig)
	var v := clamp_appearance(appearance)
	if d == null or sk == null:
		return v
	var root := d.bone_index("root")
	var r0 := d.local_rest(root)
	_set_rest(sk, root, Transform3D(r0.basis.scaled_local(Vector3.ONE * float(v["height"])), r0.origin))
	for side in [".L", ".R"]:
		var ua := d.bone_index("upper_arm" + side)
		var t := d.local_rest(ua)
		_set_rest(sk, ua, Transform3D(t.basis, t.origin * float(v["shoulder_width"])))
	var neck := d.bone_index("neck")
	var head := d.bone_index("head")
	var tn := d.local_rest(neck)
	var th := d.local_rest(head)
	var grow := (float(v["neck_length"]) - 1.0) * 0.5
	var length := th.origin.length()
	_set_rest(sk, neck, Transform3D(tn.basis, tn.origin + tn.basis.y.normalized() * length * grow))
	_set_rest(sk, head, Transform3D(th.basis, th.origin * (1.0 + grow)))
	var rib := d.bone_index("ribcage")
	var tr := d.local_rest(rib)
	var c := float(v["chest_volume"])
	_set_rest(sk, rib, Transform3D(tr.basis.scaled_local(Vector3(c, 1.0, c)), tr.origin))
	return v


static func _set_rest(sk: Skeleton3D, bone: int, t: Transform3D) -> void:
	sk.set_bone_rest(bone, t)
	sk.set_bone_pose_position(bone, t.origin)
	sk.set_bone_pose_scale(bone, t.basis.get_scale())
