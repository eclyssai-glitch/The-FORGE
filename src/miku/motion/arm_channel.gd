class_name ArmChannel
extends RefCounted
## One of MIKU's arms as a set of second-order channels (Loop 5). Owner: animator. Pure.
## Goals (model space of the rig: +Z forward, +X her left) are set by the runtime — a rest pose
## by mood, or a gesture beat of an action — and every channel follows its goal with its own
## spring, so the hand travels, the wrist turns and the fingers close at different rates
## (overlap), with the anticipation and follow-through of the beat itself (ActionScript).
## `stiff` (0 = fluid, 1 = lost composure) retunes the springs: calm = soft, slightly overshooting
## curves; angry = fast, critically damped, dry stops.

## Spring character at stiff 0 and stiff 1: [f (Hz), zeta, r].
const HAND_CALM := Vector3(1.05, 0.62, 0.9)
const HAND_STIFF := Vector3(2.7, 1.0, 0.0)
const WRIST_CALM := Vector3(0.9, 0.6, 0.6)
const WRIST_STIFF := Vector3(3.0, 1.0, 0.0)
const FINGER_CALM := Vector3(1.6, 0.55, 0.6)
const FINGER_STIFF := Vector3(4.5, 1.0, 0.0)
const POLE := Vector3(0.9, 0.8, 0.0)

var side := 0
## +1 for the left arm (+X), -1 for the right.
var sx := 1.0

## Goals.
var goal_pos := Vector3.ZERO
var goal_palm := Vector3.LEFT
var goal_point := Vector3.DOWN
var goal_pole := Vector3.RIGHT
var goal_pose: StringName = &"relaxed"
## Extra spring speed for this beat (>1 = a quick gesture; the mood multiplies it).
var goal_speed := 1.0
## Beat of fingers that moves on top of the pose (beckon, tapping): added curl per finger.
var finger_wave := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])

## Outputs (springs).
var pos := SecondOrder3.new()
var palm := SecondOrder3.new()
var point := SecondOrder3.new()
var pole := SecondOrder3.new()
var curl: Array[SecondOrder] = []
var spread := SecondOrder.new()

var _curl_goal := PackedFloat32Array()


func _init(side_index := 0) -> void:
	side = side_index
	sx = 1.0 if side == 0 else -1.0
	for i in HandPoses.FINGER_COUNT:
		curl.append(SecondOrder.new(1.6, 0.6, 0.5, 0.3))
	HandPoses.curls(&"relaxed", _curl_goal)


## Places every channel on its goal at rest (composition, reset).
func snap() -> void:
	pos.reset(goal_pos)
	palm.reset(goal_palm.normalized())
	point.reset(goal_point.normalized())
	pole.reset(goal_pole.normalized())
	HandPoses.curls(goal_pose, _curl_goal)
	for i in curl.size():
		curl[i].reset(_curl_goal[i])
	spread.reset(HandPoses.spread(goal_pose))


## Sets the goal of the arm (directions need not be normalised).
func set_goal(p: Vector3, palm_dir: Vector3, point_dir: Vector3, pole_dir: Vector3, pose: StringName,
		speed := 1.0) -> void:
	goal_pos = p
	goal_palm = palm_dir
	goal_point = point_dir
	goal_pole = pole_dir
	goal_pose = pose
	goal_speed = speed


func step(dt: float, stiff: float, tempo: float) -> void:
	var k := clampf(stiff, 0.0, 1.0)
	var sp := goal_speed * tempo
	var h := HAND_CALM.lerp(HAND_STIFF, k)
	pos.set_params(h.x * sp, h.y, h.z)
	pos.step(goal_pos, dt)
	var w := WRIST_CALM.lerp(WRIST_STIFF, k)
	palm.set_params(w.x * sp, w.y, w.z)
	point.set_params(w.x * sp, w.y, w.z)
	palm.step(goal_palm.normalized(), dt)
	point.step(goal_point.normalized(), dt)
	pole.set_params(POLE.x * sp, POLE.y, POLE.z)
	pole.step(goal_pole.normalized(), dt)
	HandPoses.curls(goal_pose, _curl_goal)
	var fc := FINGER_CALM.lerp(FINGER_STIFF, k)
	for i in curl.size():
		curl[i].set_params(fc.x * sp * HandPoses.finger_lag(i), fc.y, fc.z)
		curl[i].step(_curl_goal[i] + finger_wave[i], dt)
	spread.set_params(fc.x * sp, fc.y, fc.z)
	spread.step(HandPoses.spread(goal_pose), dt)
