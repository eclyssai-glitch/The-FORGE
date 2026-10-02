class_name MikuPoses
extends RefCounted
## MIKU's torso key poses as Animation resources generated in code (Loop 5 r2, native migration
## STEP 1). Owner: animator. No external asset: every key is the bone's local REST rotation times a
## delta (`rest * delta`) and every track is a ROTATION track — never position/scale, so the
## appearance the procedural-modeler writes into the rests (height, shoulders, neck, chest) is never
## overwritten (research P-17).
##
## The deltas are the round-1 body's own numbers (MikuMotor._compose: how lean, lift, raise... move
## spine, chest, neck, head, clavicles, hips) expressed in the rig's MODEL axes at rest (+X her left,
## +Y up, +Z forward; LimbIK.euler) and converted to each bone's local axes exactly as PoseRig.write
## does:  local = rest_local · (rest_global⁻¹ · q_model · rest_global). The same library works on the
## real MikuRig and on the development mannequin, whatever their bone axes.
##
## Library (AnimationLibrary, names below):
##   <mood>          loop a -> b -> a per mood (CALM, FOCUSED, FRUSTRATED, ANGRY, RECOVERING): the
##                   mood's carriage (MOOD_POSTURE) and a small life of its own (MOOD_LIFE), so a
##                   state is never a frozen pose. Absolute poses (the state machine blends them).
##   axis_<axis>     one key: 1 unit of a posture axis (lean, side, lift, raise, fwd, tilt, nod).
##                   ADDITIVE (Add2: the delta relative to rest is added × add_amount).
##   neutral         one key: the rest (zero delta) — the neutral input of additive branches.
##   weight_l/_r     one key: the weight on her left / right hip (hips roll, spine counters).
##   tension         one key: composure lost (shoulders up and in, chin down, chest held).
##   breath          loop of 1 s: the round-1 breath curve (inhale 40 %, long eased exhale).
##   flinch          one-shot: composure lost — a sharp intake (anticipation), the recoil, settle.
##   exhale          one-shot: composure regained — a breath in, the long release, settle.

const SK_TORSO: Array[String] = ["hips", "spine", "chest", "neck", "head", "clavicle.L", "clavicle.R"]
## Posture axes, in MikuBody.set_posture order.
const AXES: Array[StringName] = [&"lean", &"side", &"lift", &"raise", &"fwd", &"tilt", &"nod"]
const MOODS: Array[StringName] = [&"calm", &"focused", &"frustrated", &"angry", &"recovering"]

