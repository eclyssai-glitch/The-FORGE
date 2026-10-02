extends SceneTree
## SPIKE probe: behaviour of the native animation stack in Godot 4.7.2, measured (headless).
## Run: godot --headless --path . -s res://tools/research/native_character/probe_semantics.gd
## Every line starting with "R " is a result recorded in docs/research/native-character-runtime.md.

const DT := 1.0 / 30.0


func _initialize() -> void:
	_run.call_deferred()


func _rig() -> NCHarness:
	var body := NCRig.build_body()
	root.add_child(body)
	return NCHarness.new(body)


func _free(h: NCHarness) -> void:
	h.root.queue_free()


func _frame(h: NCHarness, dt: float = DT) -> void:
	h.advance(dt)
	await process_frame


func _lib(sk: Skeleton3D) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var st := NCPoses.body_states(sk)
	for k: StringName in st:
		lib.add_animation(k, st[k])
	lib.add_animation(&"breath", NCPoses.breath(sk))
	lib.add_animation(&"flick", NCPoses.flick(sk))
	var roll := Animation.new()
	roll.length = 1.0
	roll.loop_mode = Animation.LOOP_LINEAR
	var t := roll.add_track(Animation.TYPE_ROTATION_3D)
	roll.track_set_path(t, "Skeleton3D:head")
	roll.rotation_track_insert_key(t, 0.0, Quaternion.from_euler(Vector3(0, 0, 0.3)))
	lib.add_animation(&"head_roll", roll)
	return lib


func _run() -> void:
	await _tree_semantics()
	await _lookat_relative()
	await _lookat_duration_and_limits()
	await _limit_angular_velocity()
	await _two_bone_ik()
	await _attachment_and_timing()
	await _spring_bones()
	await _appearance()
	await _aim_and_copy()
	print("R done")
	quit()


