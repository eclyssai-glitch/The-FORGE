class_name RelationThreads
extends Node3D
## The relational threads (links of the vault graph, translated into astronomy). Owner: animator.
## One thread per GenesisScript.LINKS entry: a fibre of light (RelationThread crossed ribbons +
## a duplicate of MaterialLibrary.relation_thread()) that leaves MIKU's hair — from a point inside
## the rising plume, where the hair's lilac tips are — and arcs out to the body it links, or runs
## between two bodies (planet -> moons / ring, and the backlink from NAUVE-2 back to the new world).
## At links.woven the threads are spun one after the other from their source (`woven`,
## GenesisChoreography.link); once woven, a gold pulse (a backlink forming) travels source ->
## target every few seconds, with easing and spacing (ambient, MotionClock, so the woven graph
## keeps breathing after the session completes; `pulse` < 0 = no pulse). Colour at the target:
## GOLD for the forming world, ICE for moons, pale gold for the ring, lilac for the belt, dusk
## rose for distant worlds.
## Endpoints that orbit are followed: planet -> moon threads live in a replica of the moon's orbit
## pivot (static mesh, rotated with the moon); threads to the slowly orbiting distant worlds are
## rebuilt only when an end moved more than REBUILD_STEP (a few times per second at most).
## Entity `relations`: the root is the visual root (group, hidden until links.woven, label_anchor
## on the MIKU -> planet thread), picked through capsules along the MIKU -> planet thread.

const ENTITY := &"relations"
## Thread ribbon width, segments, arc height (share of the chord).
const WIDTH := 0.04
const SEGMENTS := 40
const ARC := 0.16
## Rebuild a moving thread when one end moved farther than this (units).
const REBUILD_STEP := 0.06
## Pulses: travel time (s), period range (s) and brightness of the thread body.
const PULSE_TRAVEL := 2.2
const PULSE_PERIODS := Vector2(7.5, 12.5)
const INTENSITY := 0.42
## Hair sources (MIKU object space, relative to the hair_root anchor), one per MIKU link index:
## points inside the rising plume, spread so each thread leaves the hair on its own side.
const HAIR_SOURCES := {
	0: Vector3(-1.1, 2.6, -1.2),
	4: Vector3(0.35, 3.6, -2.4),
	5: Vector3(0.9, 3.0, -1.6),
	6: Vector3(-1.6, 3.4, -2.0),
}
## Bulge direction per link (world); default up.
const BULGE := {
	0: Vector3(-1.0, 0.25, 0.35),
	4: Vector3(0.0, 1.0, -0.3),
	5: Vector3(1.0, 0.6, 0.0),
	6: Vector3(-1.0, 0.6, 0.0),
	7: Vector3(0.3, 1.0, 0.2),
}
## Where the threads meet the ring and the belt (phase on their circle).
const RING_PHASE := 0.13
const BELT_PHASE := 0.58
const PICK_RADIUS := 0.35
const PICK_SEGMENTS := 8

var threads: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
## Per thread: [kind, a, b] — kind 0 static, 1 moon pivot (index), 2 dynamic.
var _kinds: PackedInt32Array
var _ends_a := PackedVector3Array()
var _ends_b := PackedVector3Array()
var _moon_pivots: Array[Node3D] = []
var _periods := PackedFloat32Array()
var _woven_written := PackedFloat32Array()
var _pick_body: StaticBody3D
var _shown := -1


