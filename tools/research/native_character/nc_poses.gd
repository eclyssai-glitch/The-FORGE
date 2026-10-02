class_name NCPoses
extends RefCounted
## SPIKE — Animation resources generated in code (key poses, no external assets).
## Keys are LOCAL pose rotations = REST * delta (an Animation rotation track stores the absolute local
## pose, not an offset; probe: Add2 adds relative to REST). Deltas are Euler (rad, YXZ) in the rig's
## own convention (real MikuRig: +X flexes — nod, elbow bend, finger curl, arm forward; +Z on .L
## abducts; .R mirrored by negating Y/Z). Works on the synthetic NCRig too (identity rests).
## Only ROTATION tracks: position/scale stay free for `appearance` (probe: a position track on a bone
## overrides the appearance offset every frame).

const SK := "Skeleton3D:"
const OTHER_FINGERS := ["middle", "ring", "little"]


## Track path + rest-multiplied key for `bone` (synthetic name) on skeleton `sk`.
static func _bone(sk: Skeleton3D, bone: String) -> String:
	if sk.find_bone(bone) >= 0:
		return bone
	# synthetic -> contract names: index.L -> index.0.L, index.L.1 -> index.1.L
	var parts := bone.split(".")
	if parts.size() == 2 and (parts[0] == "index" or parts[0] == "thumb"):
		return "%s.0.%s" % [parts[0], parts[1]]
	if parts.size() == 3:
		return "%s.%s.%s" % [parts[0], parts[2], parts[1]]
	return bone


static func _key(sk: Skeleton3D, bone: String, e: Vector3) -> Quaternion:
	var i := sk.find_bone(bone)
	var rest := Quaternion.IDENTITY if i < 0 else sk.get_bone_rest(i).basis.get_rotation_quaternion()
	return rest * Quaternion.from_euler(e)


