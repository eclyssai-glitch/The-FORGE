class_name RigData
extends RefCounted
## A baked skinned rig (tools/sculpt/rig_bake.py): skeleton + skin weights over a sculpture.
##
## Files (versioned in assets/meshes/): `<name>.json` = skeleton (bone names, parents, global
## rest frames, conventions, stats) and `<name>.skin.json` = arrays (zlib + base64, little
## endian: float32 vertex/normal/color/weights, int32 bones/index; faces already clockwise).
## Both are plain JSON, so they ship in the export like the other mesh metadata.
##
## Bone frames (global rest bases): +Y along the bone, +Z towards the side the joint flexes to,
## +X = Y x Z; a positive rotation about local +X flexes. Left/right (and the mirrored hand)
## are mirror images with X flipped: +X flexes on both sides, Y/Z rotations are mirrored.
##
## Build once: `load_rig` caches the data, `mesh()`/`skin()` are built once and shared by every
## instance (each instance only owns its Skeleton3D). Nothing here runs per frame except what
## the caller does with the skeleton.

const MESH_DIR := "res://assets/meshes/"
const SKELETON_NODE := "Skeleton3D"
const MESH_NODE := "Mesh"

static var _cache := {}

var rig_name := ""
var meta: Dictionary = {}
var bone_names := PackedStringArray()
var bone_parents := PackedInt32Array()
var bone_sides := PackedInt32Array()
var bone_deform: Array[bool] = []
var global_rests: Array[Transform3D] = []
var tails := PackedVector3Array()
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var indices := PackedInt32Array()
var mirrored := false
var _index := {}
var _mesh: ArrayMesh
var _skin: Skin


## Loads (once) `res://assets/meshes/<rig_name>.json` + its skin payload. null on failure.
static func load_rig(p_name: String) -> RigData:
	if _cache.has(p_name):
		return _cache[p_name]
	var d := RigData.new()
	if not d._load(p_name):
		return null
	_cache[p_name] = d
	return d


## The same rig mirrored through the XY plane (z -> -z): a left hand becomes a right hand with
## the same orientation convention. Bones keep their names. Cached per source rig.
func mirror_z() -> RigData:
	var key := rig_name + "#mirror_z"
	if _cache.has(key):
		return _cache[key]
	var d := RigData.new()
	d.rig_name = key
	d.meta = meta
	d.mirrored = true
	d.bone_names = bone_names
	d.bone_parents = bone_parents
	d.bone_sides = bone_sides
	d.bone_deform = bone_deform
	d._index = _index
	var m := Vector3(1.0, 1.0, -1.0)
	for t in global_rests:
		# M B N with M = diag(1, 1, -1) (world mirror) and N = diag(-1, 1, 1) (flip local X):
		# a proper rotation whose +X still flexes
		var b := Basis(-(t.basis.x * m), t.basis.y * m, t.basis.z * m)
		d.global_rests.append(Transform3D(b, t.origin * m))
	d.tails = PackedVector3Array()
	for p in tails:
		d.tails.append(p * m)
	d.vertices = PackedVector3Array()
	d.vertices.resize(vertices.size())
	d.normals = PackedVector3Array()
	d.normals.resize(normals.size())
	for i in vertices.size():
		d.vertices[i] = vertices[i] * m
		d.normals[i] = normals[i] * m
	d.colors = colors
	d.bones = bones
	d.weights = weights
	d.indices = indices.duplicate()
	for t in range(0, d.indices.size(), 3):  # mirroring flips the winding
		var tmp := d.indices[t + 1]
		d.indices[t + 1] = d.indices[t + 2]
		d.indices[t + 2] = tmp
	_cache[key] = d
	return d


func _load(p_name: String) -> bool:
	rig_name = p_name
	var path := MESH_DIR + p_name + ".json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("RigData: cannot read %s" % path)
		return false
	meta = parsed
	for b: Dictionary in meta["bones"]:
		_index[String(b["name"])] = bone_names.size()
		bone_names.append(String(b["name"]))
		bone_parents.append(int(b["parent"]))
		bone_sides.append(int(b["side"]))
		bone_deform.append(bool(b["deform"]))
		var basis := Basis(_v3(b["basis_x"]), _v3(b["basis_y"]), _v3(b["basis_z"])).orthonormalized()
		global_rests.append(Transform3D(basis, _v3(b["head"])))
		tails.append(_v3(b["tail"]))
	var skin_path := MESH_DIR + String(meta["skin_file"])
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(skin_path))
	if not (payload is Dictionary):
		push_error("RigData: cannot read %s" % skin_path)
		return false
	var arrays: Dictionary = payload["arrays"]
	vertices = _blob(arrays["vertex"]).to_vector3_array()
	normals = _blob(arrays["normal"]).to_vector3_array()
	colors = _blob(arrays["color"]).to_color_array()
	bones = _blob(arrays["bones"]).to_int32_array()
	weights = _blob(arrays["weights"]).to_float32_array()
	indices = _blob(arrays["index"]).to_int32_array()
	var n := vertices.size()
	if n != int(payload["vertex_count"]) or normals.size() != n or colors.size() != n \
			or bones.size() != 4 * n or weights.size() != 4 * n \
			or indices.size() != int(payload["index_count"]):
		push_error("RigData: inconsistent arrays in %s" % skin_path)
		return false
	return true


