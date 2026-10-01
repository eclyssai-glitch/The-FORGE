class_name MikuMind
extends RefCounted
## MIKU's mind (Loop 5): mood and composure, attention, current task. Owner: animator.
## Pure (no nodes, no clock, no randomness): the runtime (Miku) feeds it events — task begun or
## ended, failures and successes of the work, the user's call — and advances it with step(dt).
## Its outputs drive the body: `composure` (1 = the elegant, human MIKU; 0 = the composure lost,
## the not-human one), `arousal` (energy), `tempo()` (speed of her actions), `rigidity()`, the
## focus of attention and the mood itself.
##
## Moods: CALM -> FOCUSED (working) -> FRUSTRATED (frustration >= frustration_threshold) ->
## ANGRY (frustration >= anger_level(): controlled rage, never a "demon mode") -> RECOVERING (a
## success after frustration; frustration drains at recovery_speed) -> CALM / FOCUSED.
## Frustration comes only from failures of her work, weighted by patience and pride; it cools
## slowly by itself (patience) except when ANGRY (she is locked on the problem until it is fixed).
## Composure falls fast and comes back slowly (recovery_speed). identity/behaviour values of
## MikuParams modulate every threshold and rate.

enum Mood { CALM, FOCUSED, FRUSTRATED, ANGRY, RECOVERING }
const MOOD_IDS: Array[StringName] = [&"calm", &"focused", &"frustrated", &"angry", &"recovering"]

## What holds her attention. The base focus comes from the task; transient overrides from
## micro-behaviours, actions and the user (attend()).
enum Focus { NONE, WORK, HAND, WORLD, USER, SELF, FILE }
const FOCUS_IDS: Array[StringName] = [&"none", &"work", &"hand", &"world", &"user", &"self", &"file"]

## Reaction to the user's call, by mood (user_call()).
const REACT_CURIOUS := &"curious"
const REACT_BRIEF := &"brief"
const REACT_CURT := &"curt"
const REACT_COLD := &"cold"

## Minimum seconds in RECOVERING before she is calm again (the recovery is seen, not skipped).
const RECOVER_MIN := 3.5
## Frustration below which the recovery ends.
const RECOVERED_LEVEL := 0.08
## Composure easing (s): losing it is quick, regaining it slow (scaled by recovery_speed).
const COMPOSURE_FALL_TAU := 0.45
const COMPOSURE_RISE_TAU := Vector2(6.0, 2.0)
const AROUSAL_TAU := 1.2

var params: MikuParams
var mood: Mood = Mood.CALM
var frustration := 0.0
var composure := 1.0
var arousal := 0.2
var time_in_mood := 0.0
## Seconds of mind time (sum of the dt given to step).
var clock := 0.0

var task: StringName = &""
var task_world: StringName = &""
var failures_in_task := 0
## Last world the user pointed at (&"" = none).
var user_target: StringName = &""
## Mind time of the last call of the user (-1e9 = never).
var last_user_call := -1.0e9

var _base_kind: Focus = Focus.NONE
var _base_id: StringName = &""
var _over_kind: Focus = Focus.NONE
var _over_id: StringName = &""
var _over_until := -1.0


func _init(p: MikuParams = null) -> void:
	params = p if p != null else MikuParams.new()


## Mood id (&"calm", &"focused", ...).
func mood_id() -> StringName:
	return MOOD_IDS[mood]


## Frustration at which she becomes ANGRY (above frustration_threshold; a fiery temperament
## gets there sooner).
func anger_level() -> float:
	var th := params.value(&"behaviour", "frustration_threshold")
	return th + lerpf(0.5, 0.25, params.value(&"identity", "temperament"))


## 0 = fluid and human (composed), 1 = rigid, mechanical, not human.
func rigidity() -> float:
	return clampf(1.0 - composure, 0.0, 1.0)


## Speed of her actions: graceful and unhurried when calm, extremely efficient when angry.
func tempo() -> float:
	return lerpf(0.9, 1.85, pow(clampf(arousal, 0.0, 1.0), 1.4))


# ---------------------------------------------------------------- events


func begin_task(task_id: StringName, world: StringName) -> void:
	task = task_id
	task_world = world
	failures_in_task = 0
	_base_kind = Focus.WORK if world != &"" else Focus.NONE
	_base_id = world
	if mood == Mood.CALM:
		_set_mood(Mood.FOCUSED)


## The task is over. A success also counts as one (on_success).
func end_task(success: bool) -> void:
	if success:
		on_success(1.0)
	task = &""
	_base_kind = Focus.NONE
	_base_id = &""
	if mood == Mood.FOCUSED:
		_set_mood(Mood.CALM)


## Something in her work went wrong (severity 0..1: a crack ~0.35, a collapse ~0.6).
## Returns the frustration it added.
func on_failure(severity: float) -> float:
	failures_in_task += 1
	var patience := params.value(&"identity", "patience")
	var pride := params.value(&"identity", "pride")
	var add := maxf(severity, 0.0) * lerpf(1.3, 0.7, patience) * lerpf(0.8, 1.2, pride)
	frustration = clampf(frustration + add, 0.0, 1.5)
	_evaluate()
	return add


## A step of the work held (magnitude 0..1). After frustration it starts the recovery.
func on_success(magnitude: float) -> void:
	frustration = maxf(frustration - 0.25 * clampf(magnitude, 0.0, 1.0), 0.0)
	if mood == Mood.FRUSTRATED or mood == Mood.ANGRY:
		_set_mood(Mood.RECOVERING)
	else:
		_evaluate()


