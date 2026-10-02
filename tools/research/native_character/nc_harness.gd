class_name NCHarness
extends RefCounted
## SPIKE — test harness around one rig: manual AnimationTree + manual Skeleton3D modifiers, and a
## snapshot of the POST-MODIFIER global poses taken in `skeleton_updated` (the only moment the
## modifier output exists: Godot 4.7.2 restores the pre-modifier pose after the update).

var root: Node3D
var sk: Skeleton3D
var tree: AnimationTree
var snap: Array[Transform3D] = []
var updates := 0


func _init(rig_root: Node3D) -> void:
	root = rig_root
	sk = rig_root.get_node("Skeleton3D")
	snap.resize(sk.get_bone_count())
	sk.skeleton_updated.connect(_on_updated)
	sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL


func _on_updated() -> void:
	updates += 1
	for i in range(sk.get_bone_count()):
		snap[i] = sk.get_bone_global_pose(i)


func g(bone: String) -> Transform3D:
	return snap[sk.find_bone(bone)]


## World-space (skeleton global transform applied).
func world(bone: String) -> Transform3D:
	return sk.global_transform * g(bone)


func add_tree(tree_root: AnimationRootNode, lib: AnimationLibrary) -> AnimationTree:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.add_animation_library(&"", lib)
	tree.tree_root = tree_root
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree


## One frame: tree (if any) then modifiers; the caller awaits a process frame afterwards.
func advance(dt: float) -> void:
	if tree != null:
		tree.advance(dt)
	sk.advance(dt)


static func angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))
