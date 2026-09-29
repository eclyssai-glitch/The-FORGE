class_name CameraShots
extends RefCounted
## Camera shots as pure data. Owner: animator. Used by CameraDirector; unit-tested in
## tests/unit/test_animation_camera_shots.gd.
##
## A shot is an orbit rig around `target`: the camera sits at
##     target + (sin(yaw)·cos(pitch), sin(pitch), cos(yaw)·cos(pitch)) · distance
## (yaw measured around +Y from +Z towards +X, pitch = elevation above the target) and looks at
## the target. `fov` is the vertical FOV (degrees). `offset` shifts the subject horizontally on
## screen in NDC (-1..1; +0.38 moves it to the centre of the right 62 % of the frame) and is
## applied through Camera3D.h_offset (a sideways shift of the camera: exact at the target depth,
## smaller for farther points — tests project with that shift).
##
## Composition (docs/VISUAL_DIRECTION.md, docs/ANIMATION.md):
## - FORGE: the structure fills ~55 % of the frame height, the core slightly above the optical
##   centre, low horizon.
## - UNIVERSE: far out, from outside the pillar ring and between two pillars — the chamber is a
##   warm point in the lower middle, the cold dormant seeds (src/world/universe.gd SEEDS, 62–70
##   units beyond the chamber) spread around it higher in the frame, all of them in the part of the
##   frame the HUD leaves free (universe_free_rect: right of the SITES panel, below the mode bar,
##   above the transport, left of the inspector/feed column).
## - OBSERVATORY: raised three-quarter view (the outer walls dominate the ring caps), subject
##   pushed right, into the free area beside the native panel (38 % of the width on the left).

## Floor of the chamber (world Y) and the minimum camera clearance above it.
const FLOOR_Y := -3.2
const FLOOR_CLEARANCE := 0.45
const PITCH_MIN := -0.32
const PITCH_MAX := 1.35
## Distance limits per mode (index = SessionState.Mode).
const DISTANCE_LIMITS: Array[Vector2] = [Vector2(14.0, 140.0), Vector2(4.8, 15.5), Vector2(6.0, 30.0)]
## UNIVERSE flight and focus: the rig target stays within this radius of the chamber (the seeds
## sit 62–70 units out and drift a little, so focusing one never clamps its centre).
const FLY_RADIUS := 74.0


## Orbit rig state. Fields are plain floats/vectors so a Shot can be reused every frame.
class Shot extends RefCounted:
	var target := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var distance := 10.0
	var fov := 40.0
	var offset := 0.0

	func setup(p_target: Vector3, p_yaw: float, p_pitch: float, p_distance: float, p_fov: float,
			p_offset: float = 0.0) -> Shot:
		target = p_target
		yaw = p_yaw
		pitch = p_pitch
		distance = p_distance
		fov = p_fov
		offset = p_offset
		return self

	func copy_from(o: Shot) -> Shot:
		return setup(o.target, o.yaw, o.pitch, o.distance, o.fov, o.offset)

	## Camera position in world space.
	func position() -> Vector3:
		var c := cos(pitch)
		return target + Vector3(sin(yaw) * c, sin(pitch), cos(yaw) * c) * distance

	## Camera3D.h_offset that moves the subject by `offset` NDC for a viewport aspect (w/h).
	func h_offset(aspect: float) -> float:
		return -offset * distance * tan(deg_to_rad(fov) * 0.5) * aspect

	func approx_equals(o: Shot) -> bool:
		return target.distance_to(o.target) < 1e-4 and absf(angle_difference(yaw, o.yaw)) < 1e-4 \
			and absf(pitch - o.pitch) < 1e-4 and absf(distance - o.distance) < 1e-4 \
			and absf(fov - o.fov) < 1e-4 and absf(offset - o.offset) < 1e-4


# --- Mode shots -------------------------------------------------------------------------------

