class_name MikuDirector
extends RefCounted
## MIKU's ANIMATION DIRECTOR on the native stack (Loop 5 r2, migration STEP 1). Owner: animator.
## It owns an AnimationTree (MANUAL process: advanced with the MotionClock dt by MikuBody.step) and
## writes ONLY tree parameters — never a bone. The mind's outputs arrive as body goals (mood,
## rigidity, tempo, posture offsets, weight, breath) and become:
##
##   mood        AnimationNodeStateMachine: calm / focused / frustrated / angry / recovering.
##               Start -> calm is AUTO (research P-05). Every edge cross-fades with an eased
##               curve: composure is lost fast (XFADE_LOSS), regained slowly (XFADE_RECOVER...).
##               Each state is a BlendTree: its loop -> TimeScale `tempo` (the mind's rhythm:
##               her life inside the mood speeds up with her tempo; the cross-fades stay in real
##               seconds).
##   tension     BlendSpace1D on rigidity (0 poise .. 1 composure lost), ADDED (Add2) on top of
##               the mood: the continuous grade inside a discrete mode. It answers at once, also
##               while the state machine is still finishing a cross-fade (4.7.2: a travel asked
##               during a fade waits for its end — measured, see docs/ANIMATION.md).
##   ax_<axis>   7 Add2 layers: the posture the actions and micro-behaviours ask on top of the
##               mood (lean, side, lift, raise, fwd, tilt, nod), each through the round-1 posture
##               spring (POSTURE_CALM .. POSTURE_STIFF, × tempo).
##   weight      BlendSpace1D (-1 right .. 1 left) of the hip roll, added (Add2).
##   breath      the breath loop -> TimeScale (rate, Hz) -> Add2 (depth × lerp(1, 0.35, rigidity)).
##   flinch / exhale   OneShot gestures in additive branches (filtered to the torso): the flinch
##               when composure is lost, the exhale when it comes back. Anticipation is in keys.
## Every Add2 has sync = true (P-07: a zero-weight layer must keep its clock).

const STATES: Array[StringName] = MikuPoses.MOODS
## Cross-fade (s) from -> to (MikuMind.Mood order). Losing composure: 0.25 s; regaining it:
## 1.2–1.6 s; calm <-> focus between them.
const XFADE_LOSS := 0.25
const XFADE_RECOVER := 1.4
const XFADE_SETTLE := 1.6
const XFADE: Array = [
	# to:  calm  focused frustr. angry  recovering
	[0.0, 0.9, XFADE_LOSS, XFADE_LOSS, 1.2],  # from calm
	[1.2, 0.0, XFADE_LOSS, XFADE_LOSS, 1.2],  # from focused
	[XFADE_RECOVER, 1.2, 0.0, XFADE_LOSS, XFADE_RECOVER],  # from frustrated
	[XFADE_SETTLE, XFADE_RECOVER, 0.8, 0.0, XFADE_SETTLE],  # from angry
	[XFADE_SETTLE, 1.2, XFADE_LOSS, XFADE_LOSS, 0.0],  # from recovering
]
## Posture springs [f, zeta, r] at rigidity 0 / 1 (MikuMotor.POSTURE_CALM / _STIFF).
const POSTURE_CALM := MikuMotor.POSTURE_CALM
const POSTURE_STIFF := MikuMotor.POSTURE_STIFF
const WEIGHT := MikuMotor.WEIGHT
const DEPTH := Vector2(0.4, 1.0)
const ONESHOT_FADE_IN := 0.05
const ONESHOT_FADE_OUT := 0.2

var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var poses: MikuPoses

## Goals (MikuBody's body goals).
var mood := 0
var stiff := 0.0
var tempo := 1.0
var posture := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var weight_side := 0.0
var breath_rate := 1.0 / Palette.T_BREATH
var breath_depth := 1.0

## Outputs / inspection.
var travels := 0
var gestures := {&"flinch": 0, &"exhale": 0}
var last_us := 0

var _axes: Array[SecondOrder] = []
var _weight := SecondOrder.new(WEIGHT.x, WEIGHT.y, WEIGHT.z)
var _depth := SecondOrder.new(DEPTH.x, DEPTH.y, 0.0, 1.0)
var _cur_mood := 0
var _snap := true
var _p_tempo: Array[StringName] = []
var _p_axis: Array[StringName] = []
var _cache: Dictionary = {}