func _ready() -> void:
	add_to_group(SessionState.entity_group(ENTITY))
	visible = false
	var n := GenesisScript.LINKS.size()
	_kinds.resize(n)
	_ends_a.resize(n)
	_ends_b.resize(n)
	_woven_written.resize(n)
	_woven_written.fill(-1.0)
	_periods.resize(n)
	var m := MotionClock.now()
	for i in n:
		_periods[i] = lerpf(PULSE_PERIODS.x, PULSE_PERIODS.y, Motion.hash01(i * 17 + 4))
		var mat := MaterialLibrary.relation_thread().duplicate() as ShaderMaterial
		mat.set_shader_parameter("color_to", target_color(GenesisScript.LINKS[i][1]))
		mat.set_shader_parameter("intensity", INTENSITY)
		mat.set_shader_parameter("woven", 0.0)
		mat.set_shader_parameter("pulse", -1.0)
		var mi := MeshInstance3D.new()
		mi.name = "Thread%d" % i
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		threads.append(mi)
		_mats.append(mat)
		var a: StringName = GenesisScript.LINKS[i][0]
		var b: StringName = GenesisScript.LINKS[i][1]
		if a == &"planet_forming" and (b == &"moon_0" or b == &"moon_1"):
			# Lives in a replica of the moon's orbit pivot: planet centre -> moon, static mesh.
			var mi_idx := 0 if b == &"moon_0" else 1
			_kinds[i] = 1
			var frame := Node3D.new()
			frame.name = "MoonFrame%d" % mi_idx
			frame.position = GenesisLayout.PLANET_CENTER
			frame.rotation = GenesisLayout.MOON_TILTS[mi_idx]
			add_child(frame)
			var pivot := Node3D.new()
			pivot.name = "Pivot"
			frame.add_child(pivot)
			pivot.add_child(mi)
			_moon_pivots.append(pivot)
			var local_b := Vector3(0.0, 0.0, GenesisLayout.MOON_ORBITS[mi_idx])
			mi.mesh = RelationThread.build_crossed(Vector3.ZERO, local_b, local_b.length() * ARC, WIDTH, SEGMENTS, Vector3.UP)
		else:
			add_child(mi)
			var ea := endpoint(i, true, m)
			var eb := endpoint(i, false, m)
			_kinds[i] = 2 if moving(a) or moving(b) else 0
			_build(i, ea, eb)
	var mid := RelationThread.arc_point(_ends_a[0], _ends_b[0], _ends_a[0].distance_to(_ends_b[0]) * ARC, 0.55, _bulge(0))
	set_meta(&"label_anchor", mid)
	set_meta(&"label_radius", 0.3)
	set_meta(CameraDirector.FOCUS_BOUNDS_META, AABB(Vector3(-5.0, -1.5, -3.0), Vector3(10.0, 13.0, 10.0)))
	_pick_body = _thread_pick_body(0)
	add_child(_pick_body)
	Simulation.world_rebuilt.connect(_update)
	_update()


func _process(_delta: float) -> void:
	_update()


## True when the body orbits (its thread end moves with MotionClock).
static func moving(id: StringName) -> bool:
	return id == &"moon_0" or id == &"moon_1" or id == &"planet_far_0" or id == &"planet_far_1"


## Colour of a thread at its target (the target body's family).
static func target_color(id: StringName) -> Color:
	match id:
		&"planet_forming":
			return Palette.GOLD
		&"moon_0", &"moon_1":
			return Palette.ICE
		&"ring_skill":
			return Palette.GOLD.lerp(Palette.PEARL, 0.4)
		&"belt_memory":
			return Palette.LILAC.lerp(Palette.DUSK_ROSE, 0.4)
		&"planet_far_0", &"planet_far_1":
			return Palette.DUSK_ROSE
	return Palette.ICE


## World point where link `i` starts (`source`) or ends, at ambient time `m`.
static func endpoint(i: int, source: bool, m: float) -> Vector3:
	var id: StringName = GenesisScript.LINKS[i][0 if source else 1]
	match id:
		&"miku":
			var root := GenesisLayout.anchor("miku_body", "hair_root", Vector3(-0.08, 1.73, -0.11))
			var off: Vector3 = HAIR_SOURCES.get(i, Vector3(0.0, 2.5, -1.5))
			return GenesisLayout.miku_transform() * (root + off)
		&"planet_forming":
			return GenesisLayout.PLANET_CENTER
		&"moon_0":
			return GenesisLayout.moon_position(0, m)
		&"moon_1":
			return GenesisLayout.moon_position(1, m)
		&"ring_skill":
			var mid := (GenesisLayout.RING_INNER + GenesisLayout.RING_OUTER) * 0.5
			return GenesisLayout.orbit_point(GenesisLayout.PLANET_CENTER, mid, GenesisLayout.PLANET_TILT, RING_PHASE)
		&"belt_memory":
			var bm := (GenesisLayout.BELT_INNER + GenesisLayout.BELT_OUTER) * 0.5
			return GenesisLayout.orbit_point(GenesisLayout.BELT_CENTER, bm, GenesisLayout.BELT_TILT, BELT_PHASE)
		&"planet_far_0":
			return GenesisLayout.far_position(0, m)
		&"planet_far_1":
			return GenesisLayout.far_position(1, m)
	return Vector3.ZERO