## The user called her. Returns {reaction, hold (s she looks at the user), turn (0..1 of the
## body that turns to the user), leave_work (she pauses the work)} — all by mood and
## interruption_tolerance. Calm: curious, turns, lingers. Focused: a brief look and back.
## Frustrated: curt. Angry: cold — the eyes only, the work does not stop.
func user_call() -> Dictionary:
	last_user_call = clock
	var tol := params.value(&"behaviour", "interruption_tolerance")
	var cur := params.value(&"identity", "curiosity")
	var out := {}
	match mood:
		Mood.CALM:
			out = {"reaction": REACT_CURIOUS, "hold": lerpf(2.6, 4.2, cur), "turn": lerpf(0.55, 0.85, cur),
				"leave_work": true}
		Mood.RECOVERING:
			out = {"reaction": REACT_CURIOUS, "hold": 2.2, "turn": 0.45, "leave_work": true}
		Mood.FOCUSED:
			out = {"reaction": REACT_BRIEF, "hold": lerpf(0.9, 2.0, tol), "turn": lerpf(0.15, 0.4, tol),
				"leave_work": tol > 0.75}
		Mood.FRUSTRATED:
			out = {"reaction": REACT_CURT, "hold": lerpf(0.6, 1.1, tol), "turn": 0.1, "leave_work": false}
		_:
			out = {"reaction": REACT_COLD, "hold": lerpf(0.45, 0.8, tol), "turn": 0.0, "leave_work": false}
	attend(Focus.USER, &"user", float(out["hold"]))
	return out


## The user pointed at a world: it becomes her next work target.
func user_points(world: StringName) -> void:
	user_target = world
	last_user_call = clock


## Transient attention for `seconds` (micro-behaviours, actions, the user).
func attend(kind: Focus, id: StringName, seconds: float) -> void:
	_over_kind = kind
	_over_id = id
	_over_until = clock + maxf(seconds, 0.0)


func release_attention() -> void:
	_over_until = -1.0


## Current focus of attention (override while it lasts, else the task's).
func focus_kind() -> Focus:
	return _over_kind if clock < _over_until else _base_kind


func focus_id() -> StringName:
	return _over_id if clock < _over_until else _base_id


## Advances the mind. Returns true when the mood changed.
func step(dt: float) -> bool:
	if dt <= 0.0:
		return false
	clock += dt
	time_in_mood += dt
	var before := mood
	var patience := params.value(&"identity", "patience")
	var recovery := params.value(&"behaviour", "recovery_speed")
	match mood:
		Mood.RECOVERING:
			frustration = maxf(frustration - lerpf(0.06, 0.24, recovery) * dt, 0.0)
		Mood.ANGRY:
			frustration = maxf(frustration - 0.004 * dt, 0.0)
		_:
			frustration = maxf(frustration - lerpf(0.006, 0.03, patience) * dt, 0.0)
	_evaluate()
	var target := _composure_target()
	var tau := COMPOSURE_FALL_TAU if target < composure else lerpf(COMPOSURE_RISE_TAU.x, COMPOSURE_RISE_TAU.y, recovery)
	composure = lerpf(composure, target, 1.0 - exp(-dt / tau))
	arousal = lerpf(arousal, _arousal_target(), 1.0 - exp(-dt / AROUSAL_TAU))
	return mood != before


func _composure_target() -> float:
	var temper := params.value(&"identity", "temperament")
	match mood:
		Mood.CALM:
			return 1.0
		Mood.FOCUSED:
			return 0.9
		Mood.FRUSTRATED:
			return lerpf(0.72, 0.55, temper)
		Mood.ANGRY:
			return 1.0 - 0.92 * params.value(&"behaviour", "aggression_peak")
	# RECOVERING: comes back as the frustration drains.
	return clampf(1.0 - frustration / maxf(anger_level(), 0.01), 0.35, 1.0)


func _arousal_target() -> float:
	var cur := params.value(&"identity", "curiosity")
	match mood:
		Mood.CALM:
			return 0.15 + 0.1 * cur
		Mood.FOCUSED:
			return 0.42
		Mood.FRUSTRATED:
			return 0.7
		Mood.ANGRY:
			return 0.97
	return 0.3


func _evaluate() -> void:
	var th := params.value(&"behaviour", "frustration_threshold")
	var anger := anger_level()
	match mood:
		Mood.CALM, Mood.FOCUSED:
			if frustration >= anger:
				_set_mood(Mood.ANGRY)
			elif frustration >= th:
				_set_mood(Mood.FRUSTRATED)
			elif mood == Mood.CALM and task != &"":
				_set_mood(Mood.FOCUSED)
			elif mood == Mood.FOCUSED and task == &"":
				_set_mood(Mood.CALM)
		Mood.FRUSTRATED:
			if frustration >= anger:
				_set_mood(Mood.ANGRY)
			elif frustration < th * 0.6:
				_set_mood(Mood.FOCUSED if task != &"" else Mood.CALM)
		Mood.ANGRY:
			if frustration < th * 0.5:
				_set_mood(Mood.RECOVERING)
		Mood.RECOVERING:
			if frustration >= anger:
				_set_mood(Mood.ANGRY)
			elif frustration < RECOVERED_LEVEL and time_in_mood >= RECOVER_MIN:
				_set_mood(Mood.FOCUSED if task != &"" else Mood.CALM)


func _set_mood(m: Mood) -> void:
	if m == mood:
		return
	mood = m
	time_in_mood = 0.0