## Posture of each mood (MikuMind.Mood order; the AXES above). Calm = the dancer's carriage;
## angry = vertical, square, chin down, no tilt. (Moved here from Miku: both bodies use it.)
const MOOD_POSTURE: Array = [
	[0.0, 0.015, 0.2, -0.12, -0.18, 0.065, 0.0],
	[0.08, 0.0, 0.1, 0.0, 0.08, 0.03, 0.07],
	[0.06, 0.0, -0.05, 0.5, 0.25, 0.0, 0.05],
	[0.0, 0.0, 0.06, 0.3, 0.0, 0.0, 0.08],
	[0.02, 0.0, 0.12, -0.2, -0.1, 0.05, 0.08],
]
## The life inside each mood: offset of key b from key a (AXES) and the loop's period (s at
## tempo 1). Calm sways and settles slowly; focus breathes into the work; frustration is a held,
## barely moving tension; anger does not move; recovery keeps settling.
const MOOD_LIFE: Array = [
	[[0.0, -0.012, 0.035, -0.03, -0.02, 0.02, -0.012], 6.5],
	[[0.025, 0.0, 0.0, 0.0, 0.02, 0.0, 0.025], 4.2],
	[[0.0, 0.0, -0.01, 0.035, 0.0, 0.0, 0.0], 1.6],
	[[0.0, 0.0, 0.0, 0.008, 0.0, 0.0, 0.0], 2.4],
	[[-0.01, 0.0, 0.05, -0.05, -0.02, 0.025, -0.02], 5.2],
]
## Composure lost, on top of any mood, at rigidity 1 (AXES).
const TENSION: Array = [0.0, 0.0, -0.04, 0.14, 0.06, 0.0, 0.035]
## Breath at depth 1 (peak of the inhale, model axes): chest opens back, spine follows, clavicles
## lift. (MikuMotor.BREATH_CHEST / BREATH_SHOULDER.)
const BREATH_CHEST := 0.035
const BREATH_SHOULDER := 0.035
## Weight on one hip: hips roll (rad) at weight 1 (MikuMotor.HIP_ROLL).
const HIP_ROLL := 0.07
## One-shots: [t, AXES] keys. Anticipation is in the keys (the intake before the recoil; the
## breath in before the release).
const FLINCH: Array = [
	[0.0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]],
	[0.07, [0.0, 0.0, 0.07, 0.05, 0.0, 0.0, -0.02]],
	[0.2, [-0.07, 0.0, -0.02, 0.24, 0.12, 0.0, -0.06]],
	[0.42, [-0.03, 0.0, -0.03, 0.18, 0.08, 0.0, 0.0]],
	[0.85, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]],
]
const EXHALE: Array = [
	[0.0, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]],
	[0.55, [-0.02, 0.0, 0.1, 0.08, -0.03, 0.0, -0.03]],
	[1.5, [0.04, 0.0, -0.08, -0.16, 0.0, 0.03, 0.09]],
	[2.6, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]],
]
const FLINCH_LENGTH := 0.85
const EXHALE_LENGTH := 2.6

var skeleton: Skeleton3D
var map: RigBones
## Track path prefix ("<skeleton node name>:") relative to the AnimationTree's root node.
var prefix := "Skeleton3D:"
## Torso bones present in the rig (keys), resolved.
var bones: PackedStringArray = []

var _rest_l: Dictionary = {}
var _rest_g: Dictionary = {}


func _init(skel: Skeleton3D, bone_map: RigBones) -> void:
	skeleton = skel
	map = bone_map
	prefix = String(skel.name) + ":"
	for key in SK_TORSO:
		var b := map.bone(key)
		if b < 0:
			continue
		bones.append(key)
		_rest_l[key] = skel.get_bone_rest(b).basis.get_rotation_quaternion()
		_rest_g[key] = skel.get_bone_global_rest(b).basis.get_rotation_quaternion()


## Skeleton bone name of a semantic key.
func bone_name(key: String) -> String:
	return skeleton.get_bone_name(map.bone(key))


## Model-axis rotation per torso bone for posture values `v` (AXES order), breath `breath` (0..1, the curve
## at depth 1) and hip roll `roll` (rad) — MikuMotor._compose without gaze, turn and arms.
static func model_rotations(v: Array, breath := 0.0, roll := 0.0) -> Dictionary:
	var lean := float(v[0])
	var side := float(v[1])
	var lift := float(v[2])
	var raise := float(v[3])
	var fwd := float(v[4])
	var tilt := float(v[5])
	var nod := float(v[6])
	var out := {}
	out["hips"] = LimbIK.euler(0.0, 0.0, roll)
	out["spine"] = LimbIK.euler(lean * 0.45 - lift * 0.25 - breath * BREATH_CHEST * 0.3, 0.0, -roll * 0.7 + side * 0.5)
	out["chest"] = LimbIK.euler(lean * 0.4 - lift * 0.45 - breath * BREATH_CHEST, 0.0, -roll * 0.45 + side * 0.5)
	out["neck"] = LimbIK.euler(-lean * 0.35 + lift * 0.3, 0.0, roll * 0.3)
	out["head"] = LimbIK.euler(nod, 0.0, tilt)
	for s in 2:
		var sx := 1.0 if s == 0 else -1.0
		out["clavicle." + RigBones.SIDES[s]] = LimbIK.euler(0.0, -sx * fwd * 0.25, sx * (raise * 0.2 + breath * BREATH_SHOULDER))
	return out


