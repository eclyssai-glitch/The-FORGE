class_name GenesisShots
extends RefCounted
## Camera shots of the GENESIS scene as pure data (docs/VISUAL_DIRECTION.md §5, docs/ANIMATION.md
## "GENESIS — câmera"). Owner: animator. Same orbit rig as CameraShots.Shot (target, yaw from +Z
## towards +X, pitch = elevation, distance, vertical fov, NDC offset).
##
## - FORGE (hero): MIKU in the upper third, cut out against the warm core; planet and hands in the
##   lower third, in the foreground; a slight low angle (the camera below her chest looking up);
##   her hair leaves the frame at the top (scale).
## - UNIVERSE (system): high and far — orbits, the memory belt, the distant worlds; MIKU a pearl
##   flame at the centre with her hair opening into threads.
## - OBSERVATORY (relational): raised three-quarter view, closer; threads and pulses read first.
## - Cinematic (FORGE with Session.cinematic): one cue per movement of the story, each a slow
##   crane/dolly whose pose is a function of the simulation time (seek lands on the same framing),
##   plus a tiny ambient sway on MotionClock (the camera breathes, also when paused). Cue changes
##   are blended over Palette.T_CRANE by the CameraDirector (no cut).
## - style_frame_poses(): the hero framings saved by tools/style_frames.sh (StyleFrames).

const PITCH_MIN := -0.55
const PITCH_MAX := 1.35
## Distance limits per mode (index = SessionState.Mode: UNIVERSE, FORGE, OBSERVATORY).
const DISTANCE_LIMITS: Array[Vector2] = [Vector2(12.0, 150.0), Vector2(4.0, 48.0), Vector2(6.0, 90.0)]
## The rig target stays within this radius of MIKU's axis (the outer world orbits at 42).
const FLY_RADIUS := 50.0
## The camera never sinks below the mist (world Y).
const MIN_CAMERA_Y := -9.0
## Transition time of cue changes (crane), and of user-driven changes (mode, focus, reset).
const T_CUE := Palette.T_CRANE
const T_USER := Palette.T_CINEMATIC * 1.35

# --- Mode shots ---------------------------------------------------------------------------------
## Hero: low enough that the cradling left hand is in the frame (its palm above the bottom edge).
const FORGE_TARGET := Vector3(0.0, 3.7, 1.0)
const FORGE_YAW := 0.06
const FORGE_PITCH := -0.06
const FORGE_DISTANCE := 25.0
const FORGE_FOV := 37.0
const UNIVERSE_TARGET := Vector3(0.0, 14.0, -2.0)
const UNIVERSE_YAW := 0.2
const UNIVERSE_PITCH := 0.1
const UNIVERSE_DISTANCE := 56.0
const UNIVERSE_FOV := 46.0
## Observatory: high three-quarter, steep enough that the lines of sight to the world and the hands
## pass inside the memory belt's ring (no rocks over the planet), with the hair and its threads in frame.
const OBSERVATORY_TARGET := Vector3(0.0, 6.0, 1.0)
const OBSERVATORY_YAW := -0.78
const OBSERVATORY_PITCH := 0.75
const OBSERVATORY_DISTANCE := 36.0
const OBSERVATORY_FOV := 42.0

