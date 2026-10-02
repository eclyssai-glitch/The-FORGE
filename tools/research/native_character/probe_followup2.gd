extends SceneTree
## SPIKE probe 3: pole-less IK failure scope, Add2 sync, spring bones vs animated pose, iterative IK.
const DT := 1.0 / 30.0


func _initialize() -> void:
	_run.call_deferred()


func _rig() -> NCHarness:
	var body := NCRig.build_body()
	root.add_child(body)
	return NCHarness.new(body)


func _frame(h: NCHarness, dt: float = DT) -> void:
	h.advance(dt)
	await process_frame


func _node(h: NCHarness, p: Vector3) -> Node3D:
	var n := Node3D.new()
	h.root.add_child(n)
	n.position = p
	return n


func _run() -> void:
	# 1. pole-less TwoBoneIK3D: does it break OTHER modifiers too? does a pole DIRECTION suffice?
	for mode in ["none", "direction_vector", "direction_enum"]:
		var h := _rig()
		var look_t := _node(h, Vector3(2, 1.7, 1))
		var look := LookAtModifier3D.new()
		h.sk.add_child(look)
		look.bone_name = "head"
		look.target_node = look.get_path_to(look_t)
		var t := _node(h, Vector3(-0.35, 1.25, 0.35))
		var ik := TwoBoneIK3D.new()
		h.sk.add_child(ik)
		ik.setting_count = 1
		ik.set_root_bone_name(0, "upper_arm.R")
		ik.set_middle_bone_name(0, "forearm.R")
		ik.set_end_bone_name(0, "hand.R")
		ik.set_target_node(0, ik.get_path_to(t))
		if mode == "direction_vector":
			ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
			ik.set_pole_direction_vector(0, Vector3(-1, 0, -1))
		elif mode == "direction_enum":
			ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z)
		for i in range(3):
			await _frame(h)
		print("R pole mode=%s updates=%d ik_err=%.4f head_yaw=%.1f" % [mode, h.updates,
				h.world("hand.R").origin.distance_to(t.position), rad_to_deg(atan2(h.g("head").basis.z.x, h.g("head").basis.z.z))])
		h.root.queue_free()
		await process_frame
	# 2. Add2 with sync=false vs true: does the zero-weight input keep its clock?
	for sync in [false, true]:
		var h := _rig()
		var lib := AnimationLibrary.new()
		lib.add_animation(&"breath", NCPoses.breath(h.sk))
		lib.add_animation(&"calm", NCPoses.body_states(h.sk)[&"calm"])
		var bt := AnimationNodeBlendTree.new()
		var c := AnimationNodeAnimation.new()
		c.animation = &"calm"
		bt.add_node(&"calm", c)
		var b := AnimationNodeAnimation.new()
		b.animation = &"breath"
		bt.add_node(&"breath", b)
		var add := AnimationNodeAdd2.new()
		add.sync = sync
		bt.add_node(&"add", add)
		bt.connect_node(&"add", 0, &"calm")
		bt.connect_node(&"add", 1, &"breath")
		bt.connect_node(&"output", 0, &"add")
		var tree := h.add_tree(bt, lib)
		tree.set("parameters/add/add_amount", 0.0)
		for i in range(15):
			tree.advance(DT)
		tree.set("parameters/add/add_amount", 1.0)
		tree.advance(0.0)
		var with_b := h.sk.get_bone_pose_rotation(h.sk.find_bone("chest")).get_euler().x
		print("R Add2 sync=%s: after 0.5 s at amount 0, switching to 1 -> chest x=%.4f (calm -0.05 + breath peak -0.055 = -0.105 if the breath clock ran)" % [sync, with_b])
		h.root.queue_free()
		await process_frame
	# 3. SpringBone over an ANIMATED skirt: does the spring settle on the animated pose or on rest?
	var h3 := _rig()
	var lib3 := AnimationLibrary.new()
	var kick := Animation.new()
	kick.length = 1.0
	var tr := kick.add_track(Animation.TYPE_ROTATION_3D)
	kick.track_set_path(tr, "Skeleton3D:skirt.f.0")
	kick.rotation_track_insert_key(tr, 0.0, Quaternion.from_euler(Vector3(-0.5, 0, 0)))
	lib3.add_animation(&"kick", kick)
	var an := AnimationNodeAnimation.new()
	an.animation = &"kick"
	h3.add_tree(an, lib3)
	var sb := SpringBoneSimulator3D.new()
	h3.sk.add_child(sb)
	sb.setting_count = 1
	sb.set_root_bone_name(0, "skirt.f.0")
	sb.set_end_bone_name(0, "skirt.f.2")
	sb.set_extend_end_bone(0, true)
	sb.set_end_bone_length(0, 0.2)
	sb.set_stiffness(0, 2.0)
	sb.set_drag(0, 0.5)
	sb.set_gravity(0, 0.0)
	for i in range(60):
		await _frame(h3)
	var y0 := h3.g("skirt.f.0").basis.y
	print("R SpringBone over animated root bone (anim rotates skirt.f.0 by -0.5 rad x): settled skirt.f.0 y=", y0.snapped(Vector3.ONE * 0.001),
			" (rest dir (0,-0.6,0.22)n; animated dir rotated back/up)")
	h3.root.queue_free()
	await process_frame
	# 4. Iterative IK on the 3-joint arm clavicle->hand: error, iterations, determinism flag.
	for cfg in [["CCDIK3D", 4, 2.0], ["CCDIK3D", 16, 30.0], ["FABRIK3D", 16, 30.0], ["JacobianIK3D", 16, 30.0]]:
		var cls: String = cfg[0]
		var h := _rig()
		var t := _node(h, Vector3(-0.3, 1.45, 0.4))
		var ik: IterateIK3D = ClassDB.instantiate(cls)
		h.sk.add_child(ik)
		ik.setting_count = 1
		ik.set_root_bone_name(0, "clavicle.R")
		ik.set_end_bone_name(0, "hand.R")
		ik.set_target_node(0, ik.get_path_to(t))
		ik.deterministic = true
		ik.max_iterations = int(cfg[1])
		ik.angular_delta_limit = deg_to_rad(float(cfg[2]))
		var errs := []
		for i in range(6):
			await _frame(h)
			errs.append("%.4f" % h.world("hand.R").origin.distance_to(t.position))
		t.position = Vector3(-0.55, 1.2, 0.2)
		for i in range(4):
			await _frame(h)
			errs.append("%.4f" % h.world("hand.R").origin.distance_to(t.position))
		var elbow := h.world("forearm.R").origin
		print("R %s clavicle.R->hand.R joints=%d max_iter=%d delta_limit=%.0f err per frame=%s elbow=%s updates=%d" % [cls, ik.get_joint_count(0), ik.max_iterations, float(cfg[2]), errs, elbow.snapped(Vector3.ONE * 0.01), h.updates])
		h.root.queue_free()
		await process_frame
	print("R done")
	quit()