const P_TENSION := &"parameters/tension/blend_position"
const P_WEIGHT := &"parameters/weight/blend_position"
const P_BREATH_RATE := &"parameters/breath_rate/scale"
const P_BREATH_ADD := &"parameters/breath_add/add_amount"
const P_FLINCH := &"parameters/flinch/request"
const P_EXHALE := &"parameters/exhale/request"


## Builds the tree for `skeleton` (bones resolved by `map`) as a sibling of the skeleton.
func _init(skeleton: Skeleton3D, map: RigBones) -> void:
	poses = MikuPoses.new(skeleton, map)
	for i in MikuPoses.AXES.size():
		_axes.append(SecondOrder.new(POSTURE_CALM.x, POSTURE_CALM.y, POSTURE_CALM.z))
		_p_axis.append(StringName("parameters/ax_%s/add_amount" % MikuPoses.AXES[i]))
	for s in STATES:
		_p_tempo.append(StringName("parameters/mood/%s/tempo/scale" % s))
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.add_animation_library(&"", poses.library())
	tree.tree_root = build_graph(poses.bones.size() > 0, _filter_paths())
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.get_parent().add_child(tree)
	tree.root_node = NodePath("..")
	tree.active = true
	tree.advance(0.0)
	playback = tree.get(&"parameters/mood/playback")


func _filter_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for key in poses.bones:
		out.append(poses.prefix + poses.bone_name(key))
	return out


static func _anim(name: StringName) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


static func _add2() -> AnimationNodeAdd2:
	var a := AnimationNodeAdd2.new()
	a.sync = true
	return a


static func ease_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0), 0.0, 0.0)
	c.add_point(Vector2(1.0, 1.0), 0.0, 0.0)
	return c


## The node graph (a resource; pure). `filters`: track paths the one-shots may touch.
static func build_graph(_has_bones: bool, filters: PackedStringArray) -> AnimationNodeBlendTree:
	var sm := AnimationNodeStateMachine.new()
	for i in STATES.size():
		var st := AnimationNodeBlendTree.new()
		st.add_node(&"pose", _anim(STATES[i]))
		st.add_node(&"tempo", AnimationNodeTimeScale.new())
		st.connect_node(&"tempo", 0, &"pose")
		st.connect_node(&"output", 0, &"tempo")
		sm.add_node(STATES[i], st, Vector2(200.0 * i, 0.0))
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", STATES[0], start)
	var curve := ease_curve()
	for a in STATES.size():
		for b in STATES.size():
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = float(XFADE[a][b])
			t.xfade_curve = curve
			sm.add_transition(STATES[a], STATES[b], t)
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"mood", sm)
	# Composure grade.
	var tension := AnimationNodeBlendSpace1D.new()
	tension.min_space = 0.0
	tension.max_space = 1.0
	tension.add_blend_point(_anim(&"neutral"), 0.0, -1, &"poise")
	tension.add_blend_point(_anim(&"tension"), 1.0, -1, &"locked")
	bt.add_node(&"tension", tension)
	bt.add_node(&"composure", _add2())
	bt.connect_node(&"composure", 0, &"mood")
	bt.connect_node(&"composure", 1, &"tension")
	var last := &"composure"
	# Posture axes.
	for ax in MikuPoses.AXES:
		var n := StringName("ax_" + String(ax))
		var src := StringName("axis_" + String(ax))
		bt.add_node(src, _anim(src))
		bt.add_node(n, _add2())
		bt.connect_node(n, 0, last)
		bt.connect_node(n, 1, src)
		last = n
	# Weight.
	var weight := AnimationNodeBlendSpace1D.new()
	weight.min_space = -1.0
	weight.max_space = 1.0
	weight.add_blend_point(_anim(&"weight_r"), -1.0, -1, &"right")
	weight.add_blend_point(_anim(&"neutral"), 0.0, -1, &"centre")
	weight.add_blend_point(_anim(&"weight_l"), 1.0, -1, &"left")
	bt.add_node(&"weight", weight)
	bt.add_node(&"weight_add", _add2())
	bt.connect_node(&"weight_add", 0, last)
	bt.connect_node(&"weight_add", 1, &"weight")
	last = &"weight_add"
	# Breath.
	bt.add_node(&"breath", _anim(&"breath"))
	bt.add_node(&"breath_rate", AnimationNodeTimeScale.new())
	bt.connect_node(&"breath_rate", 0, &"breath")
	bt.add_node(&"breath_add", _add2())
	bt.connect_node(&"breath_add", 0, last)
	bt.connect_node(&"breath_add", 1, &"breath_rate")
	last = &"breath_add"
	# Gestures (additive one-shots, torso filter).
	for g: StringName in [&"flinch", &"exhale"]:
		var os := AnimationNodeOneShot.new()
		os.fadein_time = ONESHOT_FADE_IN
		os.fadeout_time = ONESHOT_FADE_OUT
		os.filter_enabled = true
		for p in filters:
			os.set_filter_path(NodePath(p), true)
		var gn := StringName(String(g) + "_rest")
		bt.add_node(gn, _anim(&"neutral"))
		bt.add_node(StringName(String(g) + "_shot"), _anim(g))
		bt.add_node(g, os)
		bt.connect_node(g, 0, gn)
		bt.connect_node(g, 1, StringName(String(g) + "_shot"))
		var add := StringName(String(g) + "_add")
		bt.add_node(add, _add2())
		bt.connect_node(add, 0, last)
		bt.connect_node(add, 1, g)
		last = add
	bt.connect_node(&"output", 0, last)
	return bt


