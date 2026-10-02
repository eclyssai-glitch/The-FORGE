class_name MicroAgenda
extends RefCounted
## The small behaviours that keep MIKU alive between and during actions (Loop 5). Owner: animator.
## Never an idle loop: each behaviour is chosen when the previous one ends, from weights that
## depend on her mood, on the work (working or not, how many puppet hands are out, whether the
## work just failed), on her identity (curiosity, patience, pride) and on how recently each
## behaviour was done. The only noise is a seeded RandomNumberGenerator (same seed -> same life),
## used to pick among the weighted candidates and to vary durations. Pure: the caller gives dt.
##
## Sequencing rules (narrative, not chance): a hesitation is always resolved by `continue`;
## after `adjust` she looks at what she adjusted; the same behaviour never repeats back to back
## (except looking at the work while working).

const BREATHE_DEEP := &"breathe_deep"
const SHIFT_WEIGHT := &"shift_weight"
const TRACK_OBJECT := &"track_object"
const LOOK_AT_WORK := &"look_at_work"
const CORRECT_POSTURE := &"correct_posture"
const FINGERS := &"fingers"
const OBSERVE_HAND := &"observe_hand"
const CHECK_WORLD := &"check_world"
const HESITATE := &"hesitate"
const ADJUST := &"adjust"
const CONTINUE := &"continue"
## Angry stillness: the locked, not-human hold (almost no life on purpose).
const HOLD := &"hold"

const ALL: Array[StringName] = [BREATHE_DEEP, SHIFT_WEIGHT, TRACK_OBJECT, LOOK_AT_WORK, CORRECT_POSTURE,
	FINGERS, OBSERVE_HAND, CHECK_WORLD, HESITATE, ADJUST, CONTINUE, HOLD]

## Duration range (s) of each behaviour at tempo 1 (faster moods shorten them).
const DURATION := {
	BREATHE_DEEP: Vector2(3.6, 5.0), SHIFT_WEIGHT: Vector2(2.6, 4.0), TRACK_OBJECT: Vector2(2.2, 3.4),
	LOOK_AT_WORK: Vector2(2.4, 4.6), CORRECT_POSTURE: Vector2(1.6, 2.4), FINGERS: Vector2(2.2, 3.4),
	OBSERVE_HAND: Vector2(2.6, 3.8), CHECK_WORLD: Vector2(1.8, 2.8), HESITATE: Vector2(0.9, 1.5),
	ADJUST: Vector2(1.4, 2.1), CONTINUE: Vector2(0.8, 1.2), HOLD: Vector2(1.4, 2.4),
}
## Seconds after which a behaviour is fully available again (recency).
const COOLDOWN := {
	BREATHE_DEEP: 14.0, SHIFT_WEIGHT: 8.0, TRACK_OBJECT: 10.0, LOOK_AT_WORK: 0.0, CORRECT_POSTURE: 12.0,
	FINGERS: 9.0, OBSERVE_HAND: 11.0, CHECK_WORLD: 12.0, HESITATE: 10.0, ADJUST: 5.0, CONTINUE: 0.0,
	HOLD: 0.0,
}
## Base weight of each behaviour per mood (MikuMind.Mood order: CALM, FOCUSED, FRUSTRATED,
## ANGRY, RECOVERING). Calm = the curious, bodily girl; focused = the work; frustrated = tension
## and re-checking; angry = locked stillness; recovering = posture, breath, the hand.
const WEIGHTS := {
	BREATHE_DEEP: [1.0, 0.3, 0.5, 0.0, 2.2],
	SHIFT_WEIGHT: [1.4, 0.5, 0.4, 0.0, 1.0],
	TRACK_OBJECT: [1.5, 0.4, 0.2, 0.0, 0.5],
	LOOK_AT_WORK: [0.5, 2.6, 2.4, 2.0, 1.0],
	CORRECT_POSTURE: [0.8, 0.5, 1.0, 0.0, 1.8],
	FINGERS: [1.2, 0.8, 1.4, 0.0, 1.0],
	OBSERVE_HAND: [1.0, 1.0, 0.4, 0.0, 1.4],
	CHECK_WORLD: [1.3, 0.6, 0.3, 0.0, 0.6],
	HESITATE: [0.4, 0.9, 0.6, 0.0, 0.5],
	ADJUST: [0.0, 1.6, 1.6, 0.6, 0.4],
	CONTINUE: [0.0, 0.0, 0.0, 0.0, 0.0],
	HOLD: [0.0, 0.0, 0.3, 2.6, 0.0],
}

