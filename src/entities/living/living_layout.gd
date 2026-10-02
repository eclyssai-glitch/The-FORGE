class_name LivingLayout
extends RefCounted
## Stage of the living prototype (Loop 5). Owner: animator. Pure data.
## MIKU floats at the origin facing +Z (her left hand at +X; the sculpt's frame: head top ~1.75,
## hem ~-4.1). The work worlds (ids and names of LivingScript.WORLDS: VESPER left, CALYX centre,
## ORRIN right, as the default camera sees them) sit around her like a theatre seen from the
## front: CALYX low before her, at her working height (below her face, so it never hides her),
## VESPER at her right (screen left), ORRIN at her left (screen right). The layout is the
## animator's (LivingScript anchors are defaults; the interaction system reads sides from the
## camera).

const MIKU_POSITION := Vector3.ZERO
## Where the user is when nothing better is known (in front of her, at eye height): the camera
## position is used when there is one.
const USER_FALLBACK := Vector3(0.0, 1.4, 12.0)

## [id, centre, radius, seed]
const WORLDS: Array = [
	[&"world_vesper", Vector3(-4.3, 0.9, 1.3), 0.8, 2602],
	[&"world_calyx", Vector3(1.7, -1.55, 2.5), 1.0, 1301],
	[&"world_orrin", Vector3(4.4, 1.1, 1.1), 0.75, 3903],
]
## The world of the scripted work order (LivingScript.WORK_WORLD).
const DEFAULT_WORLD := &"world_calyx"

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
## (palm towards it). The hands hold the world from above and from its sides — an arch over it
## that opens away from MIKU — never between her and the world, never under it, so she, her
## hands and her work read together from the front. Returns [position, finger direction, palm].
static func work_place(center: Vector3, r: float, i: int, n: int, distance := 1.55) -> Array:
	var count := maxi(n, 1)
	var away := center - MIKU_POSITION
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 1e-6 else Vector3.FORWARD
	var lateral := Vector3.UP.cross(away).normalized()
	# Angles over the arch: -ARCH .. +ARCH around the top (0 = straight up).
	var arch := 1.25 if count > 1 else 0.0
	var a := lerpf(-arch, arch, float(i) / float(count - 1)) if count > 1 else 0.35
	var dir := (lateral * sin(a) + Vector3.UP * cos(a) * 0.85 + away * 0.45).normalized()
	var pos := center + dir * r * distance
	var palm := -dir
	# Fingers wrap over the world, pointing along the arch towards its far side.
	var fingers := (away * 0.8 - dir * 0.3 + lateral * -sin(a) * 0.3).normalized()
	return [pos, fingers, palm]
