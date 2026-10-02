class_name MikuMotor
extends RefCounted
## MIKU's procedural body in layers over her Skeleton3D (Loop 5, ADR-015). Owner: animator.
## Every layer is a second-order channel (SecondOrder) towards a goal set by the runtime (Miku:
## mind + micro-behaviour + action); nothing is a linear tween and nothing answers in the same
## frame as its cause:
##   breath   - chest rises and opens, shoulders lift, the figure floats; rate and depth by mood
##              (deep and slow when calm, shallow and quick when frustrated, held when angry);
##   weight   - the hips drift and roll to one side, the spine counters, the skirt follows late;
##   gaze     - eyes -> head -> neck -> chest, each stage chasing the previous one's output
##              (the head leads, the chest arrives last); when composure is lost the chain locks
##              into one fast block (the not-human stare);
##   posture  - lean, side lean, chest lift, shoulder raise/forward, head tilt and nod;
##   arms     - two ArmChannels solved by two-bone IK with an elbow pole, wrist frame and fingers;
##   skirt    - three pendulum segments driven by the hips' motion (follow-through).
## `stiff` (MikuMind.rigidity) retunes every spring: calm = soft, slightly overshooting, staggered;
## lost composure = fast, critically damped, simultaneous.
## Goals are in the rig's MODEL space (+Z forward, +X her left); world positions are converted by
## the caller (MikuBody.to_model).

## Share of the gaze each stage of the chain takes (the eyes take what is left).
const SHARE_CHEST := 0.16
const SHARE_NECK := 0.27
const SHARE_HEAD := 0.57
## Gaze range the chain can give (rad): yaw both sides, pitch down / up.
const GAZE_YAW := 1.35
const GAZE_DOWN := 0.85
const GAZE_UP := 0.5
## Gaze springs at stiff 0 / 1: [f, zeta, r]; the neck and chest run at these fractions of the
## head's frequency when calm (1 when stiff: the block).
const EYES_CALM := Vector3(4.0, 0.9, 0.0)
const HEAD_CALM := Vector3(1.25, 0.72, 0.5)
const HEAD_STIFF := Vector3(3.4, 1.0, 0.0)
const NECK_LAG := 0.72
const CHEST_LAG := 0.45
## Posture springs [f, zeta, r] at stiff 0 / 1.
const POSTURE_CALM := Vector3(0.55, 0.8, 0.0)
const POSTURE_STIFF := Vector3(2.2, 1.0, 0.0)
## Body turn (the whole floating figure pivots): heavy, slow.
const TURN := Vector3(0.32, 0.9, 0.0)
const TURN_STIFF := Vector3(0.9, 1.0, 0.0)
## Weight shift: hip drift (units) and roll (rad) at weight_side = 1.
const HIP_DRIFT := 0.055
const HIP_ROLL := 0.07
const WEIGHT := Vector3(0.35, 0.85, 0.0)
## Breath: chest pitch (rad, opening back), shoulder lift (rad), float (units) at depth 1.
const BREATH_CHEST := 0.035
const BREATH_SHOULDER := 0.035
const BREATH_FLOAT := 0.018
## Slow float of the figure (units, s): she hovers.
const FLOAT_AMP := 0.035
const FLOAT_PERIOD := Palette.T_BREATH_SLOW
## Skirt pendulums: [f, zeta] and how much hip velocity (units/s) tilts the first segment (rad).
const SKIRT := Vector2(0.55, 0.32)
const SKIRT_GAIN := 1.4
const SKIRT_CASCADE := 0.85
## Wrist: largest bend between the forearm and the fingers (rad).
const WRIST_LIMIT := 1.05
## Eye height above the head bone, in rest model units.
const EYE_ABOVE_HEAD := 0.27

var map: RigBones
var rig: PoseRig
var arms: Array[ArmChannel] = []
var fingers: Array[FingerSet] = []

