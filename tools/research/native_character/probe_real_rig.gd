extends SceneTree
## SPIKE probe 4: the native stack on the REAL contract rig (MikuRig/HandRig copied read-only from
## claude/funny-hawking-air6xk @ b8ddadf): non-identity rest bases, +Y joint->child, +Z = bend side,
## +X = Y x Z; tips are bones. Run: godot --headless --path . -s res://tools/research/native_character/probe_real_rig.gd

const DT := 1.0 / 30.0


func _initialize() -> void:
	_run.call_deferred()


func _rig() -> NCHarness:
	var body := MikuRig.build()
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


func _yaw_pitch(v: Vector3) -> String:
	return "yaw %.1f pitch %.1f" % [rad_to_deg(atan2(v.x, v.z)), rad_to_deg(asin(clampf(v.y, -1, 1)))]


func _run() -> void:
	var h := _rig()
	await _frame(h)
	print("R real rig bones=", h.sk.get_bone_count(), " head rest global z=", h.g("head").basis.z.snapped(Vector3.ONE * 0.01),
			" head pos=", h.g("head").origin.snapped(Vector3.ONE * 0.01), " hand.R pos=", h.g("hand.R").origin.snapped(Vector3.ONE * 0.01),
			" upper_arm.R=", h.g("upper_arm.R").origin.snapped(Vector3.ONE * 0.01))
	h.root.queue_free()
	await process_frame
	await _lookat()
	await _ik()
	await _springs()
	await _appearance()
	await _twist()
	await _additive()
	await _hand()
	print("R done")
	quit()


func _lookat() -> void:
	var h := _rig()
	var head := h.sk.find_bone("head")
	RigData.pose_local(h.sk, head, Vector3(0, 0, 0.3))  # an "animated" head tilt to preserve
	await _frame(h)
	var head_pos := h.world("head").origin
	var tgt := _node(h, head_pos + Vector3(sin(deg_to_rad(50.0)), 0.35, cos(deg_to_rad(50.0))) * 2.0)
	var infl := {"chest": 0.3, "neck": 0.45, "head": 1.0}
	for b: String in infl:
		var l := LookAtModifier3D.new()
		h.sk.add_child(l)
		l.bone_name = b
		l.relative = true
		l.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
		l.influence = infl[b]
		l.target_node = l.get_path_to(tgt)
	for i in range(3):
		RigData.pose_local(h.sk, head, Vector3(0, 0, 0.3))
		await _frame(h)
	var want := (tgt.position - h.world("head").origin).normalized()
	var got := h.world("head").basis.z.normalized()
	print("R real LookAt chain chest/neck/head (+Z forward, relative): head forward err deg=%.2f want %s got %s; chest %s neck %s" % [
			NCHarness.angle_between(got, want), _yaw_pitch(want), _yaw_pitch(got), _yaw_pitch(h.world("chest").basis.z), _yaw_pitch(h.world("neck").basis.z)])
	var up_dot := h.world("head").basis.x.dot(Vector3.UP)
	print("R real LookAt relative: head X axis . UP (tilt kept if far from 0) = %.3f" % up_dot)
	h.root.queue_free()
	await process_frame


func _ik() -> void:
	for mode in ["pole_node", "pole_dir_+Z", "no_pole"]:
		var h := _rig()
		await _frame(h)
		var sh := h.world("upper_arm.R").origin
		var t := _node(h, sh)
		var ik := TwoBoneIK3D.new()
		h.sk.add_child(ik)
		ik.setting_count = 1
		ik.set_root_bone_name(0, "upper_arm.R")
		ik.set_middle_bone_name(0, "forearm.R")
		ik.set_end_bone_name(0, "hand.R")
		ik.set_target_node(0, ik.get_path_to(t))
		if mode == "pole_node":
			var p := _node(h, sh + Vector3(-0.3, -0.3, -0.5))
			ik.set_pole_node(0, ik.get_path_to(p))
		elif mode == "pole_dir_+Z":
			ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z)
		var res := []
		var arm := h.world("upper_arm.R").origin.distance_to(h.world("forearm.R").origin) + h.world("forearm.R").origin.distance_to(h.world("hand.R").origin)
		for off in [Vector3(-0.1, -0.25, 0.3), Vector3(-0.05, 0.1, 0.4), Vector3(-0.3, -0.35, 0.05)]:
			t.position = sh + off
			for i in range(2):
				await _frame(h)
			res.append("%.4f" % h.world("hand.R").origin.distance_to(t.position))
		print("R real TwoBoneIK3D arm.R mode=%s updates=%d arm_len=%.3f errs=%s elbow=%s" % [mode, h.updates, arm, res, (h.world("forearm.R").origin - sh).snapped(Vector3.ONE * 0.01)])
		h.root.queue_free()
		await process_frame