# --- Cinematic cues (FORGE) ---------------------------------------------------------------------
const CUE_PORTRAIT := &"cue_g_portrait"
const CUE_HERO := &"cue_g_hero"
const CUE_CRADLE := &"cue_g_cradle"
const CUE_ORBITS := &"cue_g_orbits"
const CUE_BELT := &"cue_g_belt"
const CUE_THREADS := &"cue_g_threads"
const CUE_STABLE := &"cue_g_stable"
## The cues are stations of ONE continuous camera path (cue_path): consecutive cues need no blend
## (the CameraDirector only blends into the path from a mode/user framing).
const CONTINUOUS_CUES := true
## Ambient sway of every cue (rad; periods s).
const SWAY_YAW := 0.018
const SWAY_PITCH := 0.008
const SWAY_PERIODS := Vector2(37.0, 53.0)
## The path: a close on the seed in the dark, then four designed moves, each eased in and out over
## its own duration from its event (s). Poses: [target, yaw, pitch, distance, fov].
##  1. Crane back at the awakening: from the seed (close, a little above, looking down into the dark
##     below the warm core) back to MIKU whole, as the seed's light reveals her. The camera pulls
##     away from the brow first (CRANE_PULL of the move) and only then tilts down to the figure, so
##     it never grazes the torso.
##  2. Dolly back while the hands rise and the dust gathers: the world appears below her (hero).
##  3. Low dolly to the cradle at the mantle: down and in, looking up — the molten world between the
##     hands fills the lower half, MIKU stands whole above it against the warm core (never the skirt
##     alone at the top of the frame).
##  4. Rise at the moons: up and out over the ring and the belt to a high three-quarter view where
##     the threads leave her hair for every body; the warm core stays in frame.
##  5. Recede at planet.stable: the camera cranes back from the whole — the fullest frame.
const SEED_POSE := [Vector3(0.0, -0.05, 0.12), -0.15, 0.3, 3.4, 30.0]
const CRANE_DELAY := 0.3
const CRANE_BACK := 6.2
## Share of the crane over which the distance grows (the target and the tilt follow over the rest,
## starting at CRANE_TILT_FROM of the move).
const CRANE_PULL := 0.7
const CRANE_TILT_FROM := 0.2
const PORTRAIT_POSE := [Vector3(0.0, 7.1, -0.4), 0.08, -0.02, 16.5, 36.0]
const HERO_DOLLY_DUR := 13.5
const HERO_POSE := [Vector3(0.0, 3.7, 1.0), 0.0, -0.06, 25.5, 37.0]
const CRADLE_DUR := 12.0
const CRADLE_POSE := [Vector3(0.2, 3.0, 1.0), -0.32, -0.38, 16.5, 44.0]
const RISE_DUR := 15.0
const RISE_POSE := [Vector3(0.0, 5.2, 0.6), 0.34, 0.16, 25.5, 42.0]
const RECEDE_DUR := 3.0
const RECEDE_POSE := [Vector3(0.0, 5.4, 0.4), 0.22, 0.1, 31.0, 42.0]
## Exposure trim asked of the world per station (World.set_exposure_trim): the belt rise looks away
## from the warm core into the indigo sky; the trim keeps the frame from sinking (eased by the world).
const TRIM_RISE := 1.12

# --- Focus --------------------------------------------------------------------------------------
const FOCUS_FILL := 0.55
## Focus keeps a slightly high view (from above): a low focus on the world or the hands put MIKU's
## hem alone at the top of the frame.
const FOCUS_PITCH := Vector2(0.36, 0.8)


## Writes the base shot of `mode` into `out`.
static func mode_shot(mode: int, out: CameraShots.Shot) -> CameraShots.Shot:
	match mode:
		SessionState.Mode.UNIVERSE:
			return out.setup(UNIVERSE_TARGET, UNIVERSE_YAW, UNIVERSE_PITCH, UNIVERSE_DISTANCE, UNIVERSE_FOV)
		SessionState.Mode.OBSERVATORY:
			return out.setup(OBSERVATORY_TARGET, OBSERVATORY_YAW, OBSERVATORY_PITCH, OBSERVATORY_DISTANCE, OBSERVATORY_FOV)
		_:
			return out.setup(FORGE_TARGET, FORGE_YAW, FORGE_PITCH, FORGE_DISTANCE, FORGE_FOV)


## Id of the cue telling the current movement of the story.
static func cue_id(g: GenesisState) -> StringName:
	if g.stable_at >= 0.0:
		return CUE_STABLE
	if g.links_at >= 0.0:
		return CUE_THREADS
	if g.belt_at >= 0.0:
		return CUE_BELT
	if g.moon_at(0) >= 0.0:
		return CUE_ORBITS
	if g.layer_at(0) >= 0.0:
		return CUE_CRADLE
	if g.hands_at >= 0.0:
		return CUE_HERO
	return CUE_PORTRAIT


## Writes the cue shot for (g, t) into `out` (ambient sway from `m`, MotionClock seconds) and
## returns its id. The pose is cue_path (continuous across cues) + a tiny ambient sway.
static func cue(g: GenesisState, t: float, m: float, out: CameraShots.Shot) -> StringName:
	var id := cue_id(g)
	cue_path(g, t, out)
	out.yaw += SWAY_YAW * sin(TAU * m / SWAY_PERIODS.x)
	out.pitch += SWAY_PITCH * sin(TAU * m / SWAY_PERIODS.y + 1.3)
	return id