## Next step places every layer on its goal (composition / reset).
func snap() -> void:
	_snap = true


## One motion step: springs -> parameters -> AnimationTree.advance(dt) (synchronous: the torso
## pose is in the skeleton when this returns).
func step(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var k := clampf(stiff, 0.0, 1.0)
	if _snap:
		_snap_all()
	if mood != _cur_mood:
		_change_mood(_cur_mood, mood)
		_cur_mood = mood
	var pc := POSTURE_CALM.lerp(POSTURE_STIFF, k)
	for i in _axes.size():
		_axes[i].set_params(pc.x * tempo, pc.y, pc.z)
		var off := posture[i] - float(MikuPoses.MOOD_POSTURE[mood][i])
		_param(_p_axis[i], _axes[i].step(off, dt))
	_param(P_WEIGHT, clampf(_weight.step(weight_side, dt), -1.0, 1.0))
	_param(P_TENSION, k)
	_depth.step(breath_depth, dt)
	_param(P_BREATH_ADD, _depth.y * lerpf(1.0, 0.35, k))
	_param(P_BREATH_RATE, maxf(breath_rate, 0.01))
	for p in _p_tempo:
		_param(p, tempo)
	tree.advance(dt)
	_snap = false
	last_us = Time.get_ticks_usec() - t0


func _param(path: StringName, v: float) -> void:
	if absf(float(_cache.get(path, INF)) - v) < 1e-5:
		return
	_cache[path] = v
	tree.set(path, v)


func _snap_all() -> void:
	for i in _axes.size():
		_axes[i].reset(posture[i] - float(MikuPoses.MOOD_POSTURE[mood][i]))
	_weight.reset(weight_side)
	_depth.reset(breath_depth)
	if _cur_mood != mood:
		# Composition only (nothing is on screen yet): placed, not cross-faded.
		playback.start(STATES[mood])
		_cur_mood = mood


## A mood change: the state machine cross-fades; losing composure fires the flinch, regaining it
## the exhale.
func _change_mood(from: int, to: int) -> void:
	playback.travel(STATES[to])
	travels += 1
	var tense := func(m: int) -> bool: return m == MikuMind.Mood.FRUSTRATED or m == MikuMind.Mood.ANGRY
	if tense.call(to) and not (from == MikuMind.Mood.ANGRY and to == MikuMind.Mood.FRUSTRATED):
		fire(&"flinch")
	elif to == MikuMind.Mood.RECOVERING:
		fire(&"exhale")


## Fires a one-shot gesture (&"flinch" | &"exhale").
func fire(g: StringName) -> void:
	tree.set(StringName("parameters/%s/request" % g), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	gestures[g] = int(gestures.get(g, 0)) + 1


func current_state() -> StringName:
	return playback.get_current_node()


func inspect_state() -> Dictionary:
	return {"state": String(playback.get_current_node()), "fading_from": String(playback.get_fading_from_node()),
		"fade": snappedf(playback.get_fading_position() / maxf(playback.get_fading_length(), 0.001), 0.01)
			if playback.get_fading_from_node() != &"" else 1.0,
		"tension": snappedf(float(_cache.get(P_TENSION, 0.0)), 0.01),
		"weight": snappedf(float(_cache.get(P_WEIGHT, 0.0)), 0.01),
		"breath_amount": snappedf(float(_cache.get(P_BREATH_ADD, 0.0)), 0.01),
		"axes": _axes.map(func(s: SecondOrder) -> float: return snappedf(s.y, 0.001)),
		"travels": travels, "gestures": gestures.duplicate(), "tree_us": last_us}
