class_name NCMiku
extends Node3D
## SPIKE — the test character on the NATIVE stack. Layers (docs/research/native-character-runtime.md):
##   director inputs (mood, gaze goal, reach goal/weight, rigidity, gesture)  <- the MIND would set these
##   -> own springs on the TARGETS (mass, anticipation, overlap: each gaze stage its own spring)
##   -> AnimationTree (manual): state machine calm/focus/frustrated/recover + additive breath
##      (Add2, sync, filtered torso) + one-shot gesture (filtered left arm)
##   -> Skeleton3D modifiers (manual, child order = evaluation order):
##      LookAt chest/neck/head (relative, limited) -> TwoBoneIK3D right arm (pole node)
##      -> AimModifier3D right index -> BoneTwistDisperser3D forearm (candy-wrapper) ->
##      LimitAngularVelocity (anti-pop) -> SpringBoneSimulator3D (skirt chain + 10 finger chains)
## Rig: the REAL contract rig MikuRig (copied read-only from claude/funny-hawking-air6xk @ b8ddadf),
## sculpture units scaled by SCALE (waist at WAIST_Y). No eye or hair bones in that rig: the gaze
## chain stops at the head (eyes need bones or a shader — see the research doc).
## The director never writes a bone. It writes tree parameters, modifier influences and target nodes.

const STATES: Array[StringName] = [&"calm", &"focus", &"frustrated", &"recover"]
const SCALE := 0.28
const WAIST_Y := 1.25
const BREATH_BONES := ["spine", "chest", "neck", "clavicle.L", "clavicle.R"]
const GESTURE_BONES := ["upper_arm.L", "forearm.L", "hand.L"]
## gaze stage: [bone, influence, limit (total arc, deg), spring f calm, f stiff]
const GAZE_STAGES: Array = [
	["chest", 0.30, 50.0, 0.45, 2.6],
	["neck", 0.45, 80.0, 0.75, 3.0],
	["head", 0.9, 130.0, 1.3, 3.4],
]
const FINGERS := ["thumb", "index", "middle", "ring", "little"]

var body: Node3D
var sk: Skeleton3D
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var looks: Array[LookAtModifier3D] = []
var arm_ik: TwoBoneIK3D
var index_aim: AimModifier3D
var limiter: LimitAngularVelocityModifier3D
var twist: BoneTwistDisperser3D
var springs: SpringBoneSimulator3D
var index_tip: BoneAttachment3D
var index_tip_l: BoneAttachment3D

## Director inputs.
var mood: StringName = &"calm"
var gaze_goal := Vector3(0, 1.6, 2.0)
var reach_goal := Vector3(-0.3, 1.0, 0.25)
var reach_weight := 0.0
var aim_node: Node3D
var aim_weight := 0.0
var rigidity := 0.0  ## 0 = composed, human; 1 = composure lost (stiff, simultaneous, fast)
var body_offset_goal := Vector3.ZERO  ## root motion of the floating figure (own spring: recoil, drift)
var _body_spring := NCSpring.new(1.4, 0.45, 0.0, Vector3.ZERO)
var breath_depth := 1.0
var breath_rate := 0.22  ## Hz

var _gaze_springs: Array[NCSpring] = []
var _gaze_targets: Array[Node3D] = []
var _reach_spring: NCSpring
var _reach_target: Node3D
var _pole: Node3D
var _weight_spring: NCSpring
var _scalar := NCSpring.new(1.2, 1.0, 0.0)

## Measurements (µs of the last frame).
var tree_us := 0
var modifiers_us := 0
var _stamp: NCStamp


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.88, 0.84)
	mat.roughness = 0.45
	mat.rim_enabled = true
	mat.rim = 0.4
	body = MikuRig.build(mat)
	add_child(body)
	body.scale = Vector3.ONE * SCALE
	body.position = Vector3(0, WAIST_Y, 0)
	sk = MikuRig.get_skeleton(body)
	sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_build_tree()
	_build_modifiers()
	index_tip = _attach("index.tip.R")
	index_tip_l = _attach("index.tip.L")


func _attach(bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	sk.add_child(a)
	a.bone_name = bone
	var tip := Node3D.new()
	tip.name = "Tip"
	a.add_child(tip)
	tip.position = Vector3.ZERO
	return a


func _curve_ease() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0), 0.0, 0.0)
	c.add_point(Vector2(1, 1), 0.0, 0.0)
	return c


