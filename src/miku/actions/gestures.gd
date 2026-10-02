class_name Gestures
extends RefCounted
## MIKU's arm gestures as goals in WORLD space (Loop 5). Owner: animator. Pure; survives the
## migration to the native animation stack (it only says where the hand goes, how the palm and
## fingers face, where the elbow points and which finger pose — not how bones get there).
##
## Every gesture is a function of: the shoulder S, the arm's reach L, the target T, her body frame
## (x = her left, y = up, z = forward), the arm's side (sx +1 left / -1 right) and a phase for the
## rhythmic ones. Rest gestures depend on mood: calm = the dancer's low rounded arms (bras bas),
## rigid = arms held away from the body, fingers tense.
## Anticipation is its own gesture (`windup`: the hand gathers in towards the chest, fingers
## closing) and actions always play it before the gesture that releases (ActionScript).

## Gesture ids.
const REST_CALM := &"rest_calm"
const REST_FOCUS := &"rest_focus"
const REST_TENSE := &"rest_tense"
const REST_RIGID := &"rest_rigid"
const REST_SOFT := &"rest_soft"
const WINDUP := &"windup"
const REACH := &"reach"
const CONDUCT := &"conduct"
const CALL := &"call"
const POINT := &"point"
const PUSH := &"push"
const COMPRESS := &"compress"
const SMOOTH := &"smooth"
const PINCH := &"pinch"
const FLICK := &"flick"
const CHIN := &"chin"
const PALM_UP := &"palm_up"
const SELF := &"self"
const CLAW := &"claw"
const FREEZE := &"freeze"

const ALL: Array[StringName] = [REST_CALM, REST_FOCUS, REST_TENSE, REST_RIGID, REST_SOFT, WINDUP, REACH,
	CONDUCT, CALL, POINT, PUSH, COMPRESS, SMOOTH, PINCH, FLICK, CHIN, PALM_UP, SELF, CLAW, FREEZE]

## Rest gesture of each mood (MikuMind.Mood order).
const REST_BY_MOOD: Array[StringName] = [REST_CALM, REST_FOCUS, REST_TENSE, REST_RIGID, REST_SOFT]


## Output of goal(): world-space hand goal.
class ArmGoal:
	extends RefCounted
	var pos := Vector3.ZERO
	var palm := Vector3.DOWN
	var point := Vector3.FORWARD
	var pole := Vector3.DOWN
	var pose: StringName = &"relaxed"
	var speed := 1.0


