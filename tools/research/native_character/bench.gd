extends SceneTree
## SPIKE bench (headless): CPU cost per rig per frame of each native layer, measured INSIDE the
## skeleton update with two GDScript stamp modifiers (first and last child of the Skeleton3D).
## Run: godot --headless --path . -s res://tools/research/native_character/bench.gd
## Numbers are CPU only (no skinning/render). Machine is shared: see the load line.

const DT := 1.0 / 30.0
const N := 16
const WARM := 30
const FRAMES := 120


func _initialize() -> void:
	_run.call_deferred()


func _node(parent: Node3D, p: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = p
	return n


func _setup(cfg: String, body: Node3D, sk: Skeleton3D) -> void:
	match cfg:
		"empty":
			pass
		"lookat_head":
			_look(body, sk, "head")
		"lookat_chain5":
			for b in ["chest", "neck", "head", "eye.L", "eye.R"]:
				_look(body, sk, b)
		"twobone_ik":
			_twobone(body, sk)
		"ccdik_16":
			_iter(body, sk, "CCDIK3D")
		"fabrik_16":
			_iter(body, sk, "FABRIK3D")
		"jacobian_16":
			_iter(body, sk, "JacobianIK3D")
		"spline_ik_hair":
			var path := Path3D.new()
			body.add_child(path)
			var c := Curve3D.new()
			c.add_point(Vector3(0, 1.66, -0.10))
			c.add_point(Vector3(0, 1.45, -0.25))
			c.add_point(Vector3(0.1, 1.2, -0.2))
			c.add_point(Vector3(0.15, 1.0, -0.1))
			path.curve = c
			var s := SplineIK3D.new()
			sk.add_child(s)
			s.setting_count = 1
			s.set_root_bone_name(0, "hair.0")
			s.set_end_bone_name(0, "hair.3")
			s.set_path_3d(0, s.get_path_to(path))
		"aim":
			var t := _node(body, Vector3(-1, 1.3, 1))
			var a := AimModifier3D.new()
			sk.add_child(a)
			a.setting_count = 1
			a.set_apply_bone_name(0, "index.R")
			a.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
			a.set_reference_node(0, a.get_path_to(t))
		"copy_transform":
			var cp := CopyTransformModifier3D.new()
			sk.add_child(cp)
			cp.setting_count = 1
			cp.set_apply_bone_name(0, "index.L")
			cp.set_reference_bone_name(0, "index.R")
		"limit_angvel_2chains":
			var l := LimitAngularVelocityModifier3D.new()
			sk.add_child(l)
			l.chain_count = 2
			l.set_root_bone_name(0, "spine")
			l.set_end_bone_name(0, "head")
			l.set_root_bone_name(1, "upper_arm.R")
			l.set_end_bone_name(1, "hand.R")
		"twist_disperser":
			var tw := BoneTwistDisperser3D.new()
			sk.add_child(tw)
			tw.setting_count = 1
			tw.set_root_bone_name(0, "upper_arm.R")
			tw.set_end_bone_name(0, "hand.R")
		"springbone_5chains":
			var sb := SpringBoneSimulator3D.new()
			sk.add_child(sb)
			var chains := [["hair.0", "hair.3"], ["skirt.f.0", "skirt.f.2"], ["skirt.b.0", "skirt.b.2"],
					["skirt.l.0", "skirt.l.2"], ["skirt.r.0", "skirt.r.2"]]
			sb.setting_count = chains.size()
			for i in range(chains.size()):
				sb.set_root_bone_name(i, chains[i][0])
				sb.set_end_bone_name(i, chains[i][1])
				sb.set_extend_end_bone(i, true)
				sb.set_end_bone_length(i, 0.15)
			var col := SpringBoneCollisionCapsule3D.new()
			sb.add_child(col)
			col.bone_name = "hips"


func _look(body: Node3D, sk: Skeleton3D, b: String) -> void:
	var t := _node(body, Vector3(1, 1.7, 2))
	var l := LookAtModifier3D.new()
	sk.add_child(l)
	l.bone_name = b
	l.relative = true
	l.use_angle_limitation = true
	l.primary_limit_angle = 2.0
	l.secondary_limit_angle = 1.4
	l.target_node = l.get_path_to(t)


func _twobone(body: Node3D, sk: Skeleton3D) -> void:
	var t := _node(body, Vector3(-0.35, 1.25, 0.35))
	var p := _node(body, Vector3(-0.7, 1.1, -0.5))
	var ik := TwoBoneIK3D.new()
	sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upper_arm.R")
	ik.set_middle_bone_name(0, "forearm.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(t))
	ik.set_pole_node(0, ik.get_path_to(p))


func _iter(body: Node3D, sk: Skeleton3D, cls: String) -> void:
	var t := _node(body, Vector3(-0.35, 1.25, 0.35))
	var ik: IterateIK3D = ClassDB.instantiate(cls)
	sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "clavicle.R")
	ik.set_end_bone_name(0, "hand.R")
	ik.set_target_node(0, ik.get_path_to(t))
	ik.max_iterations = 16
	ik.angular_delta_limit = deg_to_rad(30.0)
	ik.deterministic = true


func _bench_modifiers(cfg: String) -> float:
	var bodies: Array[Node3D] = []
	var starts: Array[NCStamp] = []
	var ends: Array[NCStamp] = []
	for i in range(N):
		var body := NCRig.build_body()
		root.add_child(body)
		body.position.x = float(i) * 2.0
		var sk: Skeleton3D = body.get_node("Skeleton3D")
		sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		var s0 := NCStamp.new()
		sk.add_child(s0)
		_setup(cfg, body, sk)
		var s1 := NCStamp.new()
		sk.add_child(s1)
		bodies.append(body)
		starts.append(s0)
		ends.append(s1)
	var total := 0
	for f in range(WARM + FRAMES):
		for b in bodies:
			# move the rig so solvers/springs have work every frame
			b.position.z = 0.05 * sin(float(f) * 0.3)
			(b.get_node("Skeleton3D") as Skeleton3D).advance(DT)
		await process_frame
		if f >= WARM:
			for i in range(N):
				total += ends[i].stamp_us - starts[i].stamp_us
	for b in bodies:
		b.queue_free()
	await process_frame
	return float(total) / float(FRAMES * N)


func _bench_tree() -> float:
	var trees: Array[NCMiku] = []
	for i in range(N):
		var m := NCMiku.new()
		root.add_child(m)
		m.position.x = float(i) * 2.0
		trees.append(m)
	await process_frame
	for m in trees:
		for c in m.sk.get_children():
			if c is SkeletonModifier3D:
				(c as SkeletonModifier3D).active = false
	var total := 0
	for f in range(WARM + FRAMES):
		for m in trees:
			var t0 := Time.get_ticks_usec()
			m.tree.advance(DT)
			if f >= WARM:
				total += Time.get_ticks_usec() - t0
		if f == WARM + 20:
			for m in trees:
				m.travel(&"frustrated")
				m.fire_gesture()
		await process_frame
	for m in trees:
		m.queue_free()
	await process_frame
	return float(total) / float(FRAMES * N)


func _bench_full_miku() -> Vector2:
	var ms: Array[NCMiku] = []
	for i in range(N):
		var m := NCMiku.new()
		root.add_child(m)
		m.position.x = float(i) * 2.0
		ms.append(m)
	await process_frame
	var tree_total := 0
	var mod_total := 0
	for f in range(WARM + FRAMES):
		for m in ms:
			m.gaze_goal = Vector3(sin(float(f) * 0.1), 1.6, 2.0) + m.global_position
			m.reach_weight = 1.0
			m.aim_weight = 1.0
			m.aim_node = m
			m.step(DT)
		await process_frame
		if f >= WARM:
			for m in ms:
				tree_total += m.tree_us
				mod_total += m.modifiers_us
	for m in ms:
		m.queue_free()
	await process_frame
	return Vector2(float(tree_total) / float(FRAMES * N), float(mod_total) / float(FRAMES * N))


func _bench_hands(count: int) -> float:
	var hs: Array[NCPuppetHand] = []
	var s0s: Array[NCStamp] = []
	var s1s: Array[NCStamp] = []
	for i in range(count):
		var h := NCPuppetHand.new(Vector3(float(i), 1, 0))
		root.add_child(h)
		h.presence_goal = 1.0
		hs.append(h)
		var s0 := NCStamp.new()
		h.sk.add_child(s0)
		h.sk.move_child(s0, 0)
		var s1 := NCStamp.new()
		h.sk.add_child(s1)
		s0s.append(s0)
		s1s.append(s1)
	await process_frame
	var total := 0
	for f in range(WARM + FRAMES):
		var t0 := Time.get_ticks_usec()
		for i in range(count):
			var h := hs[i]
			h.goal = Vector3(float(i), 1.0 + 0.3 * sin(float(f) * 0.2), 0.3 * cos(float(f) * 0.17))
			h.grip_goal = sin(float(f) * 0.1)
			h.step(DT)
		var t_step := Time.get_ticks_usec() - t0
		await process_frame
		# step() (own springs + tree.advance, synchronous) + the deferred modifier stack (stamps)
		if f >= WARM:
			total += t_step
			for i in range(count):
				total += s1s[i].stamp_us - s0s[i].stamp_us
	for h in hs:
		h.queue_free()
	await process_frame
	return float(total) / float(FRAMES)


func _run() -> void:
	print("BENCH cpus=", OS.get_processor_count(), " N=", N, " (shared machine: other Godot workers may run)")
	var base := await _bench_modifiers("empty")
	print("BENCH modifiers[empty stamps only] us/rig/frame=%.1f (subtracted below)" % base)
	for cfg in ["lookat_head", "lookat_chain5", "twobone_ik", "ccdik_16", "fabrik_16", "jacobian_16", "spline_ik_hair",
			"aim", "copy_transform", "limit_angvel_2chains", "twist_disperser", "springbone_5chains"]:
		var us := await _bench_modifiers(cfg)
		print("BENCH modifier %-22s us/rig/frame=%.1f" % [cfg, maxf(us - base, 0.0)])
	var tr := await _bench_tree()
	print("BENCH AnimationTree MIKU (SM 4 states + Add2 breath + OneShot) advance us/rig/frame=%.1f" % tr)
	var full := await _bench_full_miku()
	print("BENCH full NCMiku: tree us=%.1f modifier stack us=%.1f (per rig per frame)" % [full.x, full.y])
	for c in [1, 4, 8, 16, 32]:
		var us := await _bench_hands(c)
		print("BENCH puppet hands x%d: step+modifiers us/frame=%.0f -> per hand us=%.1f" % [c, us, us / float(c)])
	print("BENCH done")
	quit()
