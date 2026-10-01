class_name LimbIK
extends RefCounted
## Two-bone IK and basis helpers for the procedural body (Loop 5). Owner: animator. Pure math.


## Elbow position of a two-bone chain from shoulder `s` to target `t` with segment lengths
## `l1`, `l2`, bending towards `pole` (a direction). The reach is clamped just inside the
## chain's span, so a target out of reach straightens the arm towards it (never pops).
static func elbow(s: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := t - s
	var dist := d.length()
	var dir := d / dist if dist > 1e-6 else Vector3.DOWN
	dist = clampf(dist, absf(l1 - l2) + 1e-4, (l1 + l2) * 0.9995)
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 1e-8:
		perp = dir.cross(Vector3.RIGHT)
		if perp.length_squared() < 1e-8:
			perp = dir.cross(Vector3.FORWARD)
	perp = perp.normalized()
	return s + dir * a + perp * h


## Orthonormal basis from a primary direction (Y) and a secondary one (Z, made orthogonal).
static func frame(primary: Vector3, secondary: Vector3) -> Basis:
	var y := primary.normalized()
	var z := secondary - y * secondary.dot(y)
	if z.length_squared() < 1e-8:
		z = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
		if z.length_squared() < 1e-8:
			z = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	z = z.normalized()
	var x := y.cross(z)
	return Basis(x, y, z)


## Rotation taking the frame (rest_primary, rest_secondary) to (primary, secondary).
static func align(rest_primary: Vector3, rest_secondary: Vector3, primary: Vector3,
		secondary: Vector3) -> Quaternion:
	var b := frame(primary, secondary) * frame(rest_primary, rest_secondary).inverse()
	return b.get_rotation_quaternion()


## Shortest-arc rotation from direction `a` to direction `b`.
static func arc(a: Vector3, b: Vector3) -> Quaternion:
	var an := a.normalized()
	var bn := b.normalized()
	var d := an.dot(bn)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var axis := an.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-8:
			axis = an.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(an.cross(bn).normalized(), acos(clampf(d, -1.0, 1.0)))


## Yaw (around +Y, towards +X) and pitch (positive = down) of a direction; +Z is yaw 0.
static func yaw_pitch(d: Vector3) -> Vector2:
	var h := Vector2(d.x, d.z).length()
	return Vector2(atan2(d.x, d.z), -atan2(d.y, maxf(h, 1e-6)))


## Model-space rotation: pitch about +X (positive bows forward/down), yaw about +Y (towards her
## left, +X), roll about +Z (positive tilts the top towards -X, her right).
static func euler(pitch: float, yaw: float, roll: float) -> Quaternion:
	return Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch) * Quaternion(Vector3.BACK, roll)
