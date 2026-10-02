class_name LivingShots
extends RefCounted
## Narrative camera of the living prototype (Loop 5). Owner: animator.
## The camera follows MIKU's story focus (Miku.story_focus(): which part of the story matters now
## and the world points that tell it) and never cuts: every rig channel is a heavy second-order
## spring (target, yaw, pitch, distance, fov), so moves are long, with mass, start slowly and
## settle. Framing per kind (yaw from MIKU's front, +Z, towards her left; pitch up; fov; margin):
##   miku     LIFE: her whole figure in a soft three-quarter, a slow drift;
##   puppet   MIKU and the hands she controls (two-shot);
##   work     MIKU and the world she builds, lower angle (the world's scale against her);
##   wide     many hands: the camera opens to hold MIKU, every hand and the world;
##   emotion  the push-in on her face and chest when she loses or regains composure;
##   user     she looks into the lens: frontal bust (the user is the camera);
##   file     MIKU and the configuration artifact.
## Pure state (springs) + one step per frame; the CameraDirector applies the rig.

const STYLE := {
	&"miku": [0.36, 0.05, 34.0, 1.18, 9.0],
	&"puppet": [0.5, 0.1, 38.0, 1.22, 9.0],
	&"work": [-0.42, 0.02, 38.0, 1.18, 9.5],
	&"wide": [-0.15, 0.14, 44.0, 1.12, 12.0],
	&"emotion": [0.22, 0.03, 30.0, 1.9, 4.2],
	&"user": [0.05, 0.03, 30.0, 2.0, 4.0],
	&"file": [0.28, 0.04, 32.0, 1.35, 5.0],
}
## Spring frequency (Hz) of the channels; the push-in on emotion is a little quicker.
const F_TARGET := 0.2
const F_ANGLE := 0.13
const F_DISTANCE := 0.15
const F_FOV := 0.18
const EMOTION_SPEED := 1.6
## Slow drift of the yaw (rad, period s): the camera breathes with her.
const DRIFT := Vector2(0.05, 23.0)
## Limits.
const MIN_Y := -3.6
const DISTANCE_RANGE := Vector2(3.0, 40.0)
const PITCH_RANGE := Vector2(-0.35, 0.9)

var target := SecondOrder3.new(F_TARGET, 1.0, 0.0)
var yaw := SecondOrder.new(F_ANGLE, 1.0, 0.0)
var pitch := SecondOrder.new(F_ANGLE, 1.0, 0.0)
var distance := SecondOrder.new(F_DISTANCE, 1.0, 0.0, 10.0)
var fov := SecondOrder.new(F_FOV, 1.0, 0.0, 36.0)
var time := 0.0
var kind: StringName = &""
var _snapped := false


## Goal shot of a focus: fills `out` (centre, yaw, pitch, distance, fov) from the focus points.
static func goal(focus_kind: StringName, points: PackedVector3Array, aspect: float, t: float,
		out: CameraShots.Shot) -> CameraShots.Shot:
	var st: Array = STYLE.get(focus_kind, STYLE[&"miku"])
	var c := Vector3.ZERO
	for p in points:
		c += p
	c = c / float(maxi(points.size(), 1))
	var r := 0.0
	for p in points:
		r = maxf(r, (p - c).length())
	var f := float(st[2])
	var half_v := deg_to_rad(f) * 0.5
	var half_h := atan(tan(half_v) * maxf(aspect, 0.1))
	var d := (r * float(st[3])) / sin(minf(half_v, half_h))
	d = clampf(maxf(d, float(st[4]) * 0.5), DISTANCE_RANGE.x, DISTANCE_RANGE.y)
	if focus_kind == &"emotion" or focus_kind == &"user":
		d = float(st[4])
	var drift := DRIFT.x * sin(t * TAU / DRIFT.y)
	return out.setup(c, float(st[0]) + drift, float(st[1]), d, f)


## Places every channel on the goal (composition).
func snap(focus_kind: StringName, points: PackedVector3Array, aspect: float, out: CameraShots.Shot) -> void:
	goal(focus_kind, points, aspect, time, out)
	if points.is_empty():
		# Nothing to frame yet (first frame): snap again when the story has points.
		_snapped = false
		return
	target.reset(out.target)
	yaw.reset(out.yaw)
	pitch.reset(out.pitch)
	distance.reset(out.distance)
	fov.reset(out.fov)
	kind = focus_kind
	_snapped = true


## Continues from a rig the user left (no jump when the story takes the camera back).
func take_from(rig: CameraShots.Shot) -> void:
	target.reset(rig.target)
	yaw.reset(rig.yaw)
	pitch.reset(rig.pitch)
	distance.reset(rig.distance)
	fov.reset(rig.fov)
	_snapped = true


## Advances the camera towards the focus; writes the rig into `out`.
func step(dt: float, focus_kind: StringName, points: PackedVector3Array, aspect: float, goal_shot: CameraShots.Shot,
		out: CameraShots.Shot) -> CameraShots.Shot:
	time += dt
	if not _snapped:
		snap(focus_kind, points, aspect, out)
		return clamp_rig(out)
	if points.is_empty():
		return clamp_rig(out.setup(target.y, yaw.y, pitch.y, distance.y, fov.y))
	kind = focus_kind
	goal(focus_kind, points, aspect, time, goal_shot)
	var k := EMOTION_SPEED if focus_kind == &"emotion" or focus_kind == &"user" else 1.0
	target.set_params(F_TARGET * k, 1.0, 0.0)
	yaw.set_params(F_ANGLE * k, 1.0, 0.0)
	pitch.set_params(F_ANGLE * k, 1.0, 0.0)
	distance.set_params(F_DISTANCE * k, 1.0, 0.0)
	fov.set_params(F_FOV * k, 1.0, 0.0)
	target.step(goal_shot.target, dt)
	yaw.step(yaw.y + angle_difference(yaw.y, goal_shot.yaw), dt)
	pitch.step(goal_shot.pitch, dt)
	distance.step(goal_shot.distance, dt)
	fov.step(goal_shot.fov, dt)
	out.setup(target.y, yaw.y, pitch.y, distance.y, fov.y)
	return clamp_rig(out)


## Never below the floor of the scene (under the hem), pitch and distance in range.
static func clamp_rig(s: CameraShots.Shot) -> CameraShots.Shot:
	s.pitch = clampf(s.pitch, PITCH_RANGE.x, PITCH_RANGE.y)
	s.distance = clampf(s.distance, DISTANCE_RANGE.x, DISTANCE_RANGE.y)
	if s.target.y + sin(s.pitch) * s.distance < MIN_Y:
		s.pitch = asin(clampf((MIN_Y - s.target.y) / s.distance, -1.0, 1.0))
	return s