## Goals (model space / radians).
var gaze_point := Vector3(0.0, 1.3, 6.0)
var body_turn := 0.0
var lean := 0.0
var lean_side := 0.0
var chest_lift := 0.0
var shoulder_raise := 0.0
var shoulder_fwd := 0.0
var head_tilt := 0.0
var head_nod := 0.0
var weight_side := 0.0
var breath_rate := 1.0 / Palette.T_BREATH
var breath_depth := 1.0
var float_amount := 1.0
## 0 = composed, 1 = lost composure (MikuMind.rigidity()).
var stiff := 0.0
var tempo := 1.0
## Native torso (migration STEP 1, MikuBody layer `torso`): the AnimationTree (MikuDirector)
## poses hips, spine, chest, neck, head and clavicles before step(); this class reads that pose
## and only adds the gaze chain to it (turn, float, arms, fingers and skirt stay here).
var torso_native := false
## Seconds of motion time (ambient float).
var time := 0.0

## Outputs.
var breath := 0.0
var breath_phase := 0.0
var gaze_yaw := 0.0
var gaze_pitch := 0.0
## Model-space point the eyes look from and their direction (after the chain).
var eye_pos := Vector3.ZERO
var eye_dir := Vector3.BACK

# Bones.
var b_root := -1
var b_hips := -1
var b_spine := -1
var b_chest := -1
var b_neck := -1
var b_head := -1
var b_clav := PackedInt32Array([-1, -1])
var b_ua := PackedInt32Array([-1, -1])
var b_fa := PackedInt32Array([-1, -1])
var b_hand := PackedInt32Array([-1, -1])
var b_eye := PackedInt32Array([-1, -1])
var b_skirt := PackedInt32Array()

# Arm rest data per side.
var _l1 := PackedFloat32Array([0.5, 0.5])
var _l2 := PackedFloat32Array([0.5, 0.5])
var _rest_ua := PackedVector3Array([Vector3.DOWN, Vector3.DOWN])
var _rest_fa := PackedVector3Array([Vector3.DOWN, Vector3.DOWN])
var _rest_bend := PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT])

# Springs.
var _eye_y := SecondOrder.new()
var _eye_p := SecondOrder.new()
var _head_y := SecondOrder.new()
var _head_p := SecondOrder.new()
var _neck_y := SecondOrder.new()
var _neck_p := SecondOrder.new()
var _chest_y := SecondOrder.new()
var _chest_p := SecondOrder.new()
var _turn := SecondOrder.new()
var _lean := SecondOrder.new()
var _lean_side := SecondOrder.new()
var _chest_lift := SecondOrder.new()
var _sh_raise := SecondOrder.new()
var _sh_fwd := SecondOrder.new()
var _tilt := SecondOrder.new()
var _nod := SecondOrder.new()
var _hip := SecondOrder.new()
var _skirt_x: Array[SecondOrder] = []
var _skirt_z: Array[SecondOrder] = []
var _depth := SecondOrder.new(0.4, 1.0, 0.0, 1.0)
var _last_hip := Vector3.ZERO
var _hip_vel := Vector3.ZERO
var _turn_vel := 0.0
var _last_turn := 0.0
var _curls := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _snap := true
var _posture: Array[SecondOrder] = []


func _init(skel: Skeleton3D, bone_map: RigBones = null) -> void:
	map = bone_map if bone_map != null else RigBones.new(skel)
	rig = PoseRig.new(skel)
	b_root = map.bone("root")
	b_hips = map.bone("hips")
	b_spine = map.bone("spine")
	b_chest = map.bone("chest")
	b_neck = map.bone("neck")
	b_head = map.bone("head")
	for s in 2:
		var side: String = RigBones.SIDES[s]
		b_clav[s] = map.bone("clavicle." + side)
		b_ua[s] = map.bone("upper_arm." + side)
		b_fa[s] = map.bone("forearm." + side)
		b_hand[s] = map.bone("hand." + side)
		b_eye[s] = map.bone("eye." + side)
		arms.append(ArmChannel.new(s))
		fingers.append(FingerSet.new(rig, map, side, "hand." + side, 2, s == 0))
		_measure_arm(s)
		if b_ua[s] >= 0:
			rig.set_hook(b_ua[s], _solve_arm)
	for k in 3:
		var sb := map.bone("skirt.%d" % k)
		if sb >= 0:
			b_skirt.append(sb)
			_skirt_x.append(SecondOrder.new(SKIRT.x, SKIRT.y, 0.0))
			_skirt_z.append(SecondOrder.new(SKIRT.x, SKIRT.y, 0.0))
	_turn.set_params(TURN.x, TURN.y, TURN.z)
	_hip.set_params(WEIGHT.x, WEIGHT.y, WEIGHT.z)
	_posture = [_lean, _lean_side, _chest_lift, _sh_raise, _sh_fwd, _tilt, _nod]