func _build_tree() -> void:
	var lib := AnimationLibrary.new()
	var st := NCPoses.body_states(sk)
	for k: StringName in st:
		lib.add_animation(k, st[k])
	lib.add_animation(&"breath", NCPoses.breath(sk))
	lib.add_animation(&"flick", NCPoses.flick(sk))
	var sm := AnimationNodeStateMachine.new()
	for s in STATES:
		var an := AnimationNodeAnimation.new()
		an.animation = s
		sm.add_node(s, an)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"calm", start)
	# xfade per edge: composure is lost fast (0.25 s), regained slowly (1.2–1.6 s).
	var edges := [[&"calm", &"focus", 0.9], [&"focus", &"calm", 1.2], [&"focus", &"frustrated", 0.25],
			[&"calm", &"frustrated", 0.25], [&"frustrated", &"recover", 1.2], [&"recover", &"calm", 1.6],
			[&"recover", &"focus", 1.0], [&"recover", &"frustrated", 0.3]]
	for e: Array in edges:
		var t := AnimationNodeStateMachineTransition.new()
		t.xfade_time = e[2]
		t.xfade_curve = _curve_ease()
		sm.add_transition(e[0], e[1], t)
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"state", sm)
	var br := AnimationNodeAnimation.new()
	br.animation = &"breath"
	bt.add_node(&"breath", br)
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"breath_rate", ts)
	var add := AnimationNodeAdd2.new()
	add.sync = true  # probe: with sync=false a zero-weight layer's clock stops
	add.filter_enabled = true
	for b: String in BREATH_BONES:
		add.set_filter_path(NodePath("Skeleton3D:" + b), true)
	bt.add_node(&"breath_add", add)
	var fl := AnimationNodeAnimation.new()
	fl.animation = &"flick"
	bt.add_node(&"flick", fl)
	var os := AnimationNodeOneShot.new()
	os.filter_enabled = true
	for b: String in GESTURE_BONES:
		os.set_filter_path(NodePath("Skeleton3D:" + b), true)
	os.fadein_time = 0.08
	os.fadeout_time = 0.35
	bt.add_node(&"gesture", os)
	bt.connect_node(&"breath_rate", 0, &"breath")
	bt.connect_node(&"breath_add", 0, &"state")
	bt.connect_node(&"breath_add", 1, &"breath_rate")
	bt.connect_node(&"gesture", 0, &"breath_add")
	bt.connect_node(&"gesture", 1, &"flick")
	bt.connect_node(&"output", 0, &"gesture")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	body.add_child(tree)
	tree.add_animation_library(&"", lib)
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	tree.advance(0.0)
	playback = tree.get("parameters/state/playback")


func _target(n: String, p: Vector3) -> Node3D:
	var t := Node3D.new()
	t.name = n
	add_child(t)
	t.global_position = p
	return t


