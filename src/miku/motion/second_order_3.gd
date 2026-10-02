class_name SecondOrder3
extends RefCounted
## SecondOrder on a Vector3 (same parameters and integration; see SecondOrder). Used for hand
## targets, puppet-hand positions, gaze points and camera rigs. Pure; no allocation per step.

var f := 1.0
var zeta := 1.0
var r := 0.0
var y := Vector3.ZERO
var v := Vector3.ZERO

var _k1 := 0.0
var _k2 := 0.0
var _k3 := 0.0
var _xp := Vector3.ZERO


func _init(freq := 1.0, damping := 1.0, response := 0.0, start := Vector3.ZERO) -> void:
	y = start
	_xp = start
	set_params(freq, damping, response)


func set_params(freq: float, damping: float, response: float) -> void:
	f = maxf(freq, 0.001)
	zeta = maxf(damping, 0.0)
	r = response
	_k1 = zeta / (PI * f)
	_k2 = 1.0 / ((TAU * f) * (TAU * f))
	_k3 = r * zeta / (TAU * f)


func reset(x: Vector3) -> void:
	y = x
	v = Vector3.ZERO
	_xp = x


## Forgets the target's motion (the next step sees a target at rest at `x`).
func reset_target(x: Vector3) -> void:
	_xp = x


func step(x: Vector3, dt: float) -> Vector3:
	if dt <= 0.0:
		return y
	var xd := (x - _xp) / dt
	_xp = x
	return step_with_velocity(x, xd, dt)


## Like step, with an acceleration limit (units/s²): a heavy body cannot change its velocity
## faster than its mass allows (puppet hands). 0 = no limit.
func step_limited(x: Vector3, dt: float, max_accel: float) -> Vector3:
	if dt <= 0.0:
		return y
	var xd := (x - _xp) / dt
	_xp = x
	var n := maxi(1, ceili(dt / SecondOrder.MAX_STEP))
	var h := dt / float(n)
	for i in n:
		var k2s := maxf(_k2, maxf(h * h * 0.5 + h * _k1 * 0.5, h * _k1))
		y += h * v
		var a := (x + _k3 * xd - y - _k1 * v) / k2s
		if max_accel > 0.0 and a.length_squared() > max_accel * max_accel:
			a = a.normalized() * max_accel
		v += h * a
	return y


func step_with_velocity(x: Vector3, xd: Vector3, dt: float) -> Vector3:
	if dt <= 0.0:
		return y
	var n := maxi(1, ceili(dt / SecondOrder.MAX_STEP))
	var h := dt / float(n)
	for i in n:
		var k2s := maxf(_k2, maxf(h * h * 0.5 + h * _k1 * 0.5, h * _k1))
		y += h * v
		v += h * (x + _k3 * xd - y - _k1 * v) / k2s
	return y