## Body states: each is a loop a -> b -> a (cubic), so a state is never a frozen pose; the a/b
## difference is the state's own micro life (sway, settle, held tremor).
static func body_states(sk: Skeleton3D) -> Dictionary:
	var calm_a := {
		"hips": Vector3(0, 0.04, 0.035), "spine": Vector3(-0.03, 0, -0.02), "chest": Vector3(-0.05, -0.03, -0.015),
		"neck": Vector3(0.04, 0, 0.0), "head": Vector3(0.06, 0.05, 0.10),
		"clavicle.L": Vector3(0, 0, -0.03), "upper_arm.L": Vector3(0.18, 0, 0.10), "forearm.L": Vector3(0.45, 0.1, 0),
		"hand.L": Vector3(0.15, 0, 0.1), "index.L": Vector3(0.25, 0, 0), "index.L.1": Vector3(0.3, 0, 0),
		"thumb.L": Vector3(0.2, 0, 0),
		"clavicle.R": Vector3(0, 0, 0.03), "upper_arm.R": Vector3(0.12, 0, -0.08), "forearm.R": Vector3(0.35, -0.1, 0),
		"hand.R": Vector3(0.1, 0, -0.1), "index.R": Vector3(0.2, 0, 0), "index.R.1": Vector3(0.25, 0, 0),
	}
	var calm_b := calm_a.duplicate()
	calm_b["hips"] = Vector3(0, 0.0, -0.01)
	calm_b["chest"] = Vector3(-0.04, 0.02, 0.01)
	calm_b["head"] = Vector3(0.03, -0.02, 0.05)
	calm_b["index.L"] = Vector3(0.35, 0, 0)
	var focus_a := {
		"hips": Vector3(0.03, -0.05, 0), "spine": Vector3(0.07, -0.04, 0), "chest": Vector3(0.06, -0.06, 0),
		"neck": Vector3(0.12, 0, 0), "head": Vector3(0.18, 0.0, 0.03),
		"clavicle.L": Vector3(0, 0, 0.0), "upper_arm.L": Vector3(0.55, 0, 0.12), "forearm.L": Vector3(0.9, 0.2, 0),
		"hand.L": Vector3(0.2, 0, 0.2), "index.L": Vector3(0.05, 0, 0), "index.L.1": Vector3(0.05, 0, 0),
		"thumb.L": Vector3(0.0, 0, -0.2),
		"clavicle.R": Vector3(0, 0, 0.04), "upper_arm.R": Vector3(0.5, 0, -0.2), "forearm.R": Vector3(0.8, -0.2, 0),
		"hand.R": Vector3(0.0, 0, -0.15), "index.R": Vector3(0.0, 0, 0), "index.R.1": Vector3(0.0, 0, 0),
	}
	var focus_b := focus_a.duplicate()
	focus_b["head"] = Vector3(0.22, -0.05, 0.0)
	focus_b["chest"] = Vector3(0.08, -0.03, 0)
	focus_b["index.L"] = Vector3(0.15, 0, 0)
	# frustrated: composure lost — square, rigid, shoulders up, head locked forward, fingers clawed.
	var frus_a := {
		"hips": Vector3(0, 0, 0), "spine": Vector3(-0.02, 0, 0), "chest": Vector3(-0.10, 0, 0),
		"neck": Vector3(0.18, 0, 0), "head": Vector3(0.05, 0, 0),
		"clavicle.L": Vector3(0, 0, 0.14), "upper_arm.L": Vector3(0.35, 0, 0.32), "forearm.L": Vector3(1.1, 0.0, 0),
		"hand.L": Vector3(-0.1, 0, 0.0), "index.L": Vector3(0.95, 0, 0), "index.L.1": Vector3(1.0, 0, 0),
		"thumb.L": Vector3(0.6, 0, 0.3),
		"clavicle.R": Vector3(0, 0, -0.14), "upper_arm.R": Vector3(0.45, 0, -0.32), "forearm.R": Vector3(1.0, 0.0, 0),
		"hand.R": Vector3(-0.1, 0, 0.0), "index.R": Vector3(0.9, 0, 0), "index.R.1": Vector3(1.0, 0, 0),
	}
	var frus_b := frus_a.duplicate()
	frus_b["chest"] = Vector3(-0.115, 0, 0)  # held breath: almost no difference (rigidity)
	frus_b["index.L"] = Vector3(1.0, 0, 0)
	# recover: the exhale — chest drops, shoulders fall, head tilts away, hands open.
	var rec_a := {
		"hips": Vector3(-0.02, 0.03, -0.03), "spine": Vector3(0.06, 0, 0.02), "chest": Vector3(0.12, 0.02, 0.02),
		"neck": Vector3(0.10, 0, 0), "head": Vector3(0.20, -0.08, -0.14),
		"clavicle.L": Vector3(0, 0, -0.08), "upper_arm.L": Vector3(0.05, 0, 0.04), "forearm.L": Vector3(0.25, 0.0, 0),
		"hand.L": Vector3(0.1, 0, 0.0), "index.L": Vector3(0.1, 0, 0), "index.L.1": Vector3(0.1, 0, 0),
		"thumb.L": Vector3(0.1, 0, 0),
		"clavicle.R": Vector3(0, 0, 0.08), "upper_arm.R": Vector3(0.05, 0, -0.04), "forearm.R": Vector3(0.25, 0.0, 0),
		"hand.R": Vector3(0.1, 0, 0.0), "index.R": Vector3(0.1, 0, 0), "index.R.1": Vector3(0.1, 0, 0),
	}
	var rec_b := rec_a.duplicate()
	rec_b["chest"] = Vector3(0.02, 0.0, 0.0)
	rec_b["head"] = Vector3(0.10, -0.04, -0.06)
	return {
		&"calm": _loop(sk, 5.0, calm_a, calm_b),
		&"focus": _loop(sk, 3.0, focus_a, focus_b),
		&"frustrated": _loop(sk, 0.9, frus_a, frus_b),
		&"recover": _loop(sk, 4.0, rec_a, rec_b),
	}


