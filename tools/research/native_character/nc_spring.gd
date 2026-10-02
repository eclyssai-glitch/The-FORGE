class_name NCSpring
extends RefCounted
## SPIKE — second-order dynamics on a Vector3 (same model as round 1's SecondOrder: f, zeta, r).
## This stays OWN code in the proposed architecture: the native modifiers solve geometry (where the
## bones go for a given target) but have no mass; the TARGETS they chase carry mass, anticipation
## (r < 0) and overshoot (zeta < 1). Pure: the caller passes dt.

var f := 1.0
var zeta := 1.0
var r := 0.0
var y := Vector3.ZERO
var v := Vector3.ZERO
var _xp := Vector3.ZERO


func _init(freq: float = 1.0, damping: float = 1.0, response: float = 0.0, start: Vector3 = Vector3.ZERO) -> void:
	tune(freq, damping, response)
	y = start
	_xp = start


func tune(freq: float, damping: float, response: float) -> void:
	f = maxf(freq, 0.01)
	zeta = damping
	r = response


func reset(p: Vector3) -> void:
	y = p
	_xp = p
	v = Vector3.ZERO


func step(x: Vector3, dt: float) -> Vector3:
	if dt <= 0.0:
		return y
	var w := TAU * f
	var k1 := zeta / (PI * f)
	var k2 := 1.0 / (w * w)
	var k3 := r * zeta / w
	var xd := (x - _xp) / dt
	_xp = x
	# stability: k2 >= dt^2/4 + dt*k1/2 (semi-implicit Euler)
	var k2s := maxf(k2, maxf(dt * dt / 2.0 + dt * k1 / 2.0, dt * k1))
	y += v * dt
	v += dt * (x + k3 * xd - y - k1 * v) / k2s
	return y