## Base yaw of the FORGE shot (a slight three-quarter view reads the rings as volumes).
const FORGE_YAW := 0.42
## UNIVERSE shot. Yaw sits exactly between two pillars (pillar p stands at TAU·(p + 0.5)/24, so
## multiples of TAU/24 fall in the gaps): TAU/24 looks from the gap facing the three seeds.
## Pitched high enough that the near pillars' tops stay below the structure on screen. Wide and
## far enough that the three seeds (spread ~110° around the far side of the chamber) fit in the
## part of the frame the HUD leaves free at 1600×900 and at 1280×720 (universe_free_rect; the HUD
## has fixed pixel sizes, so 1280×720 is the tighter frame); UNIVERSE_OFFSET centres their spread
## there. The chamber sits near the frame centre, the seeds open to its left, above it and to its right.
const UNIVERSE_YAW := TAU * 1.0 / 24.0
const UNIVERSE_PITCH := 0.4
const UNIVERSE_DISTANCE := 108.0
const UNIVERSE_FOV := 52.0
const UNIVERSE_OFFSET := 0.08
const UNIVERSE_TARGET := Vector3(0.0, 3.0, 0.0)
## HUD around the UNIVERSE frame (px, fixed sizes at any resolution): SITES panel up to x 288
## (and y 286), mode bar above y 70, transport and feed below `height − 220`, inspector column
## (top-right when something is selected) right of `width − 330`.
const UNIVERSE_HUD_LEFT := 310.0
const UNIVERSE_HUD_TOP := 70.0
const UNIVERSE_HUD_RIGHT := 330.0
const UNIVERSE_HUD_BOTTOM := 220.0
## OBSERVATORY shot: raised three-quarter view — low enough that the outer walls (the finished
## metal read in FORGE) dominate the ring caps — pushed right by OBSERVATORY_OFFSET NDC to the
## centre of the free 62 % of the frame (the native sheet takes 38 % on the left).
const OBSERVATORY_TARGET := Vector3(0.0, -0.3, 0.0)
const OBSERVATORY_YAW := -0.62
const OBSERVATORY_PITCH := 0.45
const OBSERVATORY_DISTANCE := 15.5
const OBSERVATORY_FOV := 40.0
const OBSERVATORY_OFFSET := 0.38
## Fraction of the frame width the OBSERVATORY sheet covers on the left.
const OBSERVATORY_SHEET := 0.38
## Slow orbit while the structure is built (rad/s of sim time), and during the final reveal.
const BUILD_ORBIT := 0.011
const FINAL_ORBIT := 0.05


## Part of a `frame` (px) the UNIVERSE HUD leaves free: x in [310, w − 330], y in [70, h − 220]
## (1600×900: x 310–1270, y 70–680; 1280×720: x 310–950, y 70–500).
static func universe_free_rect(frame: Vector2) -> Rect2:
	return Rect2(UNIVERSE_HUD_LEFT, UNIVERSE_HUD_TOP, frame.x - UNIVERSE_HUD_LEFT - UNIVERSE_HUD_RIGHT,
		frame.y - UNIVERSE_HUD_TOP - UNIVERSE_HUD_BOTTOM)


## Writes the base shot of `mode` (SessionState.Mode) into `out`.
static func mode_shot(mode: int, out: Shot) -> Shot:
	match mode:
		SessionState.Mode.UNIVERSE:
			return out.setup(UNIVERSE_TARGET, UNIVERSE_YAW, UNIVERSE_PITCH, UNIVERSE_DISTANCE, UNIVERSE_FOV,
				UNIVERSE_OFFSET)
		SessionState.Mode.OBSERVATORY:
			return out.setup(OBSERVATORY_TARGET, OBSERVATORY_YAW, OBSERVATORY_PITCH, OBSERVATORY_DISTANCE,
				OBSERVATORY_FOV, OBSERVATORY_OFFSET)
		_:
			return out.setup(Vector3(0.0, -0.45, 0.0), FORGE_YAW, 0.04, 11.2, 36.0)


# --- Cinematic cues (FORGE with Session.cinematic) --------------------------------------------

## Cue ids, in narrative order.
const CUE_DORMANT := &"cue_dormant"
const CUE_ACTIVATION := &"cue_activation"
const CUE_FRAGMENTS := &"cue_fragments"
const CUE_BUILDING := &"cue_building"
const CUE_FINISHING := &"cue_finishing"
const CUE_VERIFICATION := &"cue_verification"
const CUE_FINAL := &"cue_final"


## Id of the cue for the current world (which event the camera is telling).
static func cue_id(w: WorldState) -> StringName:
	if w.finalized_at >= 0.0:
		return CUE_FINAL
	if w.verification_at >= 0.0:
		return CUE_VERIFICATION
	if w.materials_at >= 0.0:
		return CUE_FINISHING
	if w.seeded_at >= 0.0:
		return CUE_BUILDING
	if w.fragments_at >= 0.0:
		return CUE_FRAGMENTS
	if w.core_activation_at >= 0.0:
		return CUE_ACTIVATION
	return CUE_DORMANT


## Yaw of the slow construction orbit at sim time t (continuous from seeding to the lock).
static func build_yaw(w: WorldState, t: float) -> float:
	if w.seeded_at < 0.0:
		return FORGE_YAW
	var end := t if w.finalized_at < 0.0 else minf(t, w.finalized_at)
	return FORGE_YAW + BUILD_ORBIT * maxf(end - w.seeded_at, 0.0)


