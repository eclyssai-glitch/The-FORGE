class_name GenesisLayout
extends RefCounted
## Composition of the GENESIS hero scene in world units. Owner: animator.
## Pure data + tiny helpers: every GENESIS module and the camera shots read positions from here,
## so the composition is tuned in one place (docs/ANIMATION.md, "GENESIS — composição").
## Sculpture anchors (MIKU's head, brow, hair root; the hands' palms and fingertips) are always
## read from the sculpt JSON next to the mesh (assets/meshes/<name>.json): the sculptures are
## refined in parallel and their anchors may move a little.
##
## Axes: +Y up, MIKU faces +Z (towards the hero camera); the warm nebula core is behind her (−Z).
## Layout of docs/contracts/loop-04.md, refined with the style frames: MIKU is larger (≈ 7.4 u,
## her figure must lead the giant hands) and the new world with its hands sits below and in front
## of her hem — a vertical composition: hair (out of frame) -> halo and face (upper third) -> gown
## pouring its dust down -> the world held between the hands (lower third). In front of her torso
## the hands hid the figure.

const MESH_DIR := "res://assets/meshes/"

# --- MIKU ---------------------------------------------------------------------------------------
## World position of the sculpture's origin (the waist centre) and its uniform scale.
const MIKU_ORIGIN := Vector3(0.0, 6.9, -0.6)
const MIKU_SCALE := 1.2
## Slight turn towards the hero camera's left: a three-quarter hint reads the figure as volume.
const MIKU_YAW := 0.1
## Forward lean (rad, around X): the head inclines towards the creation below.
const MIKU_LEAN := 0.06

# --- Forming planet (subagent ILVARA-7) -------------------------------------------------------------
const PLANET_CENTER := Vector3(0.0, 0.1, 2.6)
## Final radius, and the radius of each formation step (seed core, mantle, crust, sky).
const PLANET_RADIUS := 1.6
const PLANET_STEP_RADII: Array[float] = [0.55, 1.2, 1.48, 1.6]
## Axial tilt of the forming planet and its ring plane.
const PLANET_TILT := Vector3(0.32, 0.0, -0.22)

# --- Auxiliary hands -----------------------------------------------------------------------------
## Rest pose of each hand (palm centre, Euler YXZ in radians, uniform scale).
## Left cradles from below (palm up, fingers under the planet), right shapes from above (palm
## down, fingers hovering over the planet, index slightly extended).
const HAND_LEFT_POS := Vector3(-1.55, -2.8, 2.9)
const HAND_LEFT_EULER := Vector3(0.3, 0.35, 0.22)
const HAND_RIGHT_POS := Vector3(2.3, 3.65, 2.9)
const HAND_RIGHT_EULER := Vector3(-0.12, -0.3, 0.26)
## Scale of both sculptures: wrist to middle fingertip ≈ 4.7 u, a hand ≈ 1.5× the final planet's
## diameter — monumental next to the world they hold, and still below MIKU in the hierarchy.
const HAND_SCALE := 0.72
## Where the hands wait before `hands.summoned`: this far below (and a little behind) their rest
## pose, inside the mist.
const HAND_SUMMON_OFFSET := Vector3(0.0, -7.5, -1.5)

# --- Orbital system ----------------------------------------------------------------------------------
## Documentation moons: orbit radius around the planet, moon radius, orbit tilt (Euler), period (s),
## start phase 0..1 (phase 0 = +Z of the orbit plane, towards the camera).
const MOON_ORBITS: Array[float] = [3.0, 4.2]
const MOON_RADII: Array[float] = [0.26, 0.2]
const MOON_TILTS: Array[Vector3] = [Vector3(0.22, 0.0, -0.12), Vector3(-0.16, 0.0, 0.2)]
const MOON_PERIODS: Array[float] = [74.0, 118.0]
const MOON_PHASES: Array[float] = [0.18, 0.62]
## Skill ring around the planet (inner/outer radius).
const RING_INNER := 2.2
const RING_OUTER := 2.9
## Memory belt around MIKU (centre = her heart height), radii, thickness, tilt, rocks, period.
## Tilted steeply (front side high, back side low) so that the hero camera — outside the belt
## radius — never looks through rocks: the belt reads as a tilted ring that passes behind the new
## world and rises out of frame over the camera.
const BELT_CENTER := Vector3(0.0, 6.6, -0.6)
const BELT_INNER := 16.0
const BELT_OUTER := 19.0
const BELT_THICKNESS := 0.9
const BELT_TILT := Vector3(-0.42, 0.0, 0.1)
const BELT_ROCKS := 900
const BELT_PERIOD := 900.0
## Distant worlds (older subagents, already formed): orbit radius around MIKU, planet radius,
## orbit tilt, period (s), start phase, their own small moon (orbit radius, moon radius, period).
## Their orbits lie beyond the hero camera (≈ 22 u from MIKU): from FORGE they are either behind
## her, far and small, or outside the frame — discreet; UNIVERSE sees the whole system.
const FAR_ORBITS: Array[float] = [30.0, 42.0]
const FAR_RADII: Array[float] = [1.3, 1.8]
const FAR_TILTS: Array[Vector3] = [Vector3(0.1, 0.0, -0.06), Vector3(-0.05, 0.0, 0.08)]
const FAR_PERIODS: Array[float] = [900.0, 1500.0]
const FAR_PHASES: Array[float] = [0.36, 0.58]
const FAR_MOON_ORBITS: Array[float] = [2.6, 3.4]
const FAR_MOON_RADII: Array[float] = [0.26, 0.32]
const FAR_MOON_PERIODS: Array[float] = [48.0, 66.0]
## Centre of the distant orbits (a little below MIKU's heart).
const FAR_CENTER := Vector3(0.0, 5.2, -0.6)