## Arm lengths and rest directions of side s (from the skeleton's rests).
func _measure_arm(s: int) -> void:
	if b_ua[s] < 0 or b_fa[s] < 0 or b_hand[s] < 0:
		return
	var ua := rig.rest_gpos[b_ua[s]]
	var fa := rig.rest_gpos[b_fa[s]]
	var hd := rig.rest_gpos[b_hand[s]]
	_l1[s] = (fa - ua).length()
	_l2[s] = (hd - fa).length()
	_rest_ua[s] = (fa - ua).normalized()
	_rest_fa[s] = (hd - fa).normalized()
	var bend := _rest_ua[s].cross(_rest_fa[s])
	if bend.length_squared() < 1e-6:
		# Straight at rest: the elbow bends backwards, the hinge is horizontal.
		bend = _rest_ua[s].cross(Vector3.BACK)
	_rest_bend[s] = bend.normalized()


## The rig's rests changed (appearance): re-read them.
func refresh_rest() -> void:
	rig.refresh_rest()
	for s in 2:
		_measure_arm(s)


## True when the rig has what the body layers need (spine chain and both arms).
func complete() -> bool:
	return b_chest >= 0 and b_head >= 0 and b_ua[0] >= 0 and b_ua[1] >= 0 and b_hand[0] >= 0 and b_hand[1] >= 0


## Model position of the shoulder (upper arm head) of side s, at rest.
func shoulder_rest(s: int) -> Vector3:
	return rig.rest_gpos[b_ua[s]] if b_ua[s] >= 0 else Vector3(0.3 * (1.0 if s == 0 else -1.0), 0.9, 0.0)


func arm_length(s: int) -> float:
	return _l1[s] + _l2[s]


## Rest model position of the head bone (gaze origin reference).
func head_rest() -> Vector3:
	return rig.rest_gpos[b_head] if b_head >= 0 else Vector3(0.0, 1.2, 0.0)


## Current yaw of the whole figure (rad).
func turn() -> float:
	return _turn.y


## Next step snaps every channel to its goal (composition).
func snap_next() -> void:
	_snap = true


func step(dt: float) -> void:
	time += dt
	var k := clampf(stiff, 0.0, 1.0)
	if _snap:
		_snap_all()
	_step_breath(dt, k)
	_step_posture(dt, k)
	_step_gaze(dt, k)
	for a in arms:
		a.step(dt, k, tempo)
	_compose(dt)
	rig.solve()
	_measure_eyes()
	rig.write()
	_snap = false


func _snap_all() -> void:
	_turn.reset(body_turn)
	_lean.reset(lean)
	_lean_side.reset(lean_side)
	_chest_lift.reset(chest_lift)
	_sh_raise.reset(shoulder_raise)
	_sh_fwd.reset(shoulder_fwd)
	_tilt.reset(head_tilt)
	_nod.reset(head_nod)
	_hip.reset(weight_side)
	var yp := _gaze_goal()
	for s in [_eye_y, _head_y, _neck_y, _chest_y]:
		(s as SecondOrder).reset(yp.x)
	for s in [_eye_p, _head_p, _neck_p, _chest_p]:
		(s as SecondOrder).reset(yp.y)
	for a in arms:
		a.snap()
	for s in _skirt_x:
		s.reset(0.0)
	for s in _skirt_z:
		s.reset(0.0)
	_last_turn = body_turn
	_hip_vel = Vector3.ZERO