static func _blob(entry: Dictionary) -> PackedByteArray:
	var comp := Marshalls.base64_to_raw(String(entry["zlib_b64"]))
	return comp.decompress(int(entry["bytes"]), FileAccess.COMPRESSION_DEFLATE)


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func bone_count() -> int:
	return bone_names.size()


## Bone index by name (-1 when absent).
func bone_index(p_name: String) -> int:
	return int(_index.get(p_name, -1))


## Rest transform of bone `i` relative to its parent (what Skeleton3D stores).
func local_rest(i: int) -> Transform3D:
	var p := bone_parents[i]
	return global_rests[i] if p < 0 else global_rests[p].affine_inverse() * global_rests[i]


## The skinned surface (shared by all instances; built on first use).
func mesh() -> ArrayMesh:
	if _mesh == null:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vertices
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		arr[Mesh.ARRAY_INDEX] = indices
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_mesh.resource_name = rig_name
	return _mesh


## Bind poses: bind i = inverse global rest of bone i (bone indices == bind indices).
func skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		for i in bone_count():
			_skin.add_bind(i, global_rests[i].affine_inverse())
	return _skin


func make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = SKELETON_NODE
	for i in bone_count():
		sk.add_bone(bone_names[i])
	for i in bone_count():
		if bone_parents[i] >= 0:
			sk.set_bone_parent(i, bone_parents[i])
		sk.set_bone_rest(i, local_rest(i))
	sk.reset_bone_poses()
	return sk


## Node3D (named `node_name`) > Skeleton3D "Skeleton3D" > MeshInstance3D "Mesh" (skinned).
func instantiate(node_name: String, material: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var sk := make_skeleton()
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = MESH_NODE
	mi.mesh = mesh()
	mi.skin = skin()
	if material != null:
		mi.material_override = material
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return root


# ------------------------------------------------------------------ utilities (any skeleton)

## The Skeleton3D of a rig built by `instantiate` (or the node itself when it is one).
static func skeleton_of(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	if node == null:
		return null
	return node.get_node_or_null(SKELETON_NODE) as Skeleton3D


static func mesh_instance_of(node: Node) -> MeshInstance3D:
	var sk := skeleton_of(node)
	return null if sk == null else sk.get_node_or_null(MESH_NODE) as MeshInstance3D


## Sets the pose rotation of `bone` to its rest rotation followed by a local rotation
## (`euler` = radians about the bone's own X, Y, Z, applied in Godot's default YXZ order).
## +X flexes (see the class doc). Position/scale of the pose are left untouched.
static func pose_local(sk: Skeleton3D, bone: int, euler: Vector3) -> void:
	var rest := sk.get_bone_rest(bone).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, rest * Quaternion.from_euler(euler))


## Rotates `bone` by `angle` rad about `axis` given in SKELETON space (pivot = the bone's joint),
## on top of its current pose; children follow. Handy for look-at / reach chains.
static func rotate_global(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	var p := sk.get_bone_parent(bone)
	var parent_g := Basis.IDENTITY if p < 0 else _global_basis(sk, p)
	var g := parent_g * Basis(sk.get_bone_pose_rotation(bone))
	var ng := Basis(axis.normalized(), angle) * g
	sk.set_bone_pose_rotation(bone, (parent_g.inverse() * ng).get_rotation_quaternion())


static func _global_basis(sk: Skeleton3D, bone: int) -> Basis:
	var b := Basis(sk.get_bone_pose_rotation(bone))
	var p := sk.get_bone_parent(bone)
	while p >= 0:
		b = Basis(sk.get_bone_pose_rotation(p)) * b
		p = sk.get_bone_parent(p)
	return b


## BoneAttachment3D on `bone` (added under the skeleton) holding `node` (local transform kept).
static func attach(rig: Node, bone: String, node: Node3D = null) -> BoneAttachment3D:
	var sk := skeleton_of(rig)
	var ba := BoneAttachment3D.new()
	ba.name = "Attach_" + bone.replace(".", "_")
	sk.add_child(ba)
	ba.bone_name = bone
	if node != null:
		ba.add_child(node)
	return ba


## Global (skeleton-space) pose of every bone, composed from the local poses (parents first).
static func global_poses(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var local := sk.get_bone_pose(i)
		out.append(local if p < 0 else out[p] * local)
	return out


## CPU linear-blend skinning of the rest vertices with the given global poses (tests/tools,
## never per frame): v' = sum w * (pose * rest^-1) * v. `stride` samples every n-th vertex.
func skin_vertices(poses: Array[Transform3D], stride: int = 1) -> PackedVector3Array:
	var k: Array[Transform3D] = []
	for i in bone_count():
		k.append(poses[i] * global_rests[i].affine_inverse())
	var out := PackedVector3Array()
	for v in range(0, vertices.size(), stride):
		var p := vertices[v]
		var acc := Vector3.ZERO
		for j in 4:
			var w := weights[4 * v + j]
			if w > 0.0:
				acc += w * (k[bones[4 * v + j]] * p)
		out.append(acc)
	return out