## Pulse position 0..1 along thread `i` at ambient time `m` (< 0 = no pulse): one eased travel of
## PULSE_TRAVEL seconds per period, only once the thread is fully woven.
static func pulse_at(i: int, woven: float, m: float, period: float) -> float:
	if woven < 0.999:
		return -1.0
	var phase := fposmod(m + Motion.hash01(i * 23 + 9) * period, period)
	if phase > PULSE_TRAVEL:
		return -1.0
	return Motion.eased(phase / PULSE_TRAVEL, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


func _bulge(i: int) -> Vector3:
	return (BULGE.get(i, Vector3.UP) as Vector3).normalized()


func _build(i: int, a: Vector3, b: Vector3) -> void:
	_ends_a[i] = a
	_ends_b[i] = b
	threads[i].mesh = RelationThread.build_crossed(a, b, a.distance_to(b) * ARC, WIDTH, SEGMENTS, _bulge(i))


func _update() -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var m := MotionClock.now()
	var any := false
	var p := 0
	for i in threads.size():
		var w := GenesisChoreography.link(g, t, i)
		any = any or w > 0.0
		if not is_equal_approx(w, _woven_written[i]):
			_woven_written[i] = w
			_mats[i].set_shader_parameter("woven", w)
			threads[i].visible = w > 0.0
		match _kinds[i]:
			1:
				var mi_idx := 0 if GenesisScript.LINKS[i][1] == &"moon_0" else 1
				_moon_pivots[p].rotation.y = TAU * GenesisLayout.orbit_phase(GenesisLayout.MOON_PHASES[mi_idx],
					GenesisLayout.MOON_PERIODS[mi_idx], m)
				p += 1
			2:
				if w > 0.0:
					var ea := endpoint(i, true, m)
					var eb := endpoint(i, false, m)
					if ea.distance_to(_ends_a[i]) > REBUILD_STEP or eb.distance_to(_ends_b[i]) > REBUILD_STEP:
						_build(i, ea, eb)
		_mats[i].set_shader_parameter("pulse", pulse_at(i, w, m, _periods[i]))
	var shown := 1 if any else 0
	if shown != _shown:
		_shown = shown
		visible = any
		_pick_body.collision_layer = 2 if any else 0


## Capsules along thread `i` (a static one) for picking.
func _thread_pick_body(i: int) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "PickBody"
	sb.collision_layer = 0
	sb.collision_mask = 0
	sb.set_meta(&"entity_id", ENTITY)
	var a := _ends_a[i]
	var b := _ends_b[i]
	var h := a.distance_to(b) * ARC
	for k in PICK_SEGMENTS:
		var p0 := RelationThread.arc_point(a, b, h, float(k) / PICK_SEGMENTS, _bulge(i))
		var p1 := RelationThread.arc_point(a, b, h, float(k + 1) / PICK_SEGMENTS, _bulge(i))
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = PICK_RADIUS
		cap.height = p0.distance_to(p1) + PICK_RADIUS * 2.0
		cs.shape = cap
		var dir := (p1 - p0).normalized()
		var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
		cs.transform = Transform3D(Basis(side, dir, side.cross(dir)), (p0 + p1) * 0.5)
		sb.add_child(cs)
	return sb
