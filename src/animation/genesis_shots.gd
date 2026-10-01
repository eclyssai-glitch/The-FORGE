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
const FORGE_TARGET := Vector3(0.0, 4.6, 1.0)
const FORGE_YAW := 0.06
const FORGE_PITCH := -0.06
const FORGE_DISTANCE := 23.0
const FORGE_FOV := 36.5
const UNIVERSE_TARGET := Vector3(0.0, 19.0, -4.0)
const UNIVERSE_YAW := 0.2
const UNIVERSE_PITCH := 0.05
const UNIVERSE_DISTANCE := 80.0
const UNIVERSE_FOV := 46.0
const OBSERVATORY_TARGET := Vector3(0.0, 4.2, 1.2)
const OBSERVATORY_YAW := -0.78
const OBSERVATORY_PITCH := 0.55
const OBSERVATORY_DISTANCE := 32.0
const OBSERVATORY_FOV := 40.0

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
##     below the warm core) back and down to MIKU whole, as the seed's light reveals her.
##  2. Dolly back while the hands rise and the dust gathers: the world appears below her (hero).
##  3. Low dolly in to the cradle at the mantle: hands, the molten world, the hem pouring dust.
##  4. Rise at the moons: up and out over the ring and the belt to a high three-quarter view where
##     the threads leave her hair for every body.
##  5. Recede at planet.stable: the camera cranes back from the whole — the climax.
const SEED_POSE := [Vector3(0.0, -0.05, 0.12), -0.15, 0.3, 3.4, 30.0]
const CRANE_DELAY := 0.3
const CRANE_BACK := 4.7
const PORTRAIT_POSE := [Vector3(0.0, 7.1, -0.4), 0.08, -0.02, 16.5, 36.0]
const HERO_DOLLY_DUR := 13.5
const HERO_POSE := [Vector3(0.0, 4.6, 1.0), 0.0, -0.06, 23.5, 36.5]
const CRADLE_DUR := 13.0
const CRADLE_POSE := [Vector3(0.2, 0.8, 2.6), -0.45, -0.05, 12.5, 38.0]
const RISE_DUR := 16.0
const RISE_POSE := [Vector3(0.0, 5.4, 0.2), 0.4, 0.32, 33.0, 42.0]
const RECEDE_DUR := 3.0
const RECEDE_POSE := [Vector3(0.0, 5.2, 0.6), 0.3, 0.26, 40.0, 42.0]

# --- Focus --------------------------------------------------------------------------------------
const FOCUS_FILL := 0.55
const FOCUS_PITCH := Vector2(-0.15, 0.7)


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
	_move(out, PORTRAIT_POSE, Motion.smooth(g.awaken_at + CRANE_DELAY, t, CRANE_BACK))
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
	out.append(_pose("sf_02_portrait", 9.0, SessionState.Mode.FORGE,
		brow + Vector3(1.9, -1.2, 3.3), brow + Vector3(-0.25, 0.05, -0.5), 34.0))
	out.append(_pose("sf_03_cradle", 25.0, SessionState.Mode.FORGE,
		planet + Vector3(-4.6, -0.9, 8.8), planet + Vector3(0.4, 0.9, 0.0), 40.0))
	out.append(_pose("sf_04_world_detail", 47.5, SessionState.Mode.FORGE,
		planet + Vector3(3.2, 1.6, 5.4), planet + Vector3(-0.2, 0.1, 0.0), 36.0))
	out.append(_pose("sf_05_threads", 53.0, SessionState.Mode.OBSERVATORY,
		rig_position(OBSERVATORY_TARGET, OBSERVATORY_YAW, OBSERVATORY_PITCH, OBSERVATORY_DISTANCE - 4.0),
		OBSERVATORY_TARGET, OBSERVATORY_FOV))
	# The system, closer than the UNIVERSE mode shot: the belt, both older worlds and their threads.
	out.append(_pose("sf_06_system", 55.0, SessionState.Mode.UNIVERSE,
		rig_position(Vector3(0.0, 3.0, 2.0), UNIVERSE_YAW - 0.2, 0.34, 50.0), Vector3(0.0, 3.0, 2.0), 42.0))
	# Close and slightly low, looking along the sky's warm direction: MIKU cut out against the warm
	# core (the contraluz), her hair opening into it.
	out.append(_pose("sf_07_contraluz", 55.0, SessionState.Mode.FORGE,
		heart + Vector3(-1.2, -1.6, 9.0), heart + Vector3(0.0, 0.9, -0.5), 36.0))
	out.append(_pose("sf_08_open", 55.0, SessionState.Mode.FORGE,
		rig_position(Vector3(0.0, 4.2, 0.5), -0.42, 0.04, 46.0), Vector3(0.0, 4.2, 0.5), 40.0))
	return out


static func _pose(n: String, t: float, mode: int, pos: Vector3, target: Vector3, fov: float) -> Dictionary:
	return {"name": n, "time": t, "mode": mode, "position": pos, "target": target, "fov": fov}
