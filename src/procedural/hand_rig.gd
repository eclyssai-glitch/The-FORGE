class_name HandRig
extends RefCounted
## The generic angelic hand, skinned (Loop 5): hand_left.obj on the skeleton baked by
## tools/sculpt/rig_bake.py (assets/meshes/hand_rig.json + hand_rig.skin.json). ONE rig for any
## number of hands: every instance shares mesh and skin and owns only its Skeleton3D. The right
## hand is the mirror image (z -> -z) built once at runtime.
##
## Frame (both sides): fingers -> +X, palm faces +Y, origin = palm centre; thumb towards -Z on the
## LEFT hand and +Z on the RIGHT. Wrist->middle tip ~7 u (the giant scale; scale the node).
## Tree: Node3D "HandRig" > Skeleton3D "Skeleton3D" > MeshInstance3D "Mesh".
##
## Bones: wrist (root; the wrist joint, carries the forearm stump) > palm > {palm_center (anchor on
## the palm: +Y = palm normal, +Z = towards the fingers), thumb.0 (metacarpal) > thumb.1 > thumb.2 >
## thumb.tip, <finger>.0 (proximal) > .1 (middle) > .2 (distal) > .tip for index/middle/ring/little}.
## Rotate with RigData.pose_local: +X curls (both sides), Z spreads (mirrored on the right).

enum Side { LEFT, RIGHT }

const RIG := "hand_rig"
const NODE_NAME := "HandRig"
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "little"]
const CONTRACT_BONES: Array[String] = [
	"wrist", "palm",
	"thumb.0", "thumb.1", "thumb.2", "index.0", "index.1", "index.2",
	"middle.0", "middle.1", "middle.2", "ring.0", "ring.1", "ring.2",
	"little.0", "little.1", "little.2",
]


static func data(side: int = Side.LEFT) -> RigData:
	var d := RigData.load_rig(RIG)
	if d == null:
		return null
	return d.mirror_z() if side == Side.RIGHT else d


## A fresh hand of the given side (Side.LEFT / Side.RIGHT).
static func build(side: int, material: Material = null) -> Node3D:
	var d := data(side)
	if d == null:
		return null
	var rig := d.instantiate(NODE_NAME, material)
	rig.set_meta(&"rig", RIG)
	rig.set_meta(&"side", side)
	return rig


static func get_skeleton(rig: Node) -> Skeleton3D:
	return RigData.skeleton_of(rig)


static func get_mesh_instance(rig: Node) -> MeshInstance3D:
	return RigData.mesh_instance_of(rig)


static func bone_index(bone: String) -> int:
	var d := data()
	return -1 if d == null else d.bone_index(bone)


static func attach(rig: Node, bone: String, node: Node3D = null) -> BoneAttachment3D:
	return RigData.attach(rig, bone, node)


## Convenience pose: curls `finger` by `curl` (0 = sculpted, 1 ~ closed: radians per joint
## below) and spreads it by `spread` rad about the proximal bone's Z (towards the thumb side on
## the left; pass the same value on the right, the sign is handled here).
const CURL_ANGLES := {"thumb": [0.35, 0.6, 0.7], "index": [1.25, 1.45, 0.9],
	"middle": [1.25, 1.5, 0.9], "ring": [1.2, 1.5, 0.9], "little": [1.15, 1.45, 0.9]}


static func pose_finger(rig: Node, finger: String, curl: float, spread: float = 0.0, side: int = -1) -> void:
	var sk := get_skeleton(rig)
	if side < 0:
		side = int(rig.get_meta(&"side", Side.LEFT))
	var s := -1.0 if side == Side.RIGHT else 1.0
	var angles: Array = CURL_ANGLES[finger]
	for k in 3:
		var z := spread * s if k == 0 else 0.0
		RigData.pose_local(sk, sk.find_bone("%s.%d" % [finger, k]), Vector3(float(angles[k]) * curl, 0.0, z))
