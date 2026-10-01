class_name LivingLayout
extends RefCounted
## Stage of the living prototype (Loop 5). Owner: animator. Pure data.
## MIKU floats at the origin facing +Z (her left hand at +X; the sculpt's frame: head top ~1.75,
## hem ~-4.1). The work worlds sit in an arc in front of her at working height, the main one in
## front and to her left (screen right of a 3/4 view) so the camera can hold her and her work in
## one frame; the other two are the worlds the user can point at.

const MIKU_POSITION := Vector3.ZERO
## Where the user is when nothing better is known (in front of her, at eye height): the camera
## position is used when there is one.
const USER_FALLBACK := Vector3(0.0, 1.4, 12.0)

## [id, centre, radius, seed]
const WORLDS: Array = [
	[&"world_a", Vector3(2.3, -0.35, 3.1), 0.95, 1301],
	[&"world_b", Vector3(-3.5, 0.75, 2.7), 0.75, 2602],
	[&"world_c", Vector3(4.6, 1.85, 0.2), 0.7, 3903],
]
const DEFAULT_WORLD := &"world_a"

## Where summoned hands materialise around MIKU before they are sent (relative to her, model
## space; spread by index): high at her sides, like attendants of light.
const SUMMON_BASE := Vector3(1.9, 1.7, 1.2)
const SUMMON_SPREAD := Vector3(0.55, 0.45, 0.4)


static func world_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for w in WORLDS:
		out.append(w[0])
	return out


static func world_center(id: StringName) -> Vector3:
	for w in WORLDS:
		if w[0] == id:
			return w[1]
	return WORLDS[0][1]


static func world_radius(id: StringName) -> float:
	for w in WORLDS:
		if w[0] == id:
			return w[2]
	return WORLDS[0][2]


## Point where hand `i` of a summon materialises (alternating sides, rising).
static func summon_point(i: int, toward_left: bool) -> Vector3:
	var sx := 1.0 if (toward_left if i % 2 == 0 else not toward_left) else -1.0
	var row := float(i / 2)
	return Vector3(sx * (SUMMON_BASE.x + row * SUMMON_SPREAD.x), SUMMON_BASE.y + row * SUMMON_SPREAD.y,
		SUMMON_BASE.z + row * SUMMON_SPREAD.z)


## Working place of hand `i` of `n` around a world of radius r at `center`, facing the world
## (palm towards it), on the side that faces MIKU and the camera first. Returns
## [position, finger direction, palm direction].
static func work_place(center: Vector3, r: float, i: int, n: int, distance := 1.55) -> Array:
	var count := maxi(n, 1)
	# Around the world in a ring tilted towards MIKU (at the origin): first hands on her side.
	var to_miku := (MIKU_POSITION - center)
	to_miku.y = 0.0
	to_miku = to_miku.normalized() if to_miku.length_squared() > 1e-6 else Vector3.BACK
	var base_ang := atan2(to_miku.x, to_miku.z)
	var spread := TAU / float(count) if count > 2 else 1.9
	var ang := base_ang + (float(i) - float(count - 1) * 0.5) * spread
	var lift := 0.35 if i % 2 == 0 else -0.25
	var dir := Vector3(sin(ang), lift, cos(ang)).normalized()
	var pos := center + dir * r * distance
	var palm := -dir
	# Fingers wrap around the world: tangent, slightly upward.
	var fingers := dir.cross(Vector3.UP).normalized()
	if fingers.length_squared() < 1e-6:
		fingers = Vector3.FORWARD
	if i % 2 == 1:
		fingers = -fingers
	fingers = (fingers + Vector3.UP * 0.35 - dir * 0.2).normalized()
	return [pos, fingers, palm]
