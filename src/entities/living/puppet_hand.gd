class_name PuppetHand
extends Node3D
## One puppet hand (Loop 5): a tool without will, moved only by MIKU through an intent thread.
## Owner: animator. Rig: the procedural-modeler's `HandRig.build(side)` when it exists, else the
## development stand-in HandMannequin; either is rescaled so wrist -> middle fingertip =
## HAND_LENGTH and oriented by its own rest axes (FingerSet), so any rig works.
##
## Weight (HandDynamics): the hand has a mass; it accelerates and brakes within the force the
## thread gives it (max acceleration = force / mass) and its spring is slower the heavier it is.
## With no tension on its thread it only coasts and settles where it is — it never moves by
## itself. `pull` (0..1) is the thread's tension, set every frame by the runtime.
## Fingers: curls of a HandPoses pose (open, cup, pinch, fist, push, smooth...) through per-finger
## springs with lag (overlap); the fingers answer a little after the hand starts to move.
## Presence (0..1): materialises from light when summoned, dissolves when released (material
## `presence`, and a slight growth from APPEAR_SCALE). `effort` follows the pull (material).

signal settled

const HAND_LENGTH := 1.45
const APPEAR_SCALE := 0.82
## Mass (relative) and the spring it gives at full pull: f = BASE_F / sqrt(mass).
const DEFAULT_MASS := 1.0
const BASE_F := 0.62
const ZETA := 0.78
## Acceleration (units/s²) a full pull gives a unit mass.
const FORCE := 7.0
## Coasting drag when the thread is slack (1/s).
const COAST_DRAG := 1.6
## Presence spring (Hz) and finger spring character.
const PRESENCE_F := 0.7
const FINGER := Vector3(1.4, 0.7, 0.4)
const TURN := Vector3(0.55, 0.85, 0.0)

var index := 0
var left := false
var mass := DEFAULT_MASS
var rig_root: Node3D
var skeleton: Skeleton3D
var pose_rig: PoseRig
var fingers: FingerSet
var using_fallback := false
var material: Material

## Goals.
var goal_pos := Vector3.ZERO
var goal_point := Vector3.FORWARD
var goal_palm := Vector3.DOWN
var goal_pose: StringName = &"open"
var goal_presence := 0.0
## Thread tension on this hand now (0..1).
var pull := 0.0
## Extra speed of the current move (an angry MIKU drives harder).
var drive := 1.0

## State.
var active := false
var presence := SecondOrder.new(PRESENCE_F, 1.0, 0.0, 0.0)
var motion := SecondOrder3.new(BASE_F, ZETA, 0.0)
var point_s := SecondOrder3.new(TURN.x, TURN.y, TURN.z, Vector3.FORWARD)
var palm_s := SecondOrder3.new(TURN.x, TURN.y, TURN.z, Vector3.DOWN)
var curls: Array[SecondOrder] = []
var spread := SecondOrder.new(FINGER.x, FINGER.y, FINGER.z, 0.3)
var effort := 0.0

var _scale := 1.0
var _goal_curls := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _cur_curls := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _rest_frame := Basis.IDENTITY
var _anchor_local := Vector3.ZERO
var _rig_offset := Vector3.ZERO
## Wrist -> middle fingertip in the rig's own units (`hand_size` of angelic_hand).
var _hand_size := 1.0
var _was_moving := false
var _applied_presence := -1.0
var _applied_effort := -1.0


func _init(i := 0, is_left := false) -> void:
	index = i
	left = is_left
	name = "PuppetHand%d" % i
	rig_root = build_rig(is_left)
	add_child(rig_root)
	skeleton = MikuBody.find_skeleton(rig_root)
	if skeleton != null:
		pose_rig = PoseRig.new(skeleton)
		fingers = FingerSet.new(pose_rig, RigBones.new(skeleton), "", "palm", 3, is_left)
		var wrist := pose_rig.rest_gpos[0]
		var tip := fingers.tip(2)
		var length := maxf((tip - wrist).length(), 0.001)
		_scale = HAND_LENGTH / length
		# Rig frame: fingers -> local +Z, palm normal -> local -Y (the hand's own axes).
		_rest_frame = LimbIK.frame(fingers.rest_point, -fingers.rest_palm)
		var knuckles := wrist.lerp(tip, 0.48)
		# The hand turns about the middle of the palm; the thread ties on the back of the hand.
		var pivot := wrist.lerp(tip, 0.3)
		rig_root.scale = Vector3.ONE * _scale
		rig_root.position = -pivot * _scale
		_anchor_local = (knuckles - fingers.rest_palm * 0.08 * length - pivot) * _scale
		_rig_offset = rig_root.position
		_hand_size = length
	for k in 5:
		curls.append(SecondOrder.new(FINGER.x * HandPoses.finger_lag(k), FINGER.y, FINGER.z, 0.1))
	_own_material()
	visible = false