func _springs() -> void:
	var h := _rig()
	var sb := SpringBoneSimulator3D.new()
	h.sk.add_child(sb)
	sb.setting_count = 2
	sb.set_root_bone_name(0, "skirt.0")
	sb.set_end_bone_name(0, "skirt.2")
	sb.set_extend_end_bone(0, true)
	sb.set_end_bone_length(0, 0.3)
	sb.set_stiffness(0, 1.5)
	sb.set_drag(0, 0.4)
	sb.set_gravity(0, 0.0)
	sb.set_root_bone_name(1, "index.0.R")
	sb.set_end_bone_name(1, "index.tip.R")
	sb.set_stiffness(1, 3.0)
	sb.set_drag(1, 0.5)
	sb.set_gravity(1, 0.0)
	print("R real SpringBone joint counts: skirt=", sb.get_joint_count(0), " index.R=", sb.get_joint_count(1))
	for i in range(4):
		await _frame(h)
	var rest_skirt := h.g("skirt.2").basis.y
	var rest_idx := h.g("index.1.R").basis.y
	var tr := []
	for i in range(30):
		h.root.position.z = 0.25 if i >= 1 else 0.0
		await _frame(h)
		if i % 3 == 0:
			tr.append("%.1f/%.1f" % [NCHarness.angle_between(h.g("skirt.2").basis.y, rest_skirt), NCHarness.angle_between(h.g("index.1.R").basis.y, rest_idx)])
	print("R real SpringBone skirt.2 / index.1.R deviation deg after a 25 cm jerk (every 3 frames): ", tr)
	h.root.queue_free()
	await process_frame