static var _anchor_cache: Dictionary = {}


## Anchors of a sculpture (`miku_body`, `hand_left`, `hand_right`) as {name: Vector3|float}, read
## once from the JSON next to the mesh. Empty when the file is missing or unreadable.
static func anchors(mesh_name: String) -> Dictionary:
	if _anchor_cache.has(mesh_name):
		return _anchor_cache[mesh_name]
	var out := {}
	var path := MESH_DIR + mesh_name + ".json"
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and (data as Dictionary).get("anchors") is Dictionary:
			var a: Dictionary = data["anchors"]
			for k: String in a:
				var v: Variant = a[k]
				if v is Array and (v as Array).size() == 3:
					out[k] = Vector3(float(v[0]), float(v[1]), float(v[2]))
				elif v is float or v is int:
					out[k] = float(v)
		if data is Dictionary and (data as Dictionary).get("bounds") is Dictionary:
			var b: Dictionary = data["bounds"]
			if b.get("min") is Array and b.get("max") is Array:
				var mn := Vector3(float(b["min"][0]), float(b["min"][1]), float(b["min"][2]))
				var mx := Vector3(float(b["max"][0]), float(b["max"][1]), float(b["max"][2]))
				out["bounds"] = AABB(mn, mx - mn)
	_anchor_cache[mesh_name] = out
	return out


## Anchor `key` of a sculpture as a Vector3, or `fallback` when absent.
static func anchor(mesh_name: String, key: String, fallback := Vector3.ZERO) -> Vector3:
	var v: Variant = anchors(mesh_name).get(key)
	return v if v is Vector3 else fallback


## Local AABB of a sculpture from its JSON bounds (`fallback` when absent).
static func bounds(mesh_name: String, fallback := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))) -> AABB:
	var v: Variant = anchors(mesh_name).get("bounds")
	return v if v is AABB else fallback


## World transform of MIKU's sculpture (origin = waist).
static func miku_transform() -> Transform3D:
	var b := Basis.from_euler(Vector3(MIKU_LEAN, MIKU_YAW, 0.0)).scaled(Vector3.ONE * MIKU_SCALE)
	return Transform3D(b, MIKU_ORIGIN)


## World position of a MIKU anchor (object space of the sculpture -> world).
static func miku_point(key: String, fallback := Vector3.ZERO) -> Vector3:
	return miku_transform() * anchor("miku_body", key, fallback)


## MIKU's heart (chest anchor) in world space: her audio anchor and the camera's subject.
static func miku_heart() -> Vector3:
	return miku_point("chest", Vector3(0.0, 0.6, 0.2))


## Rest transform of a hand (`left` true for the left hand).
static func hand_rest(left: bool) -> Transform3D:
	var e := HAND_LEFT_EULER if left else HAND_RIGHT_EULER
	var p := HAND_LEFT_POS if left else HAND_RIGHT_POS
	return Transform3D(Basis.from_euler(e).scaled(Vector3.ONE * HAND_SCALE), p)


## Point on an orbit of radius `r` in a plane tilted by `tilt` (Euler) around `centre`, at phase
## 0..1 (phase 0 = +Z of the plane, turning towards +X, as OrbitLine.point).
static func orbit_point(centre: Vector3, r: float, tilt: Vector3, phase: float) -> Vector3:
	return centre + Basis.from_euler(tilt) * OrbitLine.point(r, r, phase)


## Phase 0..1 of a body on its orbit at ambient time `motion_t` (seconds).
static func orbit_phase(start: float, period: float, motion_t: float) -> float:
	return fposmod(start + motion_t / maxf(period, 1e-3), 1.0)


## World centre of documentation moon `i` at ambient time `motion_t`.
static func moon_position(i: int, motion_t: float) -> Vector3:
	var ph := orbit_phase(MOON_PHASES[i], MOON_PERIODS[i], motion_t)
	return orbit_point(PLANET_CENTER, MOON_ORBITS[i], MOON_TILTS[i], ph)


## World centre of distant planet `i` at ambient time `motion_t`.
static func far_position(i: int, motion_t: float) -> Vector3:
	var ph := orbit_phase(FAR_PHASES[i], FAR_PERIODS[i], motion_t)
	return orbit_point(FAR_CENTER, FAR_ORBITS[i], FAR_TILTS[i], ph)
