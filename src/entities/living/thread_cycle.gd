class_name ThreadCycle
extends RefCounted
## Life of one intent thread (Loop 5). Owner: animator. Pure.
## decide -> gesture -> the thread APPEARS (cast from MIKU's finger: `reach` grows 0 -> 1 towards
## the hand, slack) -> it is PULLED (tension rises towards the force of the gesture) -> the hand
## RESPONDS (responding() once the tension passes RESPOND_AT: the hand never moves before) ->
## RELAX (tension drains, the thread sags) -> it FADES (presence -> 0) -> GONE.
## Presence and tension are second-order channels; their speed scales with `tempo` (an angry
## MIKU casts and pulls faster). Tension and presence go to the material (uniforms `tension`,
## `presence`) and the tension also drives the hand (PuppetHand.pull).

enum Phase { GONE, APPEAR, PULL, RELAX, FADE }

const RESPOND_AT := 0.18
## Seconds to cast the thread across (tempo 1).
const T_CAST := 0.45
## Presence and tension springs [f, zeta].
const PRESENCE := Vector2(1.6, 1.0)
const TENSION := Vector2(1.3, 0.75)
const RELAX := Vector2(0.7, 1.0)
## A relaxed thread lingers this long (s) before it fades.
const LINGER := 0.35

var phase: Phase = Phase.GONE
var force := 0.0
var tempo := 1.0
var presence := SecondOrder.new(PRESENCE.x, PRESENCE.y, 0.0, 0.0)
var tension := SecondOrder.new(TENSION.x, TENSION.y, 0.0, 0.0)
## 0..1 how far the thread has travelled from MIKU's finger to the hand.
var reach := 0.0
var time_in_phase := 0.0
## Phases entered, in order (tests).
var log: Array[Phase] = []


func is_alive() -> bool:
	return phase != Phase.GONE


## Casts the thread (APPEAR). It pulls by itself once it has reached the hand, with `with_force`
## (0 = it waits for pull()).
func start(with_force := 0.0, speed := 1.0) -> void:
	tempo = maxf(speed, 0.1)
	force = clampf(with_force, 0.0, 1.0)
	reach = 0.0
	presence.reset(0.0)
	tension.reset(0.0)
	_enter(Phase.APPEAR)


## Pulls with `with_force` (0..1). A thread still being cast pulls when it arrives.
func pull(with_force: float) -> void:
	force = clampf(with_force, 0.0, 1.0)
	if phase == Phase.RELAX or phase == Phase.FADE:
		_enter(Phase.PULL)
	elif phase == Phase.GONE:
		start(force, tempo)


## Lets go (RELAX, then FADE, then GONE).
func relax() -> void:
	if phase == Phase.APPEAR or phase == Phase.PULL:
		_enter(Phase.RELAX)


## True when the hand follows (the thread is taut enough).
func responding() -> bool:
	return (phase == Phase.PULL or phase == Phase.RELAX) and tension.y > RESPOND_AT


func step(dt: float) -> void:
	if phase == Phase.GONE or dt <= 0.0:
		return
	time_in_phase += dt
	match phase:
		Phase.APPEAR:
			reach = minf(reach + dt * tempo / T_CAST, 1.0)
			presence.set_params(PRESENCE.x * tempo, PRESENCE.y, 0.0)
			presence.step(1.0, dt)
			tension.step(0.0, dt)
			if reach >= 1.0 and force > 0.0:
				_enter(Phase.PULL)
		Phase.PULL:
			presence.step(1.0, dt)
			tension.set_params(TENSION.x * tempo, TENSION.y, 0.0)
			tension.step(force, dt)
		Phase.RELAX:
			tension.set_params(RELAX.x * tempo, RELAX.y, 0.0)
			tension.step(0.0, dt)
			presence.step(1.0, dt)
			if tension.y < 0.05 and time_in_phase > LINGER / tempo:
				_enter(Phase.FADE)
		Phase.FADE:
			tension.step(0.0, dt)
			presence.set_params(PRESENCE.x * 0.8 * tempo, 1.0, 0.0)
			presence.step(0.0, dt)
			if presence.y < 0.01:
				presence.reset(0.0)
				_enter(Phase.GONE)


func _enter(p: Phase) -> void:
	phase = p
	time_in_phase = 0.0
	log.append(p)
	if log.size() > 32:
		log.remove_at(0)