## Local pose rotation of torso bone `key` for a model-axis rotation (PoseRig.write's formula).
func local_key(key: String, q_model: Quaternion) -> Quaternion:
	var g: Quaternion = _rest_g[key]
	return ((_rest_l[key] as Quaternion) * (g.inverse() * q_model * g)).normalized()


## The whole library.
func library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for m in MOODS.size():
		var a: Array = MOOD_POSTURE[m]
		var life: Array = MOOD_LIFE[m]
		var b := []
		for i in 7:
			b.append(float(a[i]) + float((life[0] as Array)[i]))
		lib.add_animation(MOODS[m], _loop([[0.0, a], [0.5, b], [1.0, a]], float(life[1])))
	var zero := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	lib.add_animation(&"neutral", _pose(model_rotations(zero)))
	for i in AXES.size():
		var unit := zero.duplicate()
		unit[i] = 1.0
		lib.add_animation(StringName("axis_" + String(AXES[i])), _pose(model_rotations(unit)))
	lib.add_animation(&"weight_l", _pose(model_rotations(zero, 0.0, HIP_ROLL)))
	lib.add_animation(&"weight_r", _pose(model_rotations(zero, 0.0, -HIP_ROLL)))
	lib.add_animation(&"tension", _pose(model_rotations(TENSION)))
	lib.add_animation(&"breath", _breath())
	lib.add_animation(&"flinch", _shot(FLINCH, FLINCH_LENGTH))
	lib.add_animation(&"exhale", _shot(EXHALE, EXHALE_LENGTH))
	return lib


## The round-1 breath curve b(phase) (0..1; MikuMotor._step_breath): eased inhale over 40 % of
## the cycle, a longer eased exhale.
static func breath_curve(phase: float) -> float:
	var ph := fposmod(phase, 1.0)
	if ph < 0.4:
		return Tween.interpolate_value(0.0, 1.0, ph / 0.4, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	return Tween.interpolate_value(1.0, -1.0, (ph - 0.4) / 0.6, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)


func _track(anim: Animation, key: String) -> int:
	var t := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t, NodePath(prefix + bone_name(key)))
	return t


## One-key pose (all torso bones).
func _pose(rots: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = 0.1
	for key in bones:
		var t := _track(anim, key)
		anim.rotation_track_insert_key(t, 0.0, local_key(key, rots[key]))
	return anim


## Looping animation through posture keys [[u (0..1 of length), AXES values]] (cubic).
func _loop(keys: Array, length: float) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	for key in bones:
		var t := _track(anim, key)
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		anim.track_set_interpolation_loop_wrap(t, true)
		for k: Array in keys:
			if float(k[0]) >= 1.0:
				continue
			anim.rotation_track_insert_key(t, float(k[0]) * length, local_key(key, model_rotations(k[1])[key]))
	return anim


func _shot(keys: Array, length: float) -> Animation:
	var anim := Animation.new()
	anim.length = length
	for key in bones:
		var t := _track(anim, key)
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		for k: Array in keys:
			anim.rotation_track_insert_key(t, float(k[0]), local_key(key, model_rotations(k[1])[key]))
	return anim


## Breath loop, 1 s long (TimeScale = rate in Hz): the curve sampled densely (linear between
## samples, so the round-1 easing is kept exactly enough).
func _breath() -> Animation:
	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR
	var zero := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	const N := 20
	for key in ["spine", "chest", "clavicle.L", "clavicle.R"]:
		if not bones.has(key):
			continue
		var t := _track(anim, key)
		anim.track_set_interpolation_loop_wrap(t, true)
		for i in N:
			var u := float(i) / float(N)
			anim.rotation_track_insert_key(t, u, local_key(key, model_rotations(zero, breath_curve(u))[key]))
	return anim