## A/B/C: manual tree advance is synchronous? Add2 is additive from rest? OneShot filter isolates?
func _tree_semantics() -> void:
	var h := _rig()
	var bt := AnimationNodeBlendTree.new()
	var sm := AnimationNodeStateMachine.new()
	for s in [&"calm", &"focus", &"frustrated", &"recover"]:
		var an := AnimationNodeAnimation.new()
		an.animation = s
		sm.add_node(s, an)
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = 0.6
	sm.add_transition(&"Start", &"calm", AnimationNodeStateMachineTransition.new())
	sm.add_transition(&"calm", &"frustrated", tr)
	bt.add_node(&"state", sm)
	var br := AnimationNodeAnimation.new()
	br.animation = &"breath"
	bt.add_node(&"breath", br)
	var add := AnimationNodeAdd2.new()
	add.filter_enabled = true
	for b in ["spine", "chest", "neck", "clavicle.L", "clavicle.R"]:
		add.set_filter_path(NodePath("Skeleton3D:" + b), true)
	bt.add_node(&"breath_add", add)
	var fl := AnimationNodeAnimation.new()
	fl.animation = &"flick"
	bt.add_node(&"flick", fl)
	var os := AnimationNodeOneShot.new()
	os.filter_enabled = true
	for b in ["upper_arm.L", "forearm.L", "hand.L"]:
		os.set_filter_path(NodePath("Skeleton3D:" + b), true)
	os.fadein_time = 0.1
	os.fadeout_time = 0.2
	bt.add_node(&"gesture", os)
	bt.connect_node(&"breath_add", 0, &"state")
	bt.connect_node(&"breath_add", 1, &"breath")
	bt.connect_node(&"gesture", 0, &"breath_add")
	bt.connect_node(&"gesture", 1, &"flick")
	bt.connect_node(&"output", 0, &"gesture")
	var tree := h.add_tree(bt, _lib(h.sk))
	tree.set("parameters/breath_add/add_amount", 0.0)
	var chest := h.sk.find_bone("chest")
	var q_before := h.sk.get_bone_pose_rotation(chest)
	tree.advance(0.0)
	var q_after := h.sk.get_bone_pose_rotation(chest)
	print("R tree.advance(0) synchronous pose write: before=", q_before, " after=", q_after,
			" changed=", not q_before.is_equal_approx(q_after))
	var pb: AnimationNodeStateMachinePlayback = tree.get("parameters/state/playback")
	print("R state machine current after first advance: ", pb.get_current_node())
	# Additive: breath at its peak (t=0.5 of a 1 s loop) on top of calm.
	for i in range(15):
		tree.advance(DT)
	var calm_chest := h.sk.get_bone_pose_rotation(chest)
	tree.set("parameters/breath_add/add_amount", 1.0)
	tree.advance(0.0)
	var added := h.sk.get_bone_pose_rotation(chest)
	var breath_q := Quaternion.from_euler(Vector3(-0.055, 0, 0))
	var t_breath: float = fmod(15.0 * DT, 1.0)
	print("R Add2: calm chest=", calm_chest.get_euler(), " with breath=", added.get_euler(),
			" diff_x=", added.get_euler().x - calm_chest.get_euler().x, " (breath t=", t_breath, ", peak -0.055 at t=0.5)")
	var head_before := h.sk.get_bone_pose_rotation(h.sk.find_bone("head"))
	var arm_before := h.sk.get_bone_pose_rotation(h.sk.find_bone("upper_arm.L"))
	tree.set("parameters/gesture/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	for i in range(14):
		tree.advance(DT)
	var head_after := h.sk.get_bone_pose_rotation(h.sk.find_bone("head"))
	var arm_after := h.sk.get_bone_pose_rotation(h.sk.find_bone("upper_arm.L"))
	print("R OneShot filtered: upper_arm.L moved deg=", rad_to_deg(arm_before.angle_to(arm_after)),
			" head (unfiltered, own calm loop) moved deg=", rad_to_deg(head_before.angle_to(head_after)),
			" active=", tree.get("parameters/gesture/active"))
	# Travel with xfade
	pb.travel(&"frustrated")
	var samples := []
	for i in range(24):
		tree.advance(DT)
		if i % 4 == 0:
			samples.append("%s:%.2f" % [pb.get_current_node(), rad_to_deg(h.sk.get_bone_pose_rotation(h.sk.find_bone("clavicle.L")).get_euler().z)])
	print("R travel calm->frustrated xfade 0.6 s clavicle.L z deg over frames: ", samples)
	_free(h)
	await process_frame


## D: LookAtModifier3D.relative (4.7 default false) vs an animated head roll.
func _lookat_relative() -> void:
	for rel in [false, true]:
		var h := _rig()
		var bt := AnimationNodeAnimation.new()
		bt.animation = &"head_roll"
		h.add_tree(bt, _lib(h.sk))
		var target := Node3D.new()
		h.root.add_child(target)
		target.position = Vector3(0.0, 1.7, 3.0)  # straight ahead
		var look := LookAtModifier3D.new()
		h.sk.add_child(look)
		look.bone_name = "head"
		look.relative = rel
		look.target_node = look.get_path_to(target)
		for i in range(3):
			await _frame(h)
		var hb := h.g("head").basis
		print("R LookAt relative=", rel, ": animated roll 17.2 deg -> head roll after look-at deg=",
				rad_to_deg(hb.get_euler().z), " forward=", hb.z)
		_free(h)
		await process_frame


## E/F: LookAt `duration` (built-in interpolation) when the target jumps; limits.
func _lookat_duration_and_limits() -> void:
	var h := _rig()
	var target := Node3D.new()
	h.root.add_child(target)
	target.position = Vector3(0.0, 1.7, 3.0)
	var look := LookAtModifier3D.new()
	h.sk.add_child(look)
	look.bone_name = "head"
	look.target_node = look.get_path_to(target)
	look.duration = 0.5
	look.transition_type = Tween.TRANS_SINE
	look.ease_type = Tween.EASE_IN_OUT
	for i in range(5):
		await _frame(h)
	target.position = Vector3(3.0, 1.7, 1.0)  # jump to her left
	var trace := []
	for i in range(20):
		await _frame(h)
		var a := NCHarness.angle_between(h.g("head").basis.z, Vector3(0, 0, 1))
		trace.append("%.1f%s" % [a, "*" if look.is_interpolating() else ""])
	print("R LookAt duration=0.5 target jump (deg from front per frame, * = interpolating): ", trace)
	# continuous motion: does duration add lag to a target that moves every frame?
	var lag := []
	for i in range(30):
		var ang := float(i) * 0.06
		target.position = Vector3(3.0 * sin(ang), 1.7, 3.0 * cos(ang))
		await _frame(h)
		var want := rad_to_deg(ang)
		var got := rad_to_deg(atan2(h.g("head").basis.z.x, h.g("head").basis.z.z))
		if i % 5 == 4:
			lag.append("want %.0f got %.0f%s" % [want, got, "*" if look.is_interpolating() else ""])
	print("R LookAt duration=0.5 target moving continuously: ", lag)
	# limits
	look.duration = 0.0
	look.use_angle_limitation = true
	look.symmetry_limitation = true
	look.primary_limit_angle = deg_to_rad(80.0)
	look.secondary_limit_angle = deg_to_rad(60.0)
	target.position = Vector3(-2.5, 1.7, -2.0)  # behind, to her right
	for i in range(3):
		await _frame(h)
	print("R LookAt limits 80/60 target behind-right: within=", look.is_target_within_limitation(),
			" head yaw deg=", rad_to_deg(atan2(h.g("head").basis.z.x, h.g("head").basis.z.z)))
	_free(h)
	await process_frame


## G: LimitAngularVelocityModifier3D on a pose jump.
func _limit_angular_velocity() -> void:
	var h := _rig()
	var lim := LimitAngularVelocityModifier3D.new()
	h.sk.add_child(lim)
	lim.max_angular_velocity = deg_to_rad(180.0)
	lim.chain_count = 1
	lim.set_root_bone_name(0, "neck")
	lim.set_end_bone_name(0, "head")
	print("R LimitAngVel joint_count after chain neck->head: ", lim.joint_count, " exclude=", lim.exclude)
	for i in range(3):
		await _frame(h)
	var head := h.sk.find_bone("head")
	var trace := []
	for i in range(18):
		h.sk.set_bone_pose_rotation(head, Quaternion.from_euler(Vector3(0, deg_to_rad(90.0), 0)) if i < 12 else Quaternion.IDENTITY)
		await _frame(h)
		trace.append("%.1f" % rad_to_deg(atan2(h.g("head").basis.z.x, h.g("head").basis.z.z)))
	print("R LimitAngVel 180 deg/s, pose jump 0->90 deg then back (head yaw per frame @30fps): ", trace)
	# does it limit a modifier placed BEFORE it (LookAt) — i.e. is it a post-filter on the stack?
	var target := Node3D.new()
	h.root.add_child(target)
	target.position = Vector3(0, 1.7, 3)
	var look := LookAtModifier3D.new()
	h.sk.add_child(look)
	h.sk.move_child(look, 0)
	look.bone_name = "head"
	look.target_node = look.get_path_to(target)
	for i in range(10):
		h.sk.set_bone_pose_rotation(head, Quaternion.IDENTITY)
		await _frame(h)
	target.position = Vector3(3, 1.7, 0.2)
	var tr2 := []
	for i in range(12):
		h.sk.set_bone_pose_rotation(head, Quaternion.IDENTITY)
		await _frame(h)
		tr2.append("%.1f" % rad_to_deg(atan2(h.g("head").basis.z.x, h.g("head").basis.z.z)))
	print("R LimitAngVel after LookAt (child order look->limit), target jump 0->86 deg: ", tr2)
	_free(h)
	await process_frame


## H: TwoBoneIK3D — reach, out of reach, pole, moving target.
func _two_bone_ik() -> void:
	var h := _rig()
	var target := Node3D.new()
	h.root.add_child(target)
	var pole := Node3D.new()
	h.root.add_child(pole)
	pole.position = Vector3(-0.6, 1.2, -0.6)  # elbow out and back
	var ik := TwoBoneIK3D.new()
	h.sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upper_arm.R")
	ik.set_middle_bone_name(0, "forearm.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	var errs := []
	for p in [Vector3(-0.35, 1.25, 0.35), Vector3(-0.2, 1.5, 0.4), Vector3(-0.5, 1.0, 0.1), Vector3(-1.5, 1.4, 0.8)]:
		target.position = p
		for i in range(2):
			await _frame(h)
		var hand := h.world("hand.R").origin
		var elbow := h.world("forearm.R").origin
		errs.append("target %s err %.4f elbow %s" % [p, hand.distance_to(p), elbow.snapped(Vector3.ONE * 0.01)])
	print("R TwoBoneIK3D (pole node) reach errors: ", errs)
	# hand orientation: does the end bone keep its animated local rotation?
	print("R TwoBoneIK3D hand.R basis y after solve: ", h.g("hand.R").basis.y, " forearm.R y: ", h.g("forearm.R").basis.y)
	_free(h)
	await process_frame


## I: when is the post-modifier pose readable? BoneAttachment3D vs get_bone_global_pose in _process.
func _attachment_and_timing() -> void:
	var h := _rig()
	var target := Node3D.new()
	h.root.add_child(target)
	target.position = Vector3(-0.2, 1.6, 0.5)
	var ik := TwoBoneIK3D.new()
	h.sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upper_arm.R")
	ik.set_middle_bone_name(0, "forearm.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(target))
	var att := BoneAttachment3D.new()
	h.sk.add_child(att)
	att.bone_name = "hand.R"
	for i in range(3):
		await _frame(h)
	var in_process := (h.sk.global_transform * h.sk.get_bone_global_pose(h.sk.find_bone("hand.R"))).origin
	print("R post-modifier hand.R: snapshot(skeleton_updated)=", h.world("hand.R").origin.snapped(Vector3.ONE * 0.001),
			" BoneAttachment3D=", att.global_position.snapped(Vector3.ONE * 0.001),
			" get_bone_global_pose in _process=", in_process.snapped(Vector3.ONE * 0.001), " target=", target.position)
	_free(h)
	await process_frame


## J: SpringBoneSimulator3D — follow-through when the body jerks; determinism; animated rest.
func _spring_bones() -> void:
	var results := []
	for run in range(2):
		var h := _rig()
		var sb := SpringBoneSimulator3D.new()
		h.sk.add_child(sb)
		sb.setting_count = 1
		sb.set_root_bone_name(0, "skirt.f.0")
		sb.set_end_bone_name(0, "skirt.f.2")
		sb.set_extend_end_bone(0, true)
		sb.set_end_bone_length(0, 0.2)
		sb.set_stiffness(0, 1.0)
		sb.set_drag(0, 0.4)
		sb.set_gravity(0, 0.0)
		for i in range(5):
			await _frame(h)
		var trace := []
		for i in range(40):
			h.root.position.z = 0.3 if i >= 1 else 0.0  # step forward 30 cm in one frame
			await _frame(h)
			var tip := h.g("skirt.f.2")
			trace.append(tip.basis.y.z)
		results.append(trace)
		if run == 0:
			var s := []
			for i in range(0, 40, 4):
				s.append("%.3f" % trace[i])
			print("R SpringBone skirt.f tip bone y.z after 30 cm step (every 4 frames): ", s)
		_free(h)
		await process_frame
	var same := true
	for i in range(40):
		if not is_equal_approx(float(results[0][i]), float(results[1][i])):
			same = false
	print("R SpringBone deterministic across two identical runs (manual dt): ", same)


## K: appearance via bone rest + pose scale/position; does the tree (rotation tracks only) keep it?
## Does TwoBoneIK3D follow a changed arm length at runtime?
func _appearance() -> void:
	var h := _rig()
	var sm := AnimationNodeAnimation.new()
	sm.animation = &"calm"
	h.add_tree(sm, _lib(h.sk))
	var chest := h.sk.find_bone("chest")
	var neck := h.sk.find_bone("neck")
	var fore := h.sk.find_bone("forearm.R")
	var rest_c := h.sk.get_bone_rest(chest)
	h.sk.set_bone_rest(chest, Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 1.0, 1.15)), rest_c.origin))
	h.sk.set_bone_pose_scale(chest, Vector3(1.2, 1.0, 1.15))
	var rest_n := h.sk.get_bone_rest(neck)
	h.sk.set_bone_rest(neck, Transform3D(Basis.IDENTITY, rest_n.origin * 1.3))
	h.sk.set_bone_pose_position(neck, rest_n.origin * 1.3)
	for i in range(4):
		await _frame(h)
	print("R appearance under AnimationTree (rotation tracks only): chest pose scale=", h.sk.get_bone_pose_scale(chest),
			" neck pose pos=", h.sk.get_bone_pose_position(neck), " (expected ", rest_n.origin * 1.3, ")")
	# a position track in ANY animation would win: demonstrate
	var lib := h.tree.get_animation_library(&"")
	var bad := Animation.new()
	var t := bad.add_track(Animation.TYPE_POSITION_3D)
	bad.track_set_path(t, "Skeleton3D:neck")
	bad.position_track_insert_key(t, 0.0, rest_n.origin)
	lib.add_animation(&"bad", bad)
	var an := AnimationNodeAnimation.new()
	an.animation = &"bad"
	h.tree.tree_root = an
	for i in range(2):
		await _frame(h)
	print("R appearance vs a POSITION track on neck: neck pose pos=", h.sk.get_bone_pose_position(neck), " (appearance lost)")
	h.tree.tree_root = sm
	h.sk.set_bone_pose_position(neck, rest_n.origin * 1.3)
	# IK on a lengthened forearm
	var target := Node3D.new()
	h.root.add_child(target)
	target.position = Vector3(-0.45, 1.05, 0.35)
	var ik := TwoBoneIK3D.new()
	h.sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upper_arm.R")
	ik.set_middle_bone_name(0, "forearm.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(target))
	for i in range(2):
		await _frame(h)
	var e0 := h.world("hand.R").origin.distance_to(target.position)
	var rest_f := h.sk.get_bone_rest(fore)
	var hand := h.sk.find_bone("hand.R")
	var rest_h := h.sk.get_bone_rest(hand)
	h.sk.set_bone_rest(hand, Transform3D(Basis.IDENTITY, rest_h.origin * 1.25))
	h.sk.set_bone_pose_position(hand, rest_h.origin * 1.25)
	for i in range(2):
		await _frame(h)
	var e1 := h.world("hand.R").origin.distance_to(target.position)
	ik.reset()
	for i in range(2):
		await _frame(h)
	var e2 := h.world("hand.R").origin.distance_to(target.position)
	print("R TwoBoneIK3D after forearm lengthened x1.25 at runtime: err before=%.4f after=%.4f after reset()=%.4f" % [e0, e1, e2])
	_free(h)
	await process_frame


## M: AimModifier3D (index points at a node) and CopyTransformModifier3D sanity.
func _aim_and_copy() -> void:
	var h := _rig()
	var target := Node3D.new()
	h.root.add_child(target)
	target.position = Vector3(-1.5, 1.4, 1.5)
	var aim := AimModifier3D.new()
	h.sk.add_child(aim)
	aim.setting_count = 1
	aim.set_apply_bone_name(0, "index.R")
	aim.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	aim.set_reference_node(0, aim.get_path_to(target))
	aim.set_forward_axis(0, SkeletonModifier3D.BONE_AXIS_MINUS_Y)
	for i in range(3):
		await _frame(h)
	var fwd := -h.world("index.R").basis.y
	var want := (target.position - h.world("index.R").origin)
	print("R AimModifier3D index.R (-Y) to node: angle error deg=", NCHarness.angle_between(fwd, want))
	var cp := CopyTransformModifier3D.new()
	h.sk.add_child(cp)
	cp.setting_count = 1
	cp.set_apply_bone_name(0, "index.L")
	cp.set_reference_bone_name(0, "index.R")
	cp.set_copy_rotation(0, true)
	cp.set_copy_position(0, false)
	cp.set_copy_scale(0, false)
	for i in range(2):
		await _frame(h)
	print("R CopyTransformModifier3D index.L <- index.R rotation (local): L=", h.sk.get_bone_pose_rotation(h.sk.find_bone("index.L")),
			" snapshot L global y=", h.g("index.L").basis.y.snapped(Vector3.ONE * 0.01), " R global y=", h.g("index.R").basis.y.snapped(Vector3.ONE * 0.01))
	_free(h)
	await process_frame