## The cinematic camera path at (g, t) into `out`: the seed close, then each move eases from the
## pose it finds to its own pose over its duration from its event. Continuous in time (each move
## starts from the pose the previous one reached) and a pure function of the story.
static func cue_path(g: GenesisState, t: float, out: CameraShots.Shot) -> CameraShots.Shot:
	var brow := GenesisLayout.miku_point("forehead", Vector3(0.0, 1.52, 0.42))
	out.setup(brow + (SEED_POSE[0] as Vector3), SEED_POSE[1], SEED_POSE[2], SEED_POSE[3], SEED_POSE[4])
	if g.awaken_at < 0.0:
		return out
	var c := Motion.progress(g.awaken_at + CRANE_DELAY, t, CRANE_BACK)
	var pull := Motion.eased(clampf(c / CRANE_PULL, 0.0, 1.0))
	var tilt := Motion.eased(clampf((c - CRANE_TILT_FROM) / (1.0 - CRANE_TILT_FROM), 0.0, 1.0))
	_move_split(out, PORTRAIT_POSE, tilt, pull)
	if g.hands_at < 0.0:
		return out
	_move(out, HERO_POSE, Motion.smooth(g.hands_at, t, HERO_DOLLY_DUR))
	if g.layer_at(0) < 0.0:
		return out
	_move(out, CRADLE_POSE, Motion.smooth(g.layer_at(0), t, CRADLE_DUR))
	if g.moon_at(0) < 0.0:
		return out
	_move(out, RISE_POSE, Motion.smooth(g.moon_at(0), t, RISE_DUR))
	if g.stable_at < 0.0:
		return out
	_move(out, RECEDE_POSE, Motion.smooth(g.stable_at, t, RECEDE_DUR))
	return out


## Exposure trim of the cinematic path at (g, t) (1 = the mode's exposure): TRIM_RISE while the
## camera rises over the belt, back to 1 as it recedes at planet.stable. Continuous.
static func cue_trim(g: GenesisState, t: float) -> float:
	if g.moon_at(0) < 0.0:
		return 1.0
	var k := Motion.smooth(g.moon_at(0), t, RISE_DUR)
	if g.stable_at >= 0.0:
		k *= 1.0 - Motion.smooth(g.stable_at, t, RECEDE_DUR)
	return lerpf(1.0, TRIM_RISE, k)


## Like _move, with the target, yaw, pitch and lens moved by `k` and the distance by `k_distance`.
static func _move_split(out: CameraShots.Shot, pose: Array, k: float, k_distance: float) -> void:
	out.distance = lerpf(out.distance, pose[3], k_distance)
	if k <= 0.0:
		return
	out.target = out.target.lerp(pose[0], k)
	out.yaw = lerpf(out.yaw, pose[1], k)
	out.pitch = lerpf(out.pitch, pose[2], k)
	out.fov = lerpf(out.fov, pose[4], k)


## Moves `out` towards `pose` ([target, yaw, pitch, distance, fov]) by `k` (in place, no allocation).
static func _move(out: CameraShots.Shot, pose: Array, k: float) -> void:
	if k <= 0.0:
		return
	out.target = out.target.lerp(pose[0], k)
	out.yaw = lerpf(out.yaw, pose[1], k)
	out.pitch = lerpf(out.pitch, pose[2], k)
	out.distance = lerpf(out.distance, pose[3], k)
	out.fov = lerpf(out.fov, pose[4], k)


const MODE_IDS: Array[StringName] = [&"g_mode_0", &"g_mode_1", &"g_mode_2"]


## Desired shot: the cue when cinematic in FORGE, else the mode shot. Returns the shot id. Clamped.
static func desired(mode: int, cinematic: bool, g: GenesisState, t: float, m: float, out: CameraShots.Shot) -> StringName:
	var id: StringName
	if cinematic and mode == SessionState.Mode.FORGE:
		id = cue(g, t, m, out)
	else:
		mode_shot(mode, out)
		id = MODE_IDS[clampi(mode, 0, MODE_IDS.size() - 1)]
	clamp_shot(out, mode)
	return id


# --- Limits ------------------------------------------------------------------------------------------

static func clamp_shot(s: CameraShots.Shot, mode: int) -> CameraShots.Shot:
	var lim: Vector2 = DISTANCE_LIMITS[clampi(mode, 0, DISTANCE_LIMITS.size() - 1)]
	s.distance = clampf(s.distance, lim.x, lim.y)
	return clamp_rig(s)


## Pitch range, target within FLY_RADIUS, camera above MIN_CAMERA_Y (pitch raised when needed).
static func clamp_rig(s: CameraShots.Shot) -> CameraShots.Shot:
	s.pitch = clampf(s.pitch, PITCH_MIN, PITCH_MAX)
	var flat := Vector2(s.target.x, s.target.z)
	if flat.length() > FLY_RADIUS:
		flat = flat.normalized() * FLY_RADIUS
		s.target.x = flat.x
		s.target.z = flat.y
	s.target.y = clampf(s.target.y, MIN_CAMERA_Y + 0.5, 40.0)
	if s.target.y + sin(s.pitch) * s.distance < MIN_CAMERA_Y:
		s.pitch = asin(clampf((MIN_CAMERA_Y - s.target.y) / s.distance, -1.0, 1.0))
	return s


# --- Focus --------------------------------------------------------------------------------------------

## Every GENESIS body is in reach (within FLY_RADIUS of MIKU's axis).
static func focus_reachable(centre: Vector3) -> bool:
	return Vector2(centre.x, centre.z).length() <= FLY_RADIUS + 1e-3


