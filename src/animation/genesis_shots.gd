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
const FORGE_TARGET := Vector3(0.0, 3.85, 1.0)
const FORGE_YAW := 0.06
const FORGE_PITCH := -0.06
const FORGE_DISTANCE := 23.0
const FORGE_FOV := 36.5
const UNIVERSE_TARGET := Vector3(0.0, 3.5, -0.5)
const UNIVERSE_YAW := 0.52
const UNIVERSE_PITCH := 0.42
const UNIVERSE_DISTANCE := 68.0
const UNIVERSE_FOV := 44.0
const OBSERVATORY_TARGET := Vector3(0.0, 4.2, 1.2)
const OBSERVATORY_YAW := -0.78
const OBSERVATORY_PITCH := 0.55
const OBSERVATORY_DISTANCE := 32.0
const OBSERVATORY_FOV := 40.0

# --- Cinematic cues (FORGE) ---------------------------------------------------------------------
const CUE_PORTRAIT := &"cue_g_portrait"
const CUE_HERO := &"cue_g_hero"
const CUE_ORBITS := &"cue_g_orbits"
const CUE_BELT := &"cue_g_belt"
const CUE_THREADS := &"cue_g_threads"
const CUE_STABLE := &"cue_g_stable"
## Ambient sway of every cue (rad; periods s).
const SWAY_YAW := 0.018
const SWAY_PITCH := 0.008
const SWAY_PERIODS := Vector2(37.0, 53.0)
## Slow dolly while the world forms (rad per sim second) and the final push-in (units per s).
const HERO_DOLLY := 0.0055
const STABLE_PUSH := 0.12
const STABLE_PUSH_MAX := 2.0

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
	if g.hands_at >= 0.0:
		return CUE_HERO
	return CUE_PORTRAIT


## Writes the cue shot for (g, t) into `out` (ambient sway from `m`, MotionClock seconds) and
## returns its id.
static func cue(g: GenesisState, t: float, m: float, out: CameraShots.Shot) -> StringName:
	var id := cue_id(g)
	match id:
		CUE_PORTRAIT:
			# Close on MIKU, slowly craning down and back as she wakes (her face, halo, seed).
			var k := Motion.eased(clampf(t / 8.0, 0.0, 1.0))
			out.setup(Vector3(0.0, lerpf(7.9, 6.6, k), -0.3), lerpf(0.16, 0.1, k), lerpf(-0.03, -0.08, k),
				lerpf(9.0, 14.0, k), 36.0)
		CUE_HERO:
			# The hero composition, with a slow dolly to the side while the world forms.
			var s := maxf(t - g.hands_at, 0.0)
			out.setup(FORGE_TARGET, FORGE_YAW - 0.1 + HERO_DOLLY * s, FORGE_PITCH, FORGE_DISTANCE + 0.5, FORGE_FOV)
		CUE_ORBITS:
			# Higher and wider: the moons and the ring around the new world.
			var s := maxf(t - g.moon_at(0), 0.0)
			out.setup(Vector3(0.0, 3.0, 1.6), 0.32 + HERO_DOLLY * s, 0.14, 24.0, 38.0)
		CUE_BELT:
			# Out beside the belt: its rocks drift through the foreground, MIKU beyond them.
			var s := maxf(t - g.belt_at, 0.0)
			out.setup(Vector3(0.0, 5.0, -0.4), 0.75 + 0.006 * s, 0.16, 27.0, 40.0)
		CUE_THREADS:
			# Three-quarter, raised: the threads leave the hair for every body.
			var s := maxf(t - g.links_at, 0.0)
			out.setup(Vector3(0.0, 3.6, 0.5), -0.62 + 0.004 * s, 0.28, 30.0, 40.0)
		_:
			# The world holds: back to the hero composition, a slow push-in.
			var s := maxf(t - g.stable_at, 0.0)
			out.setup(FORGE_TARGET, FORGE_YAW + 0.02, FORGE_PITCH, FORGE_DISTANCE - minf(STABLE_PUSH * s, STABLE_PUSH_MAX),
				FORGE_FOV)
	out.yaw += SWAY_YAW * sin(TAU * m / SWAY_PERIODS.x)
	out.pitch += SWAY_PITCH * sin(TAU * m / SWAY_PERIODS.y + 1.3)
	return id


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
		brow + Vector3(2.6, -1.7, 4.4), brow + Vector3(-0.3, 0.1, -0.6), 34.0))
	out.append(_pose("sf_03_cradle", 25.0, SessionState.Mode.FORGE,
		planet + Vector3(-4.6, -0.9, 8.8), planet + Vector3(0.4, 0.9, 0.0), 40.0))
	out.append(_pose("sf_04_world_detail", 47.5, SessionState.Mode.FORGE,
		planet + Vector3(3.2, 1.6, 5.4), planet + Vector3(-0.2, 0.1, 0.0), 36.0))
	out.append(_pose("sf_05_threads", 53.0, SessionState.Mode.OBSERVATORY,
		rig_position(OBSERVATORY_TARGET, OBSERVATORY_YAW, OBSERVATORY_PITCH, OBSERVATORY_DISTANCE - 4.0),
		OBSERVATORY_TARGET, OBSERVATORY_FOV))
	out.append(_pose("sf_06_system", 55.0, SessionState.Mode.UNIVERSE,
		rig_position(UNIVERSE_TARGET, UNIVERSE_YAW, UNIVERSE_PITCH, UNIVERSE_DISTANCE), UNIVERSE_TARGET, UNIVERSE_FOV))
	out.append(_pose("sf_07_silhouette", 55.0, SessionState.Mode.FORGE,
		heart + Vector3(-9.5, -2.2, -5.5), heart + Vector3(0.0, 0.6, 0.0), 38.0))
	out.append(_pose("sf_08_open", 55.0, SessionState.Mode.FORGE,
		rig_position(Vector3(0.0, 4.2, 0.5), -0.42, 0.04, 46.0), Vector3(0.0, 4.2, 0.5), 40.0))
	return out


static func _pose(n: String, t: float, mode: int, pos: Vector3, target: Vector3, fov: float) -> Dictionary:
	return {"name": n, "time": t, "mode": mode, "position": pos, "target": target, "fov": fov}