## Fills `out` with gesture `g` of the arm whose shoulder is `s` (world), reach `l`, towards
## target `t`, in body frame `body` (x her left, y up, z forward), side sx, rhythm phase `ph`
## (radians, rhythmic gestures), chest point `chest` and head point `head`.
static func goal(g: StringName, s: Vector3, l: float, t: Vector3, body: Basis, sx: float, ph: float,
		chest: Vector3, head: Vector3, out: ArmGoal) -> void:
	var left := body.x
	var up := body.y
	var fwd := body.z
	var out_side := left * sx
	var to_t := t - s
	var dir := to_t.normalized() if to_t.length_squared() > 1e-6 else fwd
	out.speed = 1.0
	# Elbows: out to the side and a little back (soft, rounded arms).
	out.pole = (out_side * 0.7 - up * 0.6 - fwd * 0.4).normalized()
	match g:
		REST_CALM:
			# Bras bas: hands low in front of the skirt, rounded, palms in and up, fingers soft.
			out.pos = s + up * -0.86 * l + fwd * 0.33 * l - out_side * 0.1 * l
			out.pole = (out_side * 0.9 - up * 0.3 - fwd * 0.35).normalized()
			out.palm = (-out_side * 0.7 + up * 0.55 + fwd * 0.25).normalized()
			out.point = (-out_side * 0.45 - up * 0.6 + fwd * 0.55).normalized()
			out.pose = &"ballet"
		REST_SOFT:
			out.pos = s + up * -0.9 * l + fwd * 0.2 * l + out_side * 0.02 * l
			out.palm = (-out_side * 0.85 + fwd * 0.2).normalized()
			out.point = (-up * 0.9 + fwd * 0.3).normalized()
			out.pose = &"relaxed"
		REST_FOCUS:
			# Ready: forearm lifted a little towards the work, fingers loose.
			out.pos = s + up * -0.64 * l + fwd * 0.52 * l + (dir - up * dir.dot(up)) * 0.12 * l
			out.palm = (-up * 0.7 - out_side * 0.5).normalized()
			out.point = (fwd * 0.8 - up * 0.3 - out_side * 0.25).normalized()
			out.pose = &"relaxed"
		REST_TENSE:
			# Hands closer to the body, wrists bent, fingers tense.
			out.pos = s + up * -0.95 * l + fwd * 0.25 * l - out_side * 0.05 * l
			out.palm = (-out_side * 0.8 - fwd * 0.2).normalized()
			out.point = (-up * 0.85 + fwd * 0.25).normalized()
			out.pose = &"claw"
			out.pole = (out_side * 0.6 - fwd * 0.8).normalized()
		REST_RIGID:
			# Arms held away from the body, straight, fingers spread and tense: not human.
			out.pos = s + up * -0.86 * l + out_side * 0.42 * l + fwd * 0.12 * l
			out.palm = (-up * 0.85 - fwd * 0.3).normalized()
			out.point = (-up * 0.55 + out_side * 0.75).normalized()
			out.pose = &"claw"
			out.pole = (-fwd).normalized()
		WINDUP:
			# Anticipation: the hand gathers in towards the chest, fingers closing.
			out.pos = chest + fwd * 0.22 * l + out_side * 0.12 * l + up * 0.08 * l
			out.palm = (-out_side * 0.3 - fwd * 0.9).normalized()
			out.point = (up * 0.7 - out_side * 0.4).normalized()
			out.pose = &"call"
			out.pole = (out_side - up * 0.8).normalized()
		REACH, CONDUCT:
			var rr := 0.82 if g == REACH else 0.74
			var lat0 := dir.cross(up).normalized()
			out.pos = s + dir * rr * l + up * 0.06 * l
			if g == CONDUCT:
				out.pos += lat0 * sin(ph) * 0.2 * l + up * sin(ph * 0.5) * 0.12 * l
			out.palm = (-up * 0.85 + dir * 0.2).normalized()
			out.point = (dir + up * 0.12).normalized()
			out.pose = &"open" if g == REACH else &"conduct"
		CALL:
			out.pos = s + dir * 0.62 * l + up * 0.22 * l
			out.palm = (up * 0.8 - dir * 0.4).normalized()
			out.point = (dir * 0.8 + up * 0.4).normalized()
			out.pose = &"call"
		POINT:
			out.pos = s + dir * 0.93 * l
			out.palm = (-up * 0.6 - out_side * 0.6).normalized()
			out.point = dir
			out.pose = &"point"
			out.pole = (out_side * 0.6 - up).normalized()
		PUSH:
			out.pos = s + dir * 0.8 * l + sin(ph) * dir * 0.08 * l
			out.palm = dir
			out.point = (up * 0.85 + out_side * 0.25).normalized()
			out.pose = &"push"
		COMPRESS:
			# Both hands hold an invisible sphere in front of her and squeeze it in rhythm.
			var c := chest + fwd * 0.62 * l + (dir - up * dir.dot(up)) * 0.2 * l - up * 0.12 * l
			var squeeze := 0.5 + 0.5 * sin(ph)
			out.pos = c + out_side * lerpf(0.34, 0.17, squeeze) * l
			out.palm = -out_side
			out.point = (fwd * 0.6 + up * 0.5).normalized()
			out.pose = &"cup"
		SMOOTH:
			# Long sweeping arcs towards the work: the dancer's port de bras.
			var lat := dir.cross(up).normalized()
			out.pos = s + dir * 0.72 * l + lat * sin(ph) * 0.24 * l + up * (0.1 + 0.08 * cos(ph)) * l
			out.palm = (-up * 0.7 + dir * 0.5).normalized()
			out.point = (dir + lat * cos(ph) * 0.4).normalized()
			out.pose = &"smooth"
		PINCH:
			var lat2 := dir.cross(up).normalized()
			out.pos = s + dir * 0.7 * l + up * 0.12 * l + lat2 * sin(ph * 1.7) * 0.03 * l
			out.palm = (-up * 0.4 - out_side * 0.8).normalized()
			out.point = (dir + up * 0.25).normalized()
			out.pose = &"pinch"
		FLICK:
			out.pos = s + (dir * 0.7 + out_side * 0.45 + up * 0.2).normalized() * 0.92 * l
			out.palm = (fwd * 0.5 - up * 0.5 + out_side * 0.5).normalized()
			out.point = (out_side * 0.7 + dir * 0.5).normalized()
			out.pose = &"flick"
			out.speed = 1.8
		CHIN:
			out.pos = head + fwd * 0.12 * l - up * 0.17 * l + out_side * 0.04 * l
			out.palm = (-fwd * 0.6 + up * 0.3 - out_side * 0.5).normalized()
			out.point = (up * 0.8 - out_side * 0.3).normalized()
			out.pose = &"relaxed"
			out.pole = (-up + out_side * 0.4).normalized()
		PALM_UP:
			out.pos = s + fwd * 0.6 * l - up * 0.45 * l + out_side * 0.1 * l + (dir - fwd) * 0.1 * l
			out.palm = (up * 0.9 + fwd * 0.2).normalized()
			out.point = (fwd * 0.8 + out_side * 0.2).normalized()
			out.pose = &"open"
			out.pole = (-up * 0.9 + out_side * 0.35 - fwd * 0.2).normalized()
		SELF:
			# Her own hand raised before her face, turning slowly while she looks at it.
			out.pos = head + fwd * 0.42 * l - up * 0.22 * l + out_side * 0.16 * l
			out.palm = (-fwd * cos(ph * 0.5) + out_side * sin(ph * 0.5)).normalized()
			out.point = (up * 0.85 - out_side * 0.2).normalized()
			out.pose = &"ballet"
			out.pole = (out_side - up).normalized()
		CLAW:
			# Command: arm thrust towards the target, fingers spread and tense, wrist locked.
			out.pos = s + dir * 0.9 * l + sin(ph) * dir * 0.05 * l
			out.palm = (-up * 0.5 + dir * 0.6).normalized()
			out.point = (dir + up * 0.05).normalized()
			out.pose = &"claw"
			out.speed = 1.6
			out.pole = (out_side * 0.3 - up).normalized()
		_:
			# FREEZE and unknown ids: keep the current goal (the caller does not overwrite it).
			pass