## Frames `bounds` keeping the mode's lens and the current yaw (the camera goes to the body instead
## of swinging around it), pitch kept inside FOCUS_PITCH, filling FOCUS_FILL of the frame.
static func focus_shot(mode: int, bounds: AABB, current: CameraShots.Shot, aspect: float,
		out: CameraShots.Shot) -> CameraShots.Shot:
	var yaw := current.yaw
	var pitch := clampf(current.pitch, FOCUS_PITCH.x, FOCUS_PITCH.y)
	mode_shot(mode, out)
	out.target = bounds.get_center()
	out.yaw = yaw
	out.pitch = pitch
	out.offset = 0.0
	out.distance = CameraShots.fit_distance(bounds, pitch, out.fov, 0.0, aspect) * CameraShots.FOCUS_FILL / FOCUS_FILL
	return clamp_shot(out, mode)


# --- Style frames ---------------------------------------------------------------------------------------

## Camera position of a rig pose (for style frame dictionaries).
static func rig_position(target: Vector3, yaw: float, pitch: float, distance: float) -> Vector3:
	var c := cos(pitch)
	return target + Vector3(sin(yaw) * c, sin(pitch), cos(yaw) * c) * distance


## The GENESIS style frames (StyleFrames pose dictionaries, ≥ 6): hero, portraits of MIKU, hands
## and planet, planet detail, the threads, the system, the silhouette against the warm core.
static func style_frame_poses() -> Array[Dictionary]:
	var heart := GenesisLayout.miku_heart()
	var brow := GenesisLayout.miku_point("forehead", Vector3(0, 1.52, 0.42))
	var planet := GenesisLayout.PLANET_CENTER
	var out: Array[Dictionary] = []
	out.append(_pose("sf_01_hero", 55.0, SessionState.Mode.FORGE,
		rig_position(FORGE_TARGET, FORGE_YAW + 0.02, FORGE_PITCH, FORGE_DISTANCE - 1.0), FORGE_TARGET, FORGE_FOV))
	# Statuary distance, a little from below: head, shoulders and the hair mass rising behind against
	# the sky (never an extreme close; the older worlds' orbits stay under the frame).
	out.append(_pose("sf_02_portrait", 12.0, SessionState.Mode.FORGE,
		brow + Vector3(3.0, -2.2, 6.4), brow + Vector3(-0.5, -0.35, -0.6), 31.0))
	# The cradle station of the cinematic path: low, looking up — the molten world between the hands,
	# MIKU whole above it against the warm core.
	var cp: Vector3 = CRADLE_POSE[0]
	out.append(_pose("sf_03_cradle", 25.0, SessionState.Mode.FORGE,
		rig_position(cp, CRADLE_POSE[1], CRADLE_POSE[2], CRADLE_POSE[3]), cp, CRADLE_POSE[4]))
	out.append(_pose("sf_04_world_detail", 47.5, SessionState.Mode.FORGE,
		planet + Vector3(3.2, 1.6, 5.4), planet + Vector3(-0.2, 0.1, 0.0), 36.0))
	out.append(_pose("sf_05_threads", 53.0, SessionState.Mode.OBSERVATORY,
		rig_position(OBSERVATORY_TARGET, OBSERVATORY_YAW, OBSERVATORY_PITCH, OBSERVATORY_DISTANCE - 2.0),
		OBSERVATORY_TARGET, OBSERVATORY_FOV))
	# The system, closer than the UNIVERSE mode shot: the belt, both older worlds and their threads.
	out.append(_pose("sf_06_system", 55.0, SessionState.Mode.UNIVERSE,
		rig_position(Vector3(0.0, 3.0, 2.0), UNIVERSE_YAW - 0.2, 0.34, 50.0), Vector3(0.0, 3.0, 2.0), 42.0))
	# Whole figure, slightly low, looking along the sky's warm direction: MIKU against the warm core (the
	# contraluz), her hair opening into it — never cut at the waist.
	out.append(_pose("sf_07_contraluz", 55.0, SessionState.Mode.FORGE,
		heart + Vector3(-2.2, -2.8, 16.5), heart + Vector3(0.0, -1.3, -0.5), 36.0))
	out.append(_pose("sf_08_open", 55.0, SessionState.Mode.FORGE,
		rig_position(Vector3(0.0, 4.2, 0.5), -0.42, 0.04, 46.0), Vector3(0.0, 4.2, 0.5), 40.0))
	return out


static func _pose(n: String, t: float, mode: int, pos: Vector3, target: Vector3, fov: float) -> Dictionary:
	return {"name": n, "time": t, "mode": mode, "position": pos, "target": target, "fov": fov}