func _appearance() -> void:
	var h := _rig()
	MikuRig.apply_appearance(h.root, {"height": 1.1, "shoulder_width": 1.15, "neck_length": 1.3, "chest_volume": 1.2})
	await _frame(h)
	var sh := h.world("upper_arm.R").origin
	var t := _node(h, sh + Vector3(-0.1, -0.25, 0.3))
	var p := _node(h, sh + Vector3(-0.3, -0.3, -0.5))
	var ik := TwoBoneIK3D.new()
	h.sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upper_arm.R")
	ik.set_middle_bone_name(0, "forearm.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(t))
	ik.set_pole_node(0, ik.get_path_to(p))
	var lt := _node(h, h.world("head").origin + Vector3(1.5, 0.4, 1.5))
	var l := LookAtModifier3D.new()
	h.sk.add_child(l)
	l.bone_name = "head"
	l.relative = true
	l.target_node = l.get_path_to(lt)
	var sb := SpringBoneSimulator3D.new()
	h.sk.add_child(sb)
	sb.setting_count = 1
	sb.set_root_bone_name(0, "skirt.0")
	sb.set_end_bone_name(0, "skirt.2")
	for i in range(3):
		await _frame(h)
	var want := (lt.position - h.world("head").origin).normalized()
	print("R real appearance (height 1.1, shoulders 1.15, neck 1.3, chest 1.2) applied BEFORE modifiers: IK err=%.4f LookAt err deg=%.2f updates=%d" % [
			h.world("hand.R").origin.distance_to(t.position), NCHarness.angle_between(h.world("head").basis.z, want), h.updates])
	# changing appearance at RUNTIME with modifiers already live
	MikuRig.apply_appearance(h.root, {"height": 0.9, "shoulder_width": 0.9, "neck_length": 0.85, "chest_volume": 0.85})
	t.position = h.world("upper_arm.R").origin + Vector3(-0.1, -0.25, 0.3)
	for i in range(3):
		await _frame(h)
	want = (lt.position - h.world("head").origin).normalized()
	print("R real appearance changed at runtime (modifiers live): IK err=%.4f LookAt err deg=%.2f" % [
			h.world("hand.R").origin.distance_to(t.position), NCHarness.angle_between(h.world("head").basis.z, want)])
	h.root.queue_free()
	await process_frame


func _twist_of(h: NCHarness, bone: String) -> float:
	var i := h.sk.find_bone(bone)
	var p := h.sk.get_bone_parent(i)
	var local := (h.snap[p].basis.inverse() * h.snap[i].basis).get_rotation_quaternion()
	var rest := h.sk.get_bone_rest(i).basis.get_rotation_quaternion()
	var d := rest.inverse() * local
	# swing-twist: twist about local Y
	var tw := Quaternion(0, d.y, 0, d.w).normalized()
	return rad_to_deg(2.0 * atan2(tw.y, tw.w))


func _twist() -> void:
	for use in [false, true]:
		var h := _rig()
		if use:
			var tw := BoneTwistDisperser3D.new()
			h.sk.add_child(tw)
			tw.setting_count = 1
			tw.set_root_bone_name(0, "upper_arm.R")
			tw.set_end_bone_name(0, "hand.R")
		var hand := h.sk.find_bone("hand.R")
		for i in range(3):
			RigData.pose_local(h.sk, hand, Vector3(0, deg_to_rad(80.0), 0))
			await _frame(h)
		print("R real BoneTwistDisperser3D=%s hand.R twisted 80 deg about its Y -> twist upper_arm %.1f forearm %.1f hand %.1f" % [
				use, _twist_of(h, "upper_arm.R"), _twist_of(h, "forearm.R"), _twist_of(h, "hand.R")])
		h.root.queue_free()
		await process_frame


func _additive() -> void:
	var h := _rig()
	var chest := h.sk.find_bone("chest")
	var rest := h.sk.get_bone_rest(chest).basis.get_rotation_quaternion()
	var base := Animation.new()
	var t0 := base.add_track(Animation.TYPE_ROTATION_3D)
	base.track_set_path(t0, "Skeleton3D:chest")
	base.rotation_track_insert_key(t0, 0.0, rest * Quaternion.from_euler(Vector3(0.1, 0, 0)))
	var add := Animation.new()
	var t1 := add.add_track(Animation.TYPE_ROTATION_3D)
	add.track_set_path(t1, "Skeleton3D:chest")
	add.rotation_track_insert_key(t1, 0.0, rest * Quaternion.from_euler(Vector3(-0.05, 0, 0)))
	var lib := AnimationLibrary.new()
	lib.add_animation(&"base", base)
	lib.add_animation(&"add", add)
	var bt := AnimationNodeBlendTree.new()
	var a := AnimationNodeAnimation.new()
	a.animation = &"base"
	var b := AnimationNodeAnimation.new()
	b.animation = &"add"
	bt.add_node(&"a", a)
	bt.add_node(&"b", b)
	var ad := AnimationNodeAdd2.new()
	ad.sync = true
	bt.add_node(&"add2", ad)
	bt.connect_node(&"add2", 0, &"a")
	bt.connect_node(&"add2", 1, &"b")
	bt.connect_node(&"output", 0, &"add2")
	var tree := h.add_tree(bt, lib)
	tree.set("parameters/add2/add_amount", 1.0)
	tree.advance(DT)
	var got := (rest.inverse() * h.sk.get_bone_pose_rotation(chest)).get_euler()
	print("R real Add2 with non-identity rest: base rest*Rx(0.10) + add rest*Rx(-0.05) -> rest^-1*pose euler x=%.4f (0.05 = additive relative to REST)" % got.x)
	h.root.queue_free()
	await process_frame


func _hand() -> void:
	var hand := HandRig.build(HandRig.Side.RIGHT)
	root.add_child(hand)
	var h := NCHarness.new(hand)
	var sb := SpringBoneSimulator3D.new()
	h.sk.add_child(sb)
	var names := ["thumb", "index", "middle", "ring", "little"]
	sb.setting_count = names.size()
	for i in range(names.size()):
		sb.set_root_bone_name(i, "%s.0" % names[i])
		sb.set_end_bone_name(i, "%s.tip" % names[i])
		sb.set_stiffness(i, 3.0)
		sb.set_drag(i, 0.5)
		sb.set_gravity(i, 0.0)
	var lim := LimitAngularVelocityModifier3D.new()
	h.sk.add_child(lim)
	lim.chain_count = 1
	lim.set_root_bone_name(0, "index.0")
	lim.set_end_bone_name(0, "index.tip")
	for i in range(3):
		await _frame(h)
	var rest_i := h.g("index.2").basis.x
	var tr := []
	for i in range(24):
		hand.position.y = 3.0 if i >= 1 else 0.0  # giant hand jerked up 3 u (~0.4 hand lengths)
		await _frame(h)
		if i % 3 == 0:
			tr.append("%.1f" % NCHarness.angle_between(h.g("index.2").basis.x, rest_i))
	print("R real HandRig.RIGHT bones=%d springs joints index=%d; index.2 deviation deg after jerk: %s updates=%d" % [h.sk.get_bone_count(), sb.get_joint_count(1), tr, h.updates])
	hand.queue_free()
	await process_frame