func _build_modifiers() -> void:
	_stamp = NCStamp.new()
	_stamp.name = "Stamp"
	sk.add_child(_stamp)
	for st: Array in GAZE_STAGES:
		var tgt := _target("Gaze_" + String(st[0]), gaze_goal)
		_gaze_targets.append(tgt)
		_gaze_springs.append(NCSpring.new(float(st[3]), 0.75, 0.0, gaze_goal))
		var l := LookAtModifier3D.new()
		l.name = "Look_" + String(st[0])
		sk.add_child(l)
		l.bone_name = st[0]
		l.relative = true  # 4.7 default false discards the animated pose of the bone (probe)
		l.influence = st[1]
		l.use_angle_limitation = true
		l.symmetry_limitation = true
		l.primary_limit_angle = deg_to_rad(float(st[2]))
		l.secondary_limit_angle = deg_to_rad(float(st[2]) * 0.7)
		l.target_node = l.get_path_to(tgt)
		looks.append(l)
	_reach_target = _target("ReachTarget", reach_goal)  # world space (the rig is scaled: modifiers use globals)
	_reach_spring = NCSpring.new(1.1, 0.7, -0.35, reach_goal)  # r < 0: anticipation
	_weight_spring = NCSpring.new(1.0, 0.9, 0.0, Vector3.ZERO)
	_pole = _target("ElbowPole", Vector3(-0.7, 1.1, -0.5))
	arm_ik = TwoBoneIK3D.new()
	arm_ik.name = "ArmIK_R"
	sk.add_child(arm_ik)
	arm_ik.setting_count = 1
	arm_ik.set_root_bone_name(0, "upper_arm.R")
	arm_ik.set_middle_bone_name(0, "forearm.R")
	arm_ik.set_end_bone_name(0, "hand.R")
	arm_ik.set_target_node(0, arm_ik.get_path_to(_reach_target))
	arm_ik.set_pole_node(0, arm_ik.get_path_to(_pole))  # probe: without a pole node it does nothing
	arm_ik.influence = 0.0
	index_aim = AimModifier3D.new()
	index_aim.name = "IndexAim_R"
	sk.add_child(index_aim)
	index_aim.setting_count = 1
	index_aim.set_apply_bone_name(0, "index.0.R")
	index_aim.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	index_aim.set_forward_axis(0, SkeletonModifier3D.BONE_AXIS_PLUS_Y)  # contract: +Y joint -> child
	index_aim.set_amount(0, 0.0)
	# candy-wrapper: the wrist twist is spread over forearm + hand (probe: needs the twist source past
	# the end bone — here middle.0.R — and twist_from_rest, or it produces garbage)
	twist = BoneTwistDisperser3D.new()
	twist.name = "TwistDisperser_R"
	sk.add_child(twist)
	twist.setting_count = 1
	twist.set_root_bone_name(0, "forearm.R")
	twist.set_end_bone_name(0, "middle.0.R")
	twist.set_twist_from_rest(0, true)
	twist.set_disperse_mode(0, BoneTwistDisperser3D.DISPERSE_MODE_WEIGHTED)
	limiter = LimitAngularVelocityModifier3D.new()
	limiter.name = "LimitAngVel"
	sk.add_child(limiter)
	limiter.chain_count = 2
	limiter.set_root_bone_name(0, "spine")
	limiter.set_end_bone_name(0, "head")
	limiter.set_root_bone_name(1, "upper_arm.R")
	limiter.set_end_bone_name(1, "hand.R")
	limiter.max_angular_velocity = deg_to_rad(400.0)
	springs = SpringBoneSimulator3D.new()
	springs.name = "Secondary"
	sk.add_child(springs)
	# [root, end, extend length (rig units), stiffness, drag, gravity]
	var chains := [["skirt.0", "skirt.2", 1.2, 1.6, 0.4, 0.3]]
	for side in ["L", "R"]:
		for f: String in FINGERS:
			chains.append(["%s.0.%s" % [f, side], "%s.tip.%s" % [f, side], 0.0, 4.0, 0.55, 0.0])
	springs.setting_count = chains.size()
	for i in range(chains.size()):
		var c: Array = chains[i]
		springs.set_root_bone_name(i, c[0])
		springs.set_end_bone_name(i, c[1])
		if float(c[2]) > 0.0:
			springs.set_extend_end_bone(i, true)
			springs.set_end_bone_length(i, c[2])
		springs.set_stiffness(i, c[3])
		springs.set_drag(i, c[4])
		springs.set_gravity(i, c[5])
	springs.modification_processed.connect(_on_modifiers_done)


func _on_modifiers_done() -> void:
	modifiers_us = Time.get_ticks_usec() - _stamp.stamp_us


func travel(state: StringName) -> void:
	mood = state
	playback.travel(state)


func fire_gesture() -> void:
	tree.set("parameters/gesture/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## One motion step (the director calls it once per frame with the MotionClock dt).
func step(dt: float) -> void:
	# targets with mass: gaze stages chase the goal at their own speed (overlap); rigid = locked block
	for i in range(_gaze_springs.size()):
		var st: Array = GAZE_STAGES[i]
		var f := lerpf(float(st[3]), float(st[4]), rigidity)
		_gaze_springs[i].tune(f, lerpf(0.72, 1.0, rigidity), 0.0)
		_gaze_targets[i].global_position = _gaze_springs[i].step(gaze_goal, dt)
	_reach_spring.tune(lerpf(1.1, 3.0, rigidity), lerpf(0.65, 1.0, rigidity), lerpf(-0.35, 0.0, rigidity))
	_reach_target.global_position = _reach_spring.step(reach_goal, dt)
	var w := _weight_spring.step(Vector3(reach_weight, aim_weight, breath_depth), dt)
	arm_ik.influence = clampf(w.x, 0.0, 1.0)
	index_aim.set_amount(0, clampf(w.y, 0.0, 1.0))
	if aim_node != null:
		index_aim.set_reference_node(0, index_aim.get_path_to(aim_node))
	limiter.max_angular_velocity = deg_to_rad(lerpf(300.0, 900.0, rigidity))
	tree.set("parameters/breath_add/add_amount", clampf(w.z, 0.0, 1.5))
	tree.set("parameters/breath_rate/scale", breath_rate)
	body.position = Vector3(0, WAIST_Y, 0) + _body_spring.step(body_offset_goal, dt)
	var t0 := Time.get_ticks_usec()
	tree.advance(dt)
	tree_us = Time.get_ticks_usec() - t0
	sk.advance(dt)


func tip_position() -> Vector3:
	return index_tip.get_node("Tip").global_position


func tip_position_l() -> Vector3:
	return index_tip_l.get_node("Tip").global_position