## Writes the cinematic cue shot for (world, t) into `out` and returns its id.
## Activation: approach. Fragments: pull back. Building/finishing: slow orbit.
## Verification: low angle. Final: slow orbital reveal.
static func cue(w: WorldState, t: float, out: Shot) -> StringName:
	var id := cue_id(w)
	match id:
		CUE_ACTIVATION:
			out.setup(Vector3(0.0, -0.1, 0.0), 0.3, 0.2, 7.0, 34.0)
		CUE_FRAGMENTS:
			out.setup(Vector3(0.0, -0.2, 0.0), 0.5, 0.2, 15.0, 38.0)
		CUE_BUILDING:
			out.setup(Vector3(0.0, -0.35, 0.0), build_yaw(w, t), 0.16, 12.4, 36.0)
		CUE_FINISHING:
			out.setup(Vector3(0.0, -0.45, 0.0), build_yaw(w, t), 0.11, 11.0, 36.0)
		CUE_VERIFICATION:
			out.setup(Vector3(0.0, 0.05, 0.0), build_yaw(w, t) + 0.12, -0.1, 10.4, 38.0)
		CUE_FINAL:
			var reveal := maxf(t - w.finalized_at, 0.0)
			out.setup(Vector3(0.0, -0.4, 0.0), build_yaw(w, t) + FINAL_ORBIT * reveal, 0.15, 12.2, 36.0)
		_:
			mode_shot(SessionState.Mode.FORGE, out)
			out.distance = 10.2
	return id


## Ids of the plain mode shots (index = SessionState.Mode).
const MODE_IDS: Array[StringName] = [&"mode_0", &"mode_1", &"mode_2"]


## Desired shot for the session state: the cue when cinematic in FORGE, else the mode shot.
## Returns the shot id (a cue id or &"mode_<n>"). The result is clamped.
static func desired(mode: int, cinematic: bool, w: WorldState, t: float, out: Shot) -> StringName:
	var id: StringName
	if cinematic and mode == SessionState.Mode.FORGE:
		id = cue(w, t, out)
	else:
		mode_shot(mode, out)
		id = MODE_IDS[clampi(mode, 0, MODE_IDS.size() - 1)]
	clamp_shot(out, mode)
	return id


# --- Focus on an entity (Session.focus_requested) ---------------------------------------------

## Fraction of the half frame (vertical and horizontal) the focused entity's extent fills.
const FOCUS_FILL := 0.6
## FORGE focus looks down at least this much, so a ring reads as a ring and not as a line.
const FOCUS_MIN_PITCH := 0.3
## Horizontal reach of a focus target from the chamber centre per mode (index = Mode): in FORGE
## and OBSERVATORY the camera stays with the chamber; UNIVERSE reaches the seeds.
const FOCUS_REACH: Array[float] = [FLY_RADIUS, 8.0, 8.0]
## UNIVERSE targets farther than FOCUS_FAR from the centre (the seeds) are seen from outside,
## turned SEED_FOCUS_YAW off the radial line and shifted SEED_FOCUS_OFFSET (NDC) on screen, so the
## seed holds the left third and the lit chamber stays in the background on the right third —
## the dormant seed read against the place where constructs are born. SEED_FOCUS_PITCH above.
## SEED_FOCUS_FOV: a tele lens of its own (the wide UNIVERSE lens would push the chamber behind
## the seed); the flight to the seed narrows the lens along the way.
const FOCUS_FAR := 30.0
const SEED_FOCUS_YAW := 0.42
const SEED_FOCUS_OFFSET := -0.22
const SEED_FOCUS_PITCH := 0.16
const SEED_FOCUS_FOV := 38.0


## True when `mode` may frame a target centred at `centre` (FOCUS_REACH).
static func focus_reachable(mode: int, centre: Vector3) -> bool:
	var reach: float = FOCUS_REACH[clampi(mode, 0, FOCUS_REACH.size() - 1)]
	return Vector2(centre.x, centre.z).length() <= reach + 1e-3


