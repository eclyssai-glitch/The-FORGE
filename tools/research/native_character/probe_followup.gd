extends SceneTree
## SPIKE probe 2: follow-ups of probe_semantics (anomalies isolated one at a time).
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


func _ik(h: NCHarness, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	h.sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upper_arm.R")
	ik.set_middle_bone_name(0, "forearm.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(target))
	if pole != null:
		ik.set_pole_node(0, ik.get_path_to(pole))
	return ik


func _run() -> void:
	# 1. TwoBoneIK3D with and without a pole node
	for use_pole in [true, false]:
		var h := _rig()
		var target := Node3D.new()
		h.root.add_child(target)
		target.position = Vector3(-0.35, 1.25, 0.35)
		var pole: Node3D = null
		if use_pole:
			pole = Node3D.new()
			h.root.add_child(pole)
			pole.position = Vector3(-0.6, 1.2, -0.6)
		var ik := _ik(h, target, pole)
		for i in range(3):
			await _frame(h)
		print("R IK pole=", use_pole, " updates=", h.updates, " err=", h.world("hand.R").origin.distance_to(target.position),
				" pole_direction=", ik.get_pole_direction(0))
		h.root.queue_free()
		await process_frame
	# 2. BoneAttachment3D after modifiers (with pole so IK works)
	var h2 := _rig()
	var t2 := Node3D.new()
	h2.root.add_child(t2)
	t2.position = Vector3(-0.35, 1.25, 0.35)
	var p2 := Node3D.new()
	h2.root.add_child(p2)
	p2.position = Vector3(-0.6, 1.2, -0.6)
	_ik(h2, t2, p2)
	var att := BoneAttachment3D.new()
	h2.sk.add_child(att)
	att.bone_name = "hand.R"
	var proc_read := Vector3.ZERO
	for i in range(3):
		await _frame(h2)
		proc_read = (h2.sk.global_transform * h2.sk.get_bone_global_pose(h2.sk.find_bone("hand.R"))).origin
	print("R read post-modifier hand.R: skeleton_updated snapshot=", h2.world("hand.R").origin.snapped(Vector3.ONE * 0.001),
			" BoneAttachment3D=", att.global_position.snapped(Vector3.ONE * 0.001),
			" get_bone_global_pose next frame=", proc_read.snapped(Vector3.ONE * 0.001), " target=", t2.position)
	h2.root.queue_free()
	await process_frame
	# 3. State machine start: transition advance_mode default and start()
	var h3 := _rig()
	var sm := AnimationNodeStateMachine.new()
	for s in [&"calm", &"frustrated"]:
		var an := AnimationNodeAnimation.new()
		an.animation = s
		sm.add_node(s, an)
	var st := AnimationNodeStateMachineTransition.new()
	print("R StateMachineTransition default advance_mode=", st.advance_mode, " (1=ENABLED needs travel/condition, 2=AUTO)")
	st.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"calm", st)
	var lib := AnimationLibrary.new()
	var poses := NCPoses.body_states(h3.sk)
	lib.add_animation(&"calm", poses[&"calm"])
	lib.add_animation(&"frustrated", poses[&"frustrated"])
	lib.add_animation(&"breath", NCPoses.breath(h3.sk))
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"state", sm)
	var br := AnimationNodeAnimation.new()
	br.animation = &"breath"
	bt.add_node(&"breath", br)
	var add := AnimationNodeAdd2.new()
	bt.add_node(&"add", add)
	bt.connect_node(&"add", 0, &"state")
	bt.connect_node(&"add", 1, &"breath")
	bt.connect_node(&"output", 0, &"add")
	var tree := h3.add_tree(bt, lib)
	var chest := h3.sk.find_bone("chest")
	tree.advance(0.0)
	var pb: AnimationNodeStateMachinePlayback = tree.get("parameters/state/playback")
	print("R after advance(0): current=", pb.get_current_node(), " chest=", h3.sk.get_bone_pose_rotation(chest).get_euler())
	tree.advance(DT)
	print("R after advance(DT): current=", pb.get_current_node(), " chest=", h3.sk.get_bone_pose_rotation(chest).get_euler(),
			" (calm key0 chest x=-0.05; written synchronously by advance)")
	for i in range(14):
		tree.advance(DT)
	var base := h3.sk.get_bone_pose_rotation(chest).get_euler()
	tree.set("parameters/add/add_amount", 1.0)
	tree.advance(DT)
	var with_b := h3.sk.get_bone_pose_rotation(chest).get_euler()
	tree.set("parameters/add/add_amount", 0.0)
	tree.advance(0.0)
	var without := h3.sk.get_bone_pose_rotation(chest).get_euler()
	print("R Add2 at breath t~0.53: chest x with=%.4f without=%.4f diff=%.4f (breath peak -0.055)" % [with_b.x, without.x, with_b.x - without.x])
	h3.root.queue_free()
	await process_frame
	# 4. LookAt limit semantics: primary_limit_angle total arc or half?
	for lim_deg in [60.0, 120.0, 160.0]:
		var h := _rig()
		var tg := Node3D.new()
		h.root.add_child(tg)
		tg.position = Vector3(-3.0, 1.7, 0.0)  # 90 deg to her right
		var look := LookAtModifier3D.new()
		h.sk.add_child(look)
		look.bone_name = "head"
		look.target_node = look.get_path_to(tg)
		look.use_angle_limitation = true
		look.symmetry_limitation = true
		look.primary_limit_angle = deg_to_rad(lim_deg)
		look.secondary_limit_angle = deg_to_rad(lim_deg)
		for i in range(3):
			await _frame(h)
		print("R LookAt limit=%d target 90 deg right -> head yaw %.1f" % [lim_deg, rad_to_deg(atan2(h.g("head").basis.z.x, h.g("head").basis.z.z))])
		h.root.queue_free()
		await process_frame
	# 5. LookAt duration: interpolation curve vs time
	var h5 := _rig()
	var tg5 := Node3D.new()
	h5.root.add_child(tg5)
	tg5.position = Vector3(0, 1.7, 3)
	var lk := LookAtModifier3D.new()
	h5.sk.add_child(lk)
	lk.bone_name = "head"
	lk.target_node = lk.get_path_to(tg5)
	lk.duration = 1.0
	lk.transition_type = Tween.TRANS_LINEAR
	for i in range(4):
		await _frame(h5)
	tg5.position = Vector3(3, 1.7, 0)
	var tr := []
	for i in range(36):
		await _frame(h5)
		if i % 3 == 0:
			tr.append("%.1f(rem %.2f %s)" % [rad_to_deg(atan2(h5.g("head").basis.z.x, h5.g("head").basis.z.z)), lk.get_interpolation_remaining(), lk.is_interpolating()])
	print("R LookAt duration=1.0 LINEAR, target jump 0->90: ", tr)
	h5.root.queue_free()
	await process_frame
	# 6. LimitAngularVelocity: what does `exclude` do; joint_count
	var h6 := _rig()
	var lim := LimitAngularVelocityModifier3D.new()
	h6.sk.add_child(lim)
	lim.max_angular_velocity = deg_to_rad(90.0)
	lim.chain_count = 1
	lim.set_root_bone_name(0, "spine")
	lim.set_end_bone_name(0, "head")
	await _frame(h6)
	print("R LimitAngVel chain spine->head joint_count=", lim.joint_count)
	var head := h6.sk.find_bone("head")
	var ua := h6.sk.find_bone("upper_arm.L")
	h6.sk.set_bone_pose_rotation(head, Quaternion.from_euler(Vector3(0, 1.2, 0)))
	h6.sk.set_bone_pose_rotation(ua, Quaternion.from_euler(Vector3(1.2, 0, 0)))
	await _frame(h6)
	print("R LimitAngVel exclude=false: head (in chain) moved deg=%.1f, upper_arm.L (outside) moved deg=%.1f in one frame (cap 3 deg/frame)" % [
			rad_to_deg(h6.sk.get_bone_pose_rotation(head).angle_to(Quaternion.IDENTITY)) if false else rad_to_deg(Quaternion.IDENTITY.angle_to(h6.g("head").basis.get_rotation_quaternion() * h6.g("neck").basis.get_rotation_quaternion().inverse())),
			rad_to_deg(Quaternion.IDENTITY.angle_to(h6.g("clavicle.L").basis.get_rotation_quaternion().inverse() * h6.g("upper_arm.L").basis.get_rotation_quaternion()))])
	h6.root.queue_free()
	await process_frame
	print("R done")
	quit()
