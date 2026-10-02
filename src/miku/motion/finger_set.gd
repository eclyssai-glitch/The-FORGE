class_name FingerSet
extends RefCounted
## The five fingers of one hand on a PoseRig (Loop 5): curl and spread in the hand's own rest
## axes, for MIKU's hands (2 segments per finger) and the puppet hands (3). Owner: animator.
## Axes come from the rest pose only, so any rig works: the finger's direction (base -> next
## segment), the palm normal (anatomical rule: left palm = fingers × thumb side, right = the
## opposite) and the lateral direction away from the middle finger (spread).

var rig: PoseRig
## bones[f] = segment bone indices of finger f (thumb, index, middle, ring, little), -1 = missing.
var bones: Array[PackedInt32Array] = []
## Rest-model curl axis and spread axis per finger.
var curl_axis := PackedVector3Array()
var spread_axis := PackedVector3Array()
## Rest finger direction of the middle finger and rest palm normal (out of the palm).
var rest_point := Vector3.DOWN
var rest_palm := Vector3.LEFT
var hand_bone := -1
## Rest length of the last segment of each finger (estimated from the previous one).
var tip_len := PackedFloat32Array()


## `side` "L"/"R" for MIKU (keys finger.side.seg), "" for a puppet hand of handedness
## `left` (keys finger.seg).
func _init(pose_rig: PoseRig, map: RigBones, side: String, hand_key: String, segments: int, left: bool) -> void:
	rig = pose_rig
	hand_bone = map.bone(hand_key)
	curl_axis.resize(5)
	spread_axis.resize(5)
	tip_len.resize(5)
	for f in 5:
		var segs := PackedInt32Array()
		for k in segments:
			segs.append(map.bone(RigBones.finger_key(RigBones.FINGERS[f], side, k)))
		bones.append(segs)
	var mid := _dir(2)
	if mid != Vector3.ZERO:
		rest_point = mid
	elif hand_bone >= 0:
		rest_point = Vector3.DOWN
	var thumb_side := _base(0) - _base(2)
	thumb_side -= rest_point * thumb_side.dot(rest_point)
	if thumb_side.length_squared() < 1e-8:
		thumb_side = Vector3.FORWARD
	thumb_side = thumb_side.normalized()
	rest_palm = rest_point.cross(thumb_side).normalized()
	if not left:
		rest_palm = -rest_palm
	for f in 5:
		var d := _dir(f)
		if d == Vector3.ZERO:
			d = rest_point
		var ax := d.cross(rest_palm)
		curl_axis[f] = ax.normalized() if ax.length_squared() > 1e-8 else Vector3.RIGHT
		var lat := _base(f) - _base(2)
		lat -= d * lat.dot(d)
		var sa := d.cross(lat)
		spread_axis[f] = sa.normalized() if sa.length_squared() > 1e-8 else Vector3.ZERO
		var segs: PackedInt32Array = bones[f]
		var last := segs[segs.size() - 1]
		var prev := segs[segs.size() - 2] if segs.size() > 1 else -1
		tip_len[f] = (rig.rest_gpos[last] - rig.rest_gpos[prev]).length() * 0.85 if last >= 0 and prev >= 0 else 0.03


## Applies curls (5, 0..1) and spread (0..1). `thumb_scale` < 1 keeps the thumb gentler.
func apply(curls: PackedFloat32Array, spread: float) -> void:
	for f in 5:
		var segs: PackedInt32Array = bones[f]
		var c := curls[f]
		for k in segs.size():
			var b := segs[k]
			if b < 0:
				continue
			var ang: float = (HandPoses.THUMB_CURL_ANGLES if f == 0 else HandPoses.CURL_ANGLES)[mini(k, 2)]
			var q := Quaternion(curl_axis[f], c * ang)
			if k == 0 and spread_axis[f] != Vector3.ZERO:
				q = Quaternion(spread_axis[f], spread * absf(HandPoses.SPREAD_ANGLES[f])) * q
			rig.set_rel(b, q)


## Model position of the tip of finger f (after solve()).
func tip(f: int) -> Vector3:
	var segs: PackedInt32Array = bones[f]
	var last := segs[segs.size() - 1]
	if last < 0:
		return rig.pos[hand_bone] if hand_bone >= 0 else Vector3.ZERO
	var d := _dir_seg(f, segs.size() - 1)
	return rig.pos[last] + rig.acc[last] * d * tip_len[f] * rig.acc_scale[last]


func _base(f: int) -> Vector3:
	var b: int = (bones[f] as PackedInt32Array)[0]
	if b >= 0:
		return rig.rest_gpos[b]
	return rig.rest_gpos[hand_bone] if hand_bone >= 0 else Vector3.ZERO


func _dir(f: int) -> Vector3:
	return _dir_seg(f, 0)


## Rest direction of segment k of finger f (towards the next segment; the last one continues
## the previous direction).
func _dir_seg(f: int, k: int) -> Vector3:
	var segs: PackedInt32Array = bones[f]
	if segs.size() == 0 or segs[0] < 0:
		return Vector3.ZERO
	if k + 1 < segs.size() and segs[k] >= 0 and segs[k + 1] >= 0:
		var d := rig.rest_gpos[segs[k + 1]] - rig.rest_gpos[segs[k]]
		if d.length_squared() > 1e-10:
			return d.normalized()
	if k > 0:
		return _dir_seg(f, k - 1)
	return Vector3.ZERO