## The procedural-modeler's HandRig when present (side "left"/"right"), else the stand-in.
static func build_rig(is_left: bool) -> Node3D:
	var path := MikuBody.global_class_path(&"HandRig")
	if path != "":
		var script := load(path) as Script
		if script != null:
			# HandRig.build(side: HandRig.Side LEFT=0 / RIGHT=1, material).
			var n: Variant = script.call(&"build", 0 if is_left else 1, null)
			if n is Node3D:
				return n
	return HandMannequin.build(is_left)


## Brings the hand into being at `at` (it materialises from light there; no motion yet).
func summon(at: Vector3, point_dir: Vector3, palm_dir: Vector3, pose: StringName = &"open") -> void:
	active = true
	visible = true
	goal_pos = at
	goal_point = point_dir
	goal_palm = palm_dir
	goal_pose = pose
	goal_presence = 1.0
	global_position = at
	motion.reset(at)
	point_s.reset(point_dir.normalized())
	palm_s.reset(palm_dir.normalized())
	HandPoses.curls(&"relaxed", _goal_curls)
	for k in 5:
		curls[k].reset(_goal_curls[k] * 0.6)
	presence.reset(0.0)
	pull = 0.0
	_apply_frame()


## Lets the hand go: it dissolves where it is (the pool reuses it once gone).
func dismiss() -> void:
	goal_presence = 0.0
	pull = 0.0


func is_gone() -> bool:
	return active and goal_presence <= 0.0 and presence.y < 0.02


## Places the hand for reuse (pool).
func park() -> void:
	active = false
	visible = false
	presence.reset(0.0)


func set_goal(p: Vector3, point_dir: Vector3, palm_dir: Vector3, pose: StringName) -> void:
	goal_pos = p
	goal_point = point_dir
	goal_palm = palm_dir
	goal_pose = pose


## World position where an intent thread ties to this hand (back of the hand, over the knuckles).
func anchor() -> Vector3:
	return global_transform * _anchor_local


## World position of a fingertip (thread anchors of an angry, many-threaded control).
func fingertip(f: int) -> Vector3:
	if fingers == null:
		return global_position
	return rig_root.global_transform * (skeleton.transform * fingers.tip(f))


## Distance (units) from the goal.
func error() -> float:
	return (motion.y - goal_pos).length()


func speed() -> float:
	return motion.v.length()


func step(dt: float) -> void:
	if not active:
		return
	presence.step(goal_presence, dt)
	effort = lerpf(effort, pull, 1.0 - exp(-dt / 0.2))
	HandDynamics.step(motion, goal_pos, pull * drive, mass, dt)
	var tf := TURN.x * lerpf(0.25, 1.0, pull) * sqrt(drive) / sqrt(mass)
	point_s.set_params(tf, TURN.y, TURN.z)
	palm_s.set_params(tf, TURN.y, TURN.z)
	point_s.step(goal_point.normalized(), dt)
	palm_s.step(goal_palm.normalized(), dt)
	HandPoses.curls(goal_pose, _goal_curls)
	for k in 5:
		curls[k].set_params(FINGER.x * HandPoses.finger_lag(k) * sqrt(drive), FINGER.y, FINGER.z)
		_cur_curls[k] = curls[k].step(_goal_curls[k], dt)
	spread.step(HandPoses.spread(goal_pose), dt)
	_apply_frame()
	if fingers != null:
		pose_rig.begin()
		fingers.apply(_cur_curls, spread.y)
		pose_rig.solve()
		pose_rig.write()
	_apply_material()
	var moving := speed() > 0.05
	if _was_moving and not moving and error() < 0.15:
		settled.emit()
	_was_moving = moving
	if is_gone():
		park()


func _apply_frame() -> void:
	var b := LimbIK.frame(point_s.y, -palm_s.y) * _rest_frame.inverse()
	var g := lerpf(APPEAR_SCALE, 1.0, clampf(presence.y, 0.0, 1.0))
	global_transform = Transform3D(b.scaled(Vector3.ONE * g), motion.y)


func _apply_material() -> void:
	if material == null:
		return
	var p := clampf(presence.y, 0.0, 1.0)
	if absf(p - _applied_presence) > 0.002:
		_applied_presence = p
		LivingMaterials.set_param(material, &"presence", p)
	if absf(effort - _applied_effort) > 0.01:
		_applied_effort = effort
		LivingMaterials.set_param(material, &"drive", effort)


## Every mesh of the rig gets this hand's own copy of the hand material (presence/effort are
## per hand).
func _own_material() -> void:
	material = LivingMaterials.get_material(&"hand").duplicate()
	for mi in rig_root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = material
	LivingMaterials.set_param(material, &"presence", 0.0)
	LivingMaterials.set_param(material, &"hand_size", _hand_size)