## Distance at which `bounds` (world AABB of a roughly round entity: rings, spheres, seeds)
## fills at most FOCUS_FILL of the frame, seen from `pitch` with vertical `fov` (degrees),
## subject shifted by `offset` NDC, viewport `aspect` (w/h). The entity is a vertical cylinder
## (radius r = half the wider horizontal side, so AABB corners do not inflate rings; half height
## h), with perspective: vertically its half extent r·|sin p| + h·cos p is taken at the depth of
## the near rim (d − r·cos p − h·|sin p|); horizontally the widest rim point subtends
## r / sqrt(d² − r²).
static func fit_distance(bounds: AABB, pitch: float, fov: float, offset: float, aspect: float) -> float:
	var r := maxf(bounds.size.x, bounds.size.z) * 0.5
	var h := bounds.size.y * 0.5
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * maxf(aspect, 0.1) * maxf(1.0 - absf(offset), 0.1)
	var sp := absf(sin(pitch))
	var cp := cos(pitch)
	var d_v := (r * sp + h * cp) / (tan_v * FOCUS_FILL) + r * cp + h * sp
	var k := 1.0 / (tan_h * FOCUS_FILL)
	var d_h := r * sqrt(1.0 + k * k)
	return maxf(d_v, d_h)


## Writes into `out` the shot that frames `bounds` in `mode`, starting from the `current` rig.
## Keeps the mode (fov and screen offset of the mode shot; clamped to the mode limits) and the
## current yaw, so the camera moves towards the entity instead of swinging around it. FORGE
## looks down at least FOCUS_MIN_PITCH; OBSERVATORY keeps its high pitch; UNIVERSE keeps its
## pitch near the chamber and, for far targets (seeds), looks from outside with the chamber
## behind (SEED_FOCUS_*, own fov). Callers check focus_reachable() first. Returns `out`.
static func focus_shot(mode: int, bounds: AABB, current: Shot, aspect: float, out: Shot) -> Shot:
	var yaw := current.yaw
	var current_pitch := current.pitch
	mode_shot(mode, out)
	var pitch := out.pitch
	var centre := bounds.get_center()
	match mode:
		SessionState.Mode.FORGE:
			pitch = maxf(current_pitch, FOCUS_MIN_PITCH)
		SessionState.Mode.UNIVERSE:
			if Vector2(centre.x, centre.z).length() > FOCUS_FAR:
				yaw = atan2(centre.x, centre.z) + SEED_FOCUS_YAW
				pitch = SEED_FOCUS_PITCH
				out.offset = SEED_FOCUS_OFFSET
				out.fov = SEED_FOCUS_FOV
	out.target = centre
	out.yaw = yaw
	out.pitch = pitch
	out.distance = fit_distance(bounds, pitch, out.fov, out.offset, aspect)
	return clamp_shot(out, mode)


# --- Limits and blending ----------------------------------------------------------------------

## Keeps a shot inside the limits of `mode`: distance range of the mode plus clamp_rig (pitch
## range, target reach, camera above the floor — never through y = FLOOR_Y). Returns the same shot.
static func clamp_shot(s: Shot, mode: int) -> Shot:
	var lim: Vector2 = DISTANCE_LIMITS[clampi(mode, 0, DISTANCE_LIMITS.size() - 1)]
	s.distance = clampf(s.distance, lim.x, lim.y)
	return clamp_rig(s)


## The limits shared by every mode: pitch range, target within FLY_RADIUS and above the floor, and
## the camera at least FLOOR_CLEARANCE above the floor (pitch raised when needed). Applied to the
## rig after every blend: a blend of two clamped shots is not clamped (pitch, distance and target
## interpolate independently, so e.g. a low close shot blending into a far one dips through the
## floor midway). Mode-independent, so a transition between modes keeps its distance curve.
static func clamp_rig(s: Shot) -> Shot:
	s.pitch = clampf(s.pitch, PITCH_MIN, PITCH_MAX)
	s.target.y = maxf(s.target.y, FLOOR_Y + FLOOR_CLEARANCE)
	var flat := Vector2(s.target.x, s.target.z)
	if flat.length() > FLY_RADIUS:
		flat = flat.normalized() * FLY_RADIUS
		s.target.x = flat.x
		s.target.z = flat.y
	var min_y := FLOOR_Y + FLOOR_CLEARANCE
	if s.target.y + sin(s.pitch) * s.distance < min_y:
		s.pitch = asin(clampf((min_y - s.target.y) / s.distance, -1.0, 1.0))
	return s


## out = a -> b at t (0..1): shortest-arc yaw, linear everything else. Not clamped: the caller
## applies clamp_rig to the result (CameraDirector does, every frame).
static func blend(a: Shot, b: Shot, t: float, out: Shot) -> Shot:
	return out.setup(a.target.lerp(b.target, t), lerp_angle(a.yaw, b.yaw, t),
		lerpf(a.pitch, b.pitch, t), lerpf(a.distance, b.distance, t), lerpf(a.fov, b.fov, t),
		lerpf(a.offset, b.offset, t))
