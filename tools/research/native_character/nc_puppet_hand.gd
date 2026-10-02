class_name NCPuppetHand
extends Node3D
## SPIKE — a giant puppet hand with its OWN skeleton (the real HandRig, RIGHT side, copied read-only
## from claude/funny-hawking-air6xk @ b8ddadf: fingers +X, palm normal +Y, ~7 u long), driven by a target.
##   body motion (mass, delay, overshoot, lean into acceleration): own spring on the node transform
##     — no native node gives a whole rig mass towards a moving goal;
##   finger pose: own AnimationTree (manual), BlendSpace1D "grip" over key poses open/relaxed/grip;
##   finger follow-through: SpringBoneSimulator3D on the 5 finger chains — the fingers trail when the
##     hand accelerates and settle ON the animated pose (probe: the spring rest is the animated pose);
##   anti-pop: LimitAngularVelocityModifier3D on the fingers.
## Shared resources: the AnimationLibrary and BlendSpace are built once and shared by every hand.

const SIZE := 0.11  ## rig units -> metres (~0.75 m hand: giant next to MIKU)

static var _lib: AnimationLibrary
static var _blend: AnimationNodeBlendSpace1D

var rig: Node3D
var sk: Skeleton3D
var tree: AnimationTree
var fingers: SpringBoneSimulator3D
var limiter: LimitAngularVelocityModifier3D

var goal := Vector3.ZERO
var facing_goal := Vector3(0, 0, 1)
var grip_goal := 0.0
var presence_goal := 0.0
## 0 = calm puppet (heavy, overshooting), 1 = aggressive control (fast, stiff)
var force := 0.0

var _pos: NCSpring
var _face: NCSpring
var _scalars: NCSpring
var presence := 0.0
var velocity := Vector3.ZERO
var _last := Vector3.ZERO


static var _wrist_rest := Vector3.ZERO


static func shared_tree(sk: Skeleton3D) -> AnimationNodeBlendSpace1D:
	if _blend == null:
		_lib = AnimationLibrary.new()
		_wrist_rest = sk.get_bone_global_rest(sk.find_bone("wrist")).origin
		var poses := NCPoses.hand_poses(sk)
		for k: StringName in poses:
			_lib.add_animation(k, poses[k])
		_blend = AnimationNodeBlendSpace1D.new()
		var pts := {&"open": -1.0, &"relaxed": 0.0, &"grip": 1.0}
		for k: StringName in pts:
			var an := AnimationNodeAnimation.new()
			an.animation = k
			_blend.add_blend_point(an, pts[k], -1, k)  # 4.7: unnamed points are deprecated (warning)
	return _blend


func _init(start: Vector3 = Vector3.ZERO) -> void:
	goal = start
	_pos = NCSpring.new(0.8, 0.55, 0.0, start)
	_face = NCSpring.new(0.6, 0.8, 0.0, facing_goal)
	_scalars = NCSpring.new(1.0, 0.85, 0.0, Vector3.ZERO)
	_last = start


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.92, 0.86)
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.92, 0.78)
	mat.emission_energy_multiplier = 0.2
	mat.rim_enabled = true
	rig = HandRig.build(HandRig.Side.RIGHT, mat)
	add_child(rig)
	sk = rig.get_node("Skeleton3D")
	sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	tree = AnimationTree.new()
	rig.add_child(tree)
	shared_tree(sk)
	tree.add_animation_library(&"", _lib)
	tree.tree_root = _blend
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	limiter = LimitAngularVelocityModifier3D.new()
	sk.add_child(limiter)
	fingers = SpringBoneSimulator3D.new()
	sk.add_child(fingers)
	var names := ["thumb", "index", "middle", "ring", "little"]
	fingers.setting_count = names.size()
	limiter.chain_count = names.size()
	for i in range(names.size()):
		fingers.set_root_bone_name(i, "%s.0" % names[i])
		fingers.set_end_bone_name(i, "%s.tip" % names[i])
		fingers.set_stiffness(i, 3.0)
		fingers.set_drag(i, 0.5)
		fingers.set_gravity(i, 0.0)
		limiter.set_root_bone_name(i, "%s.0" % names[i])
		limiter.set_end_bone_name(i, "%s.tip" % names[i])
	limiter.max_angular_velocity = deg_to_rad(360.0)
	global_position = goal
	scale = Vector3.ONE * 0.001


func step(dt: float) -> void:
	_pos.tune(lerpf(0.8, 2.4, force), lerpf(0.55, 0.95, force), lerpf(0.0, 0.6, force))
	_face.tune(lerpf(0.6, 2.0, force), 0.8, 0.0)
	var p := _pos.step(goal, dt)
	velocity = (p - _last) / maxf(dt, 1e-4)
	_last = p
	global_position = p
	var s := _scalars.step(Vector3(presence_goal, grip_goal, 0), dt)
	presence = clampf(s.x, 0.0, 1.2)
	var n := _face.step(facing_goal, dt).normalized()  # palm normal (+Y of the rig) towards the work
	# fingers (+X) hang down-forward; they trail against the velocity: the hand has mass
	var f0 := (Vector3.DOWN * 0.75 + n * 0.25 - _pos.v * lerpf(0.4, 0.12, force)).normalized()
	var x := (f0 - n * f0.dot(n)).normalized()
	if x.length_squared() < 1e-6:
		x = Vector3.DOWN
	var z := x.cross(n).normalized()
	global_transform.basis = Basis(x, n, z).scaled(Vector3.ONE * maxf(presence, 0.001) * SIZE)
	tree.set("parameters/blend_position", clampf(s.y, -1.0, 1.0))
	tree.advance(dt)
	sk.advance(dt)


## Wrist point (where the thread attaches), world space.
func anchor() -> Vector3:
	return global_transform * _wrist_rest


## How hard the hand is being pulled: distance to its goal + speed (feeds the thread's tension).
func pull() -> float:
	return clampf(goal.distance_to(global_position) * 1.2 + velocity.length() * 0.25, 0.0, 1.0)
