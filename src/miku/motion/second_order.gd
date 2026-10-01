class_name SecondOrder
extends RefCounted
## Second-order dynamics on a float (Owner: animator; Loop 5, ADR-015). The response of a damped
## spring to a moving target, parametrised the way an animator thinks:
##   f    natural frequency (Hz): how fast it answers (settles in roughly 1/f s);
##   zeta damping: 0 = rings forever, < 1 overshoots then settles, 1 = critically damped,
##        > 1 sluggish;
##   r    initial response: 0 = starts slowly (weight), 1 = starts with the target, > 1 overshoots
##        the start (snappy), < 0 moves the wrong way first (anticipation).
## y + k1·y' + k2·y'' = x + k3·x', k1 = zeta/(pi f), k2 = 1/(2 pi f)^2, k3 = r·zeta/(2 pi f).
## Semi-implicit Euler with k2 clamped for stability, so any frame time is safe (a 0.4 s software
## frame never explodes). Pure: no nodes, no clock — the caller passes dt.

var f := 1.0
var zeta := 1.0
var r := 0.0
## Output (position) and its velocity.
var y := 0.0
var v := 0.0

var _k1 := 0.0
var _k2 := 0.0
var _k3 := 0.0
var _xp := 0.0


func _init(freq := 1.0, damping := 1.0, response := 0.0, start := 0.0) -> void:
	y = start
	_xp = start
	set_params(freq, damping, response)


## Changes the character of the spring without moving it (the mind retunes springs by mood).
func set_params(freq: float, damping: float, response: float) -> void:
	f = maxf(freq, 0.001)
	zeta = maxf(damping, 0.0)
	r = response
	_k1 = zeta / (PI * f)
	_k2 = 1.0 / ((TAU * f) * (TAU * f))
	_k3 = r * zeta / (TAU * f)


## Jumps to `x` at rest.
func reset(x: float) -> void:
	y = x
	v = 0.0
	_xp = x


## Advances dt seconds towards target x (its velocity estimated from the last target).
func step(x: float, dt: float) -> float:
	if dt <= 0.0:
		return y
	var xd := (x - _xp) / dt
	_xp = x
	return step_with_velocity(x, xd, dt)


## Advances dt seconds towards target x moving at xd.
func step_with_velocity(x: float, xd: float, dt: float) -> float:
	if dt <= 0.0:
		return y
	# Sub-steps keep a long frame (slow renderer) close to the continuous response.
	var n := maxi(1, ceili(dt / MAX_STEP))
	var h := dt / float(n)
	for i in n:
		var k2s := maxf(_k2, maxf(h * h * 0.5 + h * _k1 * 0.5, h * _k1))
		y += h * v
		v += h * (x + _k3 * xd - y - _k1 * v) / k2s
	return y


## Largest integration step (s).
const MAX_STEP := 1.0 / 60.0
