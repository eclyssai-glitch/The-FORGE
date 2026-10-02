extends SceneTree
## SPIKE probe 0: semantics of manual modes and pose persistence.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var body := NCRig.build_body()
	root.add_child(body)
	var sk: Skeleton3D = body.get_node("Skeleton3D")
	print("bones=", sk.get_bone_count())
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = Vector3(1.0, 1.6, 1.0)
	var look := LookAtModifier3D.new()
	sk.add_child(look)
	look.bone_name = "head"
	look.target_node = look.get_path_to(target)
	sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var h := sk.find_bone("head")
	print("relative default=", look.relative, " forward_axis=", look.forward_axis, " primary_rot_axis=", look.primary_rotation_axis)
	print("before advance pose=", sk.get_bone_pose_rotation(h), " gz=", sk.get_bone_global_pose(h).basis.z)
	var got := []
	sk.skeleton_updated.connect(func() -> void: got.append(sk.get_bone_global_pose(h).basis.z))
	look.modification_processed.connect(func() -> void: print("  modification_processed: pose=", sk.get_bone_pose_rotation(h), " gz=", sk.get_bone_global_pose(h).basis.z))
	sk.advance(1.0 / 30.0)
	print("after advance(sync) pose=", sk.get_bone_pose_rotation(h), " gz=", sk.get_bone_global_pose(h).basis.z, " updated_signals=", got.size())
	await process_frame
	print("after 1 frame pose=", sk.get_bone_pose_rotation(h), " gz=", sk.get_bone_global_pose(h).basis.z, " updated_signals=", got.size(), " ", got)
	await process_frame
	print("after 2 frames gz=", sk.get_bone_global_pose(h).basis.z, " signals=", got.size())
	var dir := (target.global_position - sk.get_bone_global_pose(h).origin).normalized()
	print("wanted dir=", dir)
	quit()
