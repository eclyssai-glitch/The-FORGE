class_name Motion
extends RefCounted
## Pure progress and easing helpers for event-driven animation. Owner: animator.
## Every visual state is a function of an event timestamp (`*_at`, -1 when the event has not
## happened) and the simulation time, so pause, seek and reset never leave residual state:
##     p = Motion.progress(world.some_at, Simulation.time, duration)
## Easing goes through Tween.interpolate_value (no hand-rolled curves).


## Linear progress 0..1 of an animation that starts at `at` and lasts `duration` seconds.
## 0 when the event has not happened (`at` < 0) or `now` is before it.
static func progress(at: float, now: float, duration: float) -> float:
	if at < 0.0 or now < at:
		return 0.0
	if duration <= 0.0:
		return 1.0
	return clampf((now - at) / duration, 0.0, 1.0)


## Eased value of p (clamped to 0..1) with a Tween transition/ease pair.
static func eased(p: float, trans: Tween.TransitionType = Tween.TRANS_SINE,
		ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> float:
	return float(Tween.interpolate_value(0.0, 1.0, clampf(p, 0.0, 1.0), 1.0, trans, ease_type))


## Sine in-out progress of an event animation (the default "settle" curve).
static func smooth(at: float, now: float, duration: float) -> float:
	return eased(progress(at, now, duration))


## Cubic ease-out progress (fast start, gentle arrival: bursts, waves, growth).
static func out(at: float, now: float, duration: float) -> float:
	return eased(progress(at, now, duration), Tween.TRANS_CUBIC, Tween.EASE_OUT)


## 1 at `at`, falling to 0 after `duration` (quadratic). 0 before the event or when it never
## happened. Used for flashes, surges and fading waves.
static func decay(at: float, now: float, duration: float) -> float:
	if at < 0.0 or now < at:
		return 0.0
	var k := 1.0 - progress(at, now, duration)
	return k * k


## Envelope that rises over `rise` seconds from `at`, holds until `hold_until`, then falls over
## `fall` seconds. 0 before `at` (or when at < 0).
static func window(at: float, now: float, rise: float, hold_until: float, fall: float) -> float:
	if at < 0.0 or now < at:
		return 0.0
	if now <= hold_until:
		return eased(progress(at, now, rise))
	return eased(progress(at, hold_until, rise)) * (1.0 - eased(progress(hold_until, now, fall)))


## Deterministic pseudo-random 0..1 for an integer key (stable stagger offsets, no RNG state).
static func hash01(key: int) -> float:
	return fposmod(sin(float(key) * 12.9898 + 78.233) * 43758.5453, 1.0)