func _step_breath(dt: float, k: float) -> void:
	_depth.step(breath_depth, dt)
	breath_phase = fmod(breath_phase + dt * maxf(breath_rate, 0.01), 1.0)
	# Inhale over the first 40 % of the cycle, a longer exhale (eased, never a sine loop).
	var ph := breath_phase
	var b := 0.0
	if ph < 0.4:
		b = Tween.interpolate_value(0.0, 1.0, ph / 0.4, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	else:
		b = Tween.interpolate_value(1.0, -1.0, (ph - 0.4) / 0.6, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	breath = b * _depth.y * lerpf(1.0, 0.35, k)


func _step_posture(dt: float, k: float) -> void:
	var pc := POSTURE_CALM.lerp(POSTURE_STIFF, k)
	var f := pc.x * tempo
	for s in _posture:
		s.set_params(f, pc.y, pc.z)
	_lean.step(lean, dt)
	_lean_side.step(lean_side, dt)
	_chest_lift.step(chest_lift, dt)
	_sh_raise.step(shoulder_raise, dt)
	_sh_fwd.step(shoulder_fwd, dt)
	_tilt.step(head_tilt, dt)
	_nod.step(head_nod, dt)
	var t := TURN.lerp(TURN_STIFF, k)
	_turn.set_params(t.x * sqrt(tempo), t.y, t.z)
	_turn.step(body_turn, dt)
	_hip.step(weight_side, dt)


## Gaze goal (yaw, pitch) relative to the turned body, clamped to what the chain can give.
func _gaze_goal() -> Vector2:
	var from := eye_pos if eye_pos != Vector3.ZERO else head_rest() + Vector3(0.0, EYE_ABOVE_HEAD, 0.0)
	var d := gaze_point - from
	d = Quaternion(Vector3.UP, -_turn.y) * d
	var yp := LimbIK.yaw_pitch(d)
	return Vector2(clampf(yp.x, -GAZE_YAW, GAZE_YAW), clampf(yp.y, -GAZE_UP, GAZE_DOWN))


func _step_gaze(dt: float, k: float) -> void:
	var goal := _gaze_goal()
	var h := HEAD_CALM.lerp(HEAD_STIFF, k)
	var hf := h.x * sqrt(tempo)
	_eye_y.set_params(EYES_CALM.x, EYES_CALM.y, EYES_CALM.z)
	_eye_p.set_params(EYES_CALM.x, EYES_CALM.y, EYES_CALM.z)
	_head_y.set_params(hf, h.y, h.z)
	_head_p.set_params(hf, h.y, h.z)
	var nl := lerpf(NECK_LAG, 1.0, k)
	var cl := lerpf(CHEST_LAG, 1.0, k)
	_neck_y.set_params(hf * nl, h.y, h.z)
	_neck_p.set_params(hf * nl, h.y, h.z)
	_chest_y.set_params(hf * cl, lerpf(0.85, 1.0, k), 0.0)
	_chest_p.set_params(hf * cl, lerpf(0.85, 1.0, k), 0.0)
	# The chain: each stage chases the previous stage's output (overlap by construction).
	_eye_y.step(goal.x, dt)
	_eye_p.step(goal.y, dt)
	_head_y.step(_eye_y.y, dt)
	_head_p.step(_eye_p.y, dt)
	_neck_y.step(_head_y.y, dt)
	_neck_p.step(_head_p.y, dt)
	_chest_y.step(_neck_y.y, dt)
	_chest_p.step(_neck_p.y, dt)
	gaze_yaw = _eye_y.y
	gaze_pitch = _eye_p.y


func _compose(dt: float) -> void:
	rig.begin()
	var fl := sin(time * TAU / FLOAT_PERIOD) * FLOAT_AMP * float_amount + breath * BREATH_FLOAT
	var hip_x := _hip.y * HIP_DRIFT
	rig.root_offset = Vector3(hip_x, fl, 0.0)
	var hip_now := Vector3(hip_x, fl, 0.0)
	if dt > 0.0:
		_hip_vel = _hip_vel.lerp((hip_now - _last_hip) / dt, 1.0 - exp(-dt / 0.15))
		_turn_vel = lerpf(_turn_vel, (_turn.y - _last_turn) / dt, 1.0 - exp(-dt / 0.15))
	_last_hip = hip_now
	_last_turn = _turn.y
	var roll := _hip.y * HIP_ROLL
	var root := b_root if b_root >= 0 else b_hips
	rig.set_rel(root, LimbIK.euler(0.0, _turn.y, 0.0))
	var ch_y := _chest_y.y * SHARE_CHEST
	var ch_p := _chest_p.y * SHARE_CHEST
	if torso_native:
		# The AnimationTree posed the torso (mood, composure, posture, weight, breath) this frame;
		# the gaze chain (still this class's, migration step 2) turns it from there.
		if b_hips >= 0 and b_hips != root:
			rig.set_rel(b_hips, rig.rel_from_skeleton(b_hips))
		elif b_hips >= 0:
			rig.add_rel(b_hips, rig.rel_from_skeleton(b_hips))
		_torso(b_spine, 0.0, ch_y * 0.4)
		_torso(b_chest, ch_p, ch_y * 0.6)
		_torso(b_neck, _neck_p.y * SHARE_NECK, _neck_y.y * SHARE_NECK)
		_torso(b_head, _head_p.y * SHARE_HEAD, _head_y.y * SHARE_HEAD)
	else:
		if b_hips >= 0 and b_hips != root:
			rig.set_rel(b_hips, LimbIK.euler(0.0, 0.0, roll))
		elif b_hips >= 0:
			rig.add_rel(b_hips, LimbIK.euler(0.0, 0.0, roll))
		rig.set_rel(b_spine, LimbIK.euler(_lean.y * 0.45 - _chest_lift.y * 0.25 - breath * BREATH_CHEST * 0.3,
			ch_y * 0.4, -roll * 0.7 + _lean_side.y * 0.5))
		rig.set_rel(b_chest, LimbIK.euler(_lean.y * 0.4 - _chest_lift.y * 0.45 - breath * BREATH_CHEST + ch_p,
			ch_y * 0.6, -roll * 0.45 + _lean_side.y * 0.5))
		# The neck keeps the head over the body while she leans (a dancer's carriage).
		rig.set_rel(b_neck, LimbIK.euler(_neck_p.y * SHARE_NECK - _lean.y * 0.35 + _chest_lift.y * 0.3,
			_neck_y.y * SHARE_NECK, roll * 0.3))
		rig.set_rel(b_head, LimbIK.euler(_head_p.y * SHARE_HEAD + _nod.y, _head_y.y * SHARE_HEAD, _tilt.y))
	# Eyes take what the chain does not give yet (only rigs with eye bones show it).
	var given_y := ch_y + _neck_y.y * SHARE_NECK + _head_y.y * SHARE_HEAD
	var given_p := ch_p + _neck_p.y * SHARE_NECK + _head_p.y * SHARE_HEAD
	for s in 2:
		if b_eye[s] >= 0:
			rig.set_rel(b_eye[s], LimbIK.euler(clampf(_eye_p.y - given_p, -0.4, 0.4),
				clampf(_eye_y.y - given_y, -0.6, 0.6), 0.0))
		var sx := 1.0 if s == 0 else -1.0
		if torso_native:
			if b_clav[s] >= 0:
				rig.set_rel(b_clav[s], rig.rel_from_skeleton(b_clav[s]))
		else:
			var raise := _sh_raise.y * 0.2 + breath * BREATH_SHOULDER
			rig.set_rel(b_clav[s], LimbIK.euler(0.0, -sx * _sh_fwd.y * 0.25, sx * raise))
		var a := arms[s]
		fingers[s].apply(_finger_curls(a), a.spread.y)
	# Skirt: pendulums driven by the hips' motion and the body's turn, cascading down.
	var drive_x := clampf(-_hip_vel.z * SKIRT_GAIN, -0.3, 0.3)
	var drive_z := clampf(_hip_vel.x * SKIRT_GAIN + _turn_vel * 0.05, -0.3, 0.3)
	var prev_x := drive_x - roll * 0.5
	var prev_z := drive_z - roll * 0.6
	for i in b_skirt.size():
		_skirt_x[i].step(prev_x, dt)
		_skirt_z[i].step(prev_z, dt)
		rig.set_rel(b_skirt[i], LimbIK.euler(_skirt_x[i].y * (1.0 if i == 0 else 0.6),
			0.0, _skirt_z[i].y * (1.0 if i == 0 else 0.6)))
		prev_x = _skirt_x[i].y * SKIRT_CASCADE
		prev_z = _skirt_z[i].y * SKIRT_CASCADE


## Native torso: the tree's pose of `b` with the gaze stage's pitch/yaw over it.
func _torso(b: int, pitch: float, yaw: float) -> void:
	if b >= 0:
		rig.set_rel(b, LimbIK.euler(pitch, yaw, 0.0) * rig.rel_from_skeleton(b))


func _finger_curls(a: ArmChannel) -> PackedFloat32Array:
	for i in 5:
		_curls[i] = a.curl[i].y
	return _curls


## IK hook: runs when the upper arm's position is known (its parents are posed).
func _solve_arm(bone: int) -> void:
	var s := 0 if bone == b_ua[0] else 1
	var a := arms[s]
	var sh := rig.pos[bone]
	var target := a.pos.y
	var elbow := LimbIK.elbow(sh, target, _l1[s], _l2[s], a.pole.y)
	var u1 := (elbow - sh).normalized()
	var reach := target - elbow
	var u2 := reach.normalized() if reach.length_squared() > 1e-10 else u1
	var bend := u1.cross(u2)
	if bend.length_squared() < 1e-8:
		bend = rig.acc[rig.parent[bone]] * _rest_bend[s] if rig.parent[bone] >= 0 else _rest_bend[s]
	bend = bend.normalized()
	var q_ua := LimbIK.align(_rest_ua[s], _rest_bend[s], u1, bend)
	var q_fa := LimbIK.align(_rest_fa[s], _rest_bend[s], u2, bend)
	rig.set_abs(b_ua[s], q_ua)
	rig.set_abs(b_fa[s], q_fa)
	# Wrist: the fingers' direction, kept within WRIST_LIMIT of the forearm, and the palm.
	var fs := fingers[s]
	var pt := a.point.y.normalized() if a.point.y.length_squared() > 1e-8 else u2
	var ang := u2.angle_to(pt)
	if ang > WRIST_LIMIT:
		pt = u2.slerp(pt, WRIST_LIMIT / ang).normalized()
	rig.set_abs(b_hand[s], LimbIK.align(fs.rest_point, fs.rest_palm, pt, a.palm.y))


func _measure_eyes() -> void:
	if b_head < 0:
		return
	eye_pos = rig.point_of(b_head, head_rest() + Vector3(0.0, EYE_ABOVE_HEAD, 0.0))
	eye_dir = Quaternion(Vector3.UP, _turn.y) * (LimbIK.euler(_eye_p.y, _eye_y.y, 0.0) * Vector3.BACK)


## Model position of MIKU's index fingertip of side s (thread origin), after step().
func fingertip(s: int, finger := 1) -> Vector3:
	return fingers[s].tip(finger)


func hand_pos(s: int) -> Vector3:
	return rig.pos[b_hand[s]] if b_hand[s] >= 0 else Vector3.ZERO


func head_pos() -> Vector3:
	return rig.pos[b_head] if b_head >= 0 else Vector3.ZERO


func chest_pos() -> Vector3:
	return rig.pos[b_chest] if b_chest >= 0 else Vector3.ZERO