## Breath: ADDITIVE layer (Add2) — keys are REST * inhale delta, so Add2 adds only the delta.
static func breath(sk: Skeleton3D) -> Animation:
	var inhale := {"spine": Vector3(-0.02, 0, 0), "chest": Vector3(-0.055, 0, 0), "neck": Vector3(0.02, 0, 0),
			"clavicle.L": Vector3(0, 0, 0.035), "clavicle.R": Vector3(0, 0, -0.035)}
	return _loop(sk, 1.0, {}, inhale, ["spine", "chest", "neck", "clavicle.L", "clavicle.R"])


## One-shot gesture on the LEFT arm (bone-filtered): anticipation (wind back) -> flick out ->
## overshoot -> settle. The anticipation is IN the keys; timing is the animation's.
static func flick(sk: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = 1.1
	var keys := [
		[0.0, {"upper_arm.L": Vector3(0.2, 0, 0.1), "forearm.L": Vector3(0.5, 0, 0), "hand.L": Vector3(0.1, 0, 0)}],
		[0.28, {"upper_arm.L": Vector3(0.05, 0.2, 0.02), "forearm.L": Vector3(1.4, 0.3, 0), "hand.L": Vector3(0.6, 0, 0)}],
		[0.46, {"upper_arm.L": Vector3(0.9, -0.2, 0.75), "forearm.L": Vector3(0.15, -0.2, 0), "hand.L": Vector3(-0.5, 0, 0)}],
		[0.62, {"upper_arm.L": Vector3(0.8, -0.15, 0.68), "forearm.L": Vector3(0.25, -0.1, 0), "hand.L": Vector3(-0.3, 0, 0)}],
		[1.1, {"upper_arm.L": Vector3(0.75, -0.1, 0.62), "forearm.L": Vector3(0.3, 0, 0), "hand.L": Vector3(-0.2, 0, 0)}],
	]
	for bone in ["upper_arm.L", "forearm.L", "hand.L"]:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, SK + bone)
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		for k: Array in keys:
			var pose: Dictionary = k[1]
			a.rotation_track_insert_key(t, float(k[0]), _key(sk, bone, pose[bone]))
	return a


## Puppet hand poses (single-key animations): open, relaxed, grip. +X curls every finger joint.
static func hand_poses(sk: Skeleton3D) -> Dictionary:
	var out := {}
	var curl := {&"open": [-0.12, -0.05, 0.0], &"relaxed": [0.3, 0.35, 0.25], &"grip": [1.0, 1.15, 0.85]}
	for pose: StringName in curl:
		var a := Animation.new()
		a.length = 0.1
		var c: Array = curl[pose]
		for f in ["thumb", "index", "middle", "ring", "little"]:
			for j in range(3):
				var bone := "%s.%d" % [f, j]
				if sk.find_bone(bone) < 0:
					continue
				var v := float(c[j]) * (0.6 if f == "thumb" else 1.0)
				var t := a.add_track(Animation.TYPE_ROTATION_3D)
				a.track_set_path(t, SK + bone)
				a.rotation_track_insert_key(t, 0.0, _key(sk, bone, Vector3(v, 0, 0)))
		out[pose] = a
	return out


static func _loop(sk: Skeleton3D, length: float, a: Dictionary, b: Dictionary, bones: Array = []) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	var names: Array = bones if not bones.is_empty() else a.keys()
	for bone: String in names:
		var ea: Vector3 = a.get(bone, Vector3.ZERO)
		var eb: Vector3 = b.get(bone, ea)
		var targets := [_bone(sk, bone)]
		# real rig: the other fingers follow the index curl (slightly more towards the little finger)
		if bone.begins_with("index") and sk.find_bone("middle.0.L") >= 0:
			var base := _bone(sk, bone)
			for f: String in OTHER_FINGERS:
				targets.append(base.replace("index", f))
		for k in range(targets.size()):
			var tb: String = targets[k]
			if sk.find_bone(tb) < 0:
				continue
			var gain := 1.0 + 0.12 * float(k)
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, SK + tb)
			anim.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
			anim.track_set_interpolation_loop_wrap(t, true)
			anim.rotation_track_insert_key(t, 0.0, _key(sk, tb, ea * gain))
			anim.rotation_track_insert_key(t, length * 0.5, _key(sk, tb, eb * gain))
	return anim
