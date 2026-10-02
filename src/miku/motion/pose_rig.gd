class_name PoseRig
extends RefCounted
## Procedural posing of a Skeleton3D in MODEL-SPACE terms (Loop 5). Owner: animator.
## Every bone gets a rotation expressed in the rig's model axes *as they were at rest* (+X her
## left, +Y up, +Z forward), whatever the bone's own local axes are: the local pose written to
## the skeleton is  rest_local · (rest_global⁻¹ · Q · rest_global).  That makes the layers
## independent of how the rig author oriented the bones (the procedural-modeler's rig or the
## development stand-in): "bow the chest" is a rotation about +X for any rig.
##
## Per frame: begin() -> set_rel()/set_abs() (layers) -> solve() (forward kinematics: accumulated
## rotations `acc` and posed model positions `pos`; a hook runs when a bone flagged with
## set_hook() is reached, after its position is known, so IK can use its parents' pose) ->
## write(). Arrays are allocated once; nothing is allocated per frame.
##   acc[b] = acc[parent] · rel[b]   (or the absolute rotation given by set_abs)
##   pos[b] = pos[parent] + scale[parent] · acc[parent] · (offset[b] · pos_scale[b])

var skeleton: Skeleton3D
var count := 0
var parent := PackedInt32Array()
## Bones in parent-first order.
var order := PackedInt32Array()
var rest_lrot: Array[Quaternion] = []
var rest_lpos := PackedVector3Array()
var rest_grot: Array[Quaternion] = []
var rest_gpos := PackedVector3Array()
## Rest offset from the parent (model space).
var offset := PackedVector3Array()

var rel: Array[Quaternion] = []
var acc: Array[Quaternion] = []
var pos := PackedVector3Array()
var absolute := PackedByteArray()
var abs_rot: Array[Quaternion] = []
## Uniform pose scale per bone (appearance) and multiplier of its offset from the parent.
var bone_scale := PackedFloat32Array()
var pos_scale := PackedFloat32Array()
var acc_scale := PackedFloat32Array()
## Extra translation of root bones (model space).
var root_offset := Vector3.ZERO
## True when this class writes pose scale/position for appearance (development stand-in). The
## real rig applies appearance to its own rests (MikuRig.apply_appearance): then only rotations
## (and the root's offset) are written.
var manage_scale := true

var _hook_bone := PackedByteArray()
var _hook: Callable


func _init(skel: Skeleton3D) -> void:
	skeleton = skel
	count = skel.get_bone_count()
	parent.resize(count)
	rest_lpos.resize(count)
	rest_gpos.resize(count)
	offset.resize(count)
	pos.resize(count)
	absolute.resize(count)
	bone_scale.resize(count)
	pos_scale.resize(count)
	acc_scale.resize(count)
	_hook_bone.resize(count)
	var depth := PackedInt32Array()
	depth.resize(count)
	for b in count:
		parent[b] = skel.get_bone_parent(b)
		rest_lrot.append(Quaternion.IDENTITY)
		rest_grot.append(Quaternion.IDENTITY)
		rel.append(Quaternion.IDENTITY)
		acc.append(Quaternion.IDENTITY)
		abs_rot.append(Quaternion.IDENTITY)
		bone_scale[b] = 1.0
		pos_scale[b] = 1.0
	_read_rest()
	for b in count:
		var d := 0
		var p := parent[b]
		while p >= 0:
			d += 1
			p = parent[p]
		depth[b] = d
	var idx: Array[int] = []
	for b in count:
		idx.append(b)
	idx.sort_custom(func(a: int, c: int) -> bool: return depth[a] < depth[c] or (depth[a] == depth[c] and a < c))
	order.resize(count)
	for i in count:
		order[i] = idx[i]
	begin()
	solve()


## Re-reads the skeleton's rests (after the rig changed them: MikuRig.apply_appearance).
func refresh_rest() -> void:
	_read_rest()


func _read_rest() -> void:
	for b in count:
		var lr := skeleton.get_bone_rest(b)
		rest_lrot[b] = lr.basis.get_rotation_quaternion()
		rest_lpos[b] = lr.origin
		var g := skeleton.get_bone_global_rest(b)
		rest_grot[b] = g.basis.get_rotation_quaternion()
		rest_gpos[b] = g.origin
	for b in count:
		offset[b] = rest_gpos[b] - (rest_gpos[parent[b]] if parent[b] >= 0 else Vector3.ZERO)


## Calls `hook.call(bone)` during solve() when `bone` is reached (its position known).
func set_hook(bone: int, hook: Callable) -> void:
	if bone < 0:
		return
	_hook_bone[bone] = 1
	_hook = hook


func begin() -> void:
	for b in count:
		rel[b] = Quaternion.IDENTITY
		absolute[b] = 0


## Rotation of `b` relative to its parent, in rest model axes.
func set_rel(b: int, q: Quaternion) -> void:
	if b >= 0:
		rel[b] = q


## Multiplies onto the relative rotation of `b` (layers add up).
func add_rel(b: int, q: Quaternion) -> void:
	if b >= 0:
		rel[b] = rel[b] * q


## Absolute (accumulated) model rotation of `b` relative to its rest orientation.
func set_abs(b: int, q: Quaternion) -> void:
	if b >= 0:
		absolute[b] = 1
		abs_rot[b] = q


func solve() -> void:
	for i in count:
		var b := order[i]
		var p := parent[b]
		if p >= 0:
			pos[b] = pos[p] + acc[p] * (offset[b] * pos_scale[b]) * acc_scale[p]
		else:
			pos[b] = rest_gpos[b] * pos_scale[b] + root_offset
		if _hook_bone[b] == 1 and _hook.is_valid():
			_hook.call(b)
		var pa := acc[p] if p >= 0 else Quaternion.IDENTITY
		acc[b] = abs_rot[b] if absolute[b] == 1 else pa * rel[b]
		acc_scale[b] = (acc_scale[p] if p >= 0 else 1.0) * bone_scale[b]


## Rotation of `b` relative to its parent after solve() (rest model axes).
func relative(b: int) -> Quaternion:
	var p := parent[b]
	return (acc[p].inverse() * acc[b]) if p >= 0 else acc[b]


## Writes the solved pose to the skeleton.
func write() -> void:
	for b in count:
		var q := relative(b)
		var g := rest_grot[b]
		skeleton.set_bone_pose_rotation(b, rest_lrot[b] * (g.inverse() * q * g))
		if parent[b] < 0:
			skeleton.set_bone_pose_position(b, rest_lpos[b] * pos_scale[b] + root_offset)
		elif manage_scale and pos_scale[b] != 1.0:
			skeleton.set_bone_pose_position(b, rest_lpos[b] * pos_scale[b])
		if manage_scale:
			var s := bone_scale[b]
			skeleton.set_bone_pose_scale(b, Vector3(s, s, s))


## Relative rotation of `b` in rest model axes for the local pose rotation the skeleton holds now
## (the inverse of write(): what the AnimationTree posed, in this class's terms).
func rel_from_skeleton(b: int) -> Quaternion:
	var g := rest_grot[b]
	return (g * (rest_lrot[b].inverse() * skeleton.get_bone_pose_rotation(b)) * g.inverse()).normalized()


## Model-space direction a rest-space direction of bone `b` points to now.
func dir_of(b: int, rest_dir: Vector3) -> Vector3:
	return acc[b] * rest_dir


## Model position of a point given in rest model coordinates attached to bone `b`.
func point_of(b: int, rest_point: Vector3) -> Vector3:
	return pos[b] + acc[b] * (rest_point - rest_gpos[b]) * acc_scale[b]