var current: StringName = &""
var elapsed := 0.0
var duration := 1.0
## Every behaviour started, in order (tests, debug, the record of a take).
var history: Array[StringName] = []

var _rng := RandomNumberGenerator.new()
var _last_at: Dictionary = {}
var _clock := 0.0


func _init(seed_value := 5051) -> void:
	reset(seed_value)


func reset(seed_value := 5051) -> void:
	_rng.seed = seed_value
	_rng.state = 0
	_rng.seed = seed_value
	current = &""
	elapsed = 0.0
	duration = 1.0
	history.clear()
	_last_at.clear()
	_clock = 0.0


## 0..1 progress of the current behaviour.
func progress() -> float:
	return clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)


## Advances the agenda. `ctx`: {"working": bool, "hands": int (puppet hands out),
## "failed": bool (the work is broken now), "busy": bool (an action owns the body: the agenda
## keeps time but only breath/fingers-level behaviours are chosen)}. Returns true when a new
## behaviour started this step.
func step(dt: float, mind: MikuMind, ctx: Dictionary) -> bool:
	_clock += dt
	elapsed += dt
	if current != &"" and elapsed < duration:
		return false
	_start(_choose(mind, ctx), mind)
	return true


## Ends the current behaviour now (an action or an event took over); the next step chooses.
func interrupt() -> void:
	elapsed = duration


## Weight of `b` now (exposed for tests).
func weight(b: StringName, mind: MikuMind, ctx: Dictionary) -> float:
	var w: float = (WEIGHTS[b] as Array)[mind.mood]
	if w <= 0.0:
		return 0.0
	var working: bool = ctx.get("working", false)
	var hands: int = ctx.get("hands", 0)
	var cur := mind.params.value(&"identity", "curiosity")
	var patience := mind.params.value(&"identity", "patience")
	var pride := mind.params.value(&"identity", "pride")
	match b:
		LOOK_AT_WORK, ADJUST, HESITATE:
			w *= 1.0 if working else 0.15
		TRACK_OBJECT, CHECK_WORLD:
			w *= lerpf(0.5, 1.5, cur) * (0.5 if working else 1.0)
		OBSERVE_HAND:
			w *= lerpf(0.6, 1.4, cur) * (1.5 if hands > 0 else 1.0)
		CORRECT_POSTURE:
			w *= lerpf(0.6, 1.5, pride)
	if b == HESITATE:
		w *= lerpf(1.4, 0.6, patience) * (1.6 if ctx.get("failed", false) else 1.0)
	if ctx.get("busy", false) and not (b in [FINGERS, BREATHE_DEEP, SHIFT_WEIGHT, HOLD, LOOK_AT_WORK]):
		w *= 0.1
	var cool: float = COOLDOWN[b]
	if cool > 0.0 and _last_at.has(b):
		w *= clampf((_clock - float(_last_at[b])) / cool, 0.08, 1.0)
	return w


func _choose(mind: MikuMind, ctx: Dictionary) -> StringName:
	# Narrative sequencing first.
	if current == HESITATE:
		return CONTINUE
	if current == ADJUST and ctx.get("working", false):
		return LOOK_AT_WORK
	var total := 0.0
	var weights: Array[float] = []
	for b in ALL:
		var w := weight(b, mind, ctx)
		if b == current and not (b == LOOK_AT_WORK and ctx.get("working", false)) and b != HOLD:
			w = 0.0
		weights.append(w)
		total += w
	if total <= 0.0:
		return BREATHE_DEEP
	var pick := _rng.randf() * total
	for i in ALL.size():
		pick -= weights[i]
		if pick <= 0.0 and weights[i] > 0.0:
			return ALL[i]
	for i in range(ALL.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return ALL[i]
	return BREATHE_DEEP


func _start(b: StringName, mind: MikuMind) -> void:
	current = b
	elapsed = 0.0
	var range_s: Vector2 = DURATION[b]
	duration = _rng.randf_range(range_s.x, range_s.y) / maxf(mind.tempo(), 0.5)
	_last_at[b] = _clock
	history.append(b)
	if history.size() > 256:
		history.remove_at(0)
