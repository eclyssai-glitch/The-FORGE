class_name RelationThreads
extends Node3D
## The relational threads (links of the vault graph, translated into astronomy). Owner: animator.
## One thread per GenesisScript.LINKS entry: a fibre of light (RelationThread crossed ribbons +
## a duplicate of MaterialLibrary.relation_thread()) that leaves MIKU's hair — from a point inside
## the rising plume, where the hair turns lilac — and arcs out to the body it links, or runs
## between two bodies (planet -> moons / ring, and the backlink from NAUVE-2 back to the new world).
## At links.woven the threads are spun one after the other from their source
## (GenesisChoreography.link): the mesh is the first part [0, w] of the final arc (exact Bézier
## subdivision), so the fibre grows along its own path with tapered ends. Once woven, a gold
## pulse (a backlink forming) travels source -> target every few seconds with easing and spacing
## — a pair of soft motes riding the arc (ambient, MotionClock: the woven graph keeps breathing
## after the session completes). Colour at the target: GOLD for the forming world, ICE for moons,
## pale gold for the ring, lilac-rose for the belt, dusk rose for distant worlds.
## The material's own `woven` front and `pulse` are held off (woven = 1, pulse < 0): both raise a
## negative base to a power (NaN on llvmpipe and several drivers) — reported to the art-director.
## Endpoints that orbit are followed: planet -> moon threads live in a replica of the moon's orbit
## pivot (static mesh, rotated with the moon); threads to the slowly orbiting distant worlds are
## rebuilt only when an end moved more than REBUILD_STEP.
## Entity `relations`: the root is the visual root (group, hidden until links.woven, label_anchor
## on the MIKU -> planet thread), picked through capsules along the MIKU -> planet thread.

const ENTITY := &"relations"
## Thread ribbon width (MIKU's threads; body -> body threads are WIDTH_BODY, planet -> moon
## threads WIDTH_MOON: fine filaments, never rods), segments, arc height (share of the chord).
const WIDTH := 0.05
const WIDTH_BODY := 0.034
const WIDTH_MOON := 0.022
const SEGMENTS := 40
const ARC := 0.16
## Threads end on the surface of the bodies they tie (the limb that faces the other end), never at
## their centre: radius × LIMB_CLEARANCE from the centre (a hair outside the surface).
const LIMB_CLEARANCE := 1.03
## Stable wave (GenesisChoreography.stable_wave): the single pulse is larger and brighter than the
## ambient ones and lights each thread while it runs through it.
const WAVE_CORE := 0.2
const WAVE_HALO := 0.9
const WAVE_HDR := 2.4
const WAVE_GLOW := 1.4
## Rebuild a moving thread when one end moved farther than this (units); a growing thread when its
## weave advanced more than WEAVE_STEP.
const REBUILD_STEP := 0.06
const WEAVE_STEP := 0.004
## Pulses: travel time (s), period range (s), mote sizes (core, halo), HDR of the core.
const PULSE_TRAVEL := 2.2
const PULSE_PERIODS := Vector2(7.5, 12.5)
const PULSE_CORE := 0.09
const PULSE_HALO := 0.42
const PULSE_HDR := 1.7
const INTENSITY := 0.55
## MIKU's own threads (the hair become the graph) are drawn a little bolder (relation_thread line_px).
const HAIR_LINE_PX := 2.1
## MIKU's own threads (GenesisScript.LINKS indices whose source is MIKU), in hair-strand order.
const MIKU_LINKS: Array[int] = [0, 4, 5, 6]
## The thread starts this far (share of the strand's control points) before the strand's tip and
## overlaps it, leaving along the strand's own direction (no kink, no pinch at the junction).
const HAIR_OVERLAP := 0.06
## A thread leaving the hair keeps the strand's direction as long as it heads to its body within
## this angle (cosine; beyond it the start direction is turned towards the body).
const HAIR_TANGENT_MIN_COS := 0.55
## MIKU floats (and lifts her head at the climax): her threads are rebuilt when their hair end
## moved farther than this (units).
const HAIR_REBUILD_STEP := 0.015
## Bulge direction per link (world); default up.
const BULGE := {
	0: Vector3(-1.0, 0.1, 0.45),
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
var pulses: MoteCloud
var _mats: Array[ShaderMaterial] = []
## Per thread: 0 static, 1 lives in a moon pivot (local ends), 2 moving ends (rebuilt).
var _kinds := PackedInt32Array()
## Full-arc ends of each thread (world, or pivot-local for kind 1).
var _ends_a := PackedVector3Array()
var _ends_b := PackedVector3Array()
## Weave the mesh was built for (-1 = none).
var _built_w := PackedFloat32Array()
var _pivot_of: Array[Node3D] = []
var _periods := PackedFloat32Array()
var _hops := PackedInt32Array()
## Arc of each thread (height, bulge direction), recomputed with its ends.
var _heights := PackedFloat32Array()
var _ups := PackedVector3Array()
var _wave_hops := 1
var _intensity_written := PackedFloat32Array()
var _pick_body: StaticBody3D
var _shown := -1


func _ready() -> void:
	add_to_group(SessionState.entity_group(ENTITY))
	visible = false
	var n := GenesisScript.LINKS.size()
	_kinds.resize(n)
	_ends_a.resize(n)
	_ends_b.resize(n)
	_built_w.resize(n)
	_built_w.fill(-1.0)
	_periods.resize(n)
	_pivot_of.resize(n)
	_hops.resize(n)
	_intensity_written.resize(n)
	_intensity_written.fill(-1.0)
	_heights.resize(n)
	_ups.resize(n)
	_wave_hops = GenesisChoreography.wave_hops()
	var m := MotionClock.now()
	for i in n:
		_hops[i] = GenesisChoreography.link_hop(i)
		_periods[i] = lerpf(PULSE_PERIODS.x, PULSE_PERIODS.y, Motion.hash01(i * 17 + 4))
		var mat := MaterialLibrary.relation_thread().duplicate() as ShaderMaterial
		mat.set_shader_parameter("color_to", target_color(GenesisScript.LINKS[i][1]))
		mat.set_shader_parameter("intensity", INTENSITY)
		mat.set_shader_parameter("woven", 1.0)
		mat.set_shader_parameter("pulse", -1.0)
		if GenesisScript.LINKS[i][0] == &"miku":
			mat.set_shader_parameter("line_px", HAIR_LINE_PX)
		var mi := MeshInstance3D.new()
		mi.name = "Thread%d" % i
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.visible = false
		threads.append(mi)
		_mats.append(mat)
		var a: StringName = GenesisScript.LINKS[i][0]
		var b: StringName = GenesisScript.LINKS[i][1]
		if a == &"planet_forming" and (b == &"moon_0" or b == &"moon_1"):
			# Lives in a replica of the moon's orbit pivot: planet centre -> moon (local, static).
			var mi_idx := 0 if b == &"moon_0" else 1
			_kinds[i] = 1
			var frame := Node3D.new()
			frame.name = "MoonFrame%d" % mi_idx
			frame.position = GenesisLayout.PLANET_CENTER
			frame.rotation = GenesisLayout.MOON_TILTS[mi_idx]
			add_child(frame)
			var pivot := Node3D.new()
			pivot.name = "Pivot"
			pivot.set_meta(&"moon", mi_idx)
			frame.add_child(pivot)
			pivot.add_child(mi)
			_pivot_of[i] = pivot
			# From the world's limb to the moon's limb (along the pivot's +Z, towards the moon).
			_ends_a[i] = Vector3(0.0, 0.0, GenesisLayout.PLANET_RADIUS * LIMB_CLEARANCE)
			_ends_b[i] = Vector3(0.0, 0.0, GenesisLayout.MOON_ORBITS[mi_idx] - GenesisLayout.MOON_RADII[mi_idx] * LIMB_CLEARANCE)
		else:
			add_child(mi)
			_kinds[i] = 2 if moving(a) or moving(b) else 0
			_ends_a[i] = endpoint(i, true, m)
			_ends_b[i] = endpoint(i, false, m)
		_set_arc(i, m, 0.0)
	pulses = MoteCloud.new()
	pulses.name = "Pulses"
	pulses.setup(n * 2, Palette.GOLD.lerp(Palette.PEARL, 0.3), 1.0, Vector2(1.0, 3.0), false)
	pulses.visible = false
	add_child(pulses)
	set_meta(&"label_anchor", RelationThread.arc_point(_ends_a[0], _ends_b[0], _heights[0], 0.55, _ups[0]))
	set_meta(&"label_radius", 0.3)
	set_meta(CameraDirector.FOCUS_BOUNDS_META, AABB(Vector3(-5.0, -3.0, -3.0), Vector3(10.0, 15.0, 9.0)))
	_pick_body = _thread_pick_body(0)
	add_child(_pick_body)
	Simulation.world_rebuilt.connect(_on_rebuilt)
	_update()


func _process(_delta: float) -> void:
	_update()


func _on_rebuilt() -> void:
	_built_w.fill(-1.0)
	_update()


## True when the body orbits (its thread end moves with MotionClock).
static func moving(id: StringName) -> bool:
	return id == &"miku" or id == &"moon_0" or id == &"moon_1" or id == &"planet_far_0" or id == &"planet_far_1"


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


## World point where link `i` starts (`source`) or ends, at ambient time `m` (MIKU's head lift
## `lift` 0..1): on the limb of a round body (planet, moons, distant worlds) facing the other end;
## MIKU's end is on the tip of its hair strand, the ring's and the belt's on their circle.
static func endpoint(i: int, source: bool, m: float, lift := 0.0) -> Vector3:
	var id: StringName = GenesisScript.LINKS[i][0 if source else 1]
	var c := body_point(i, id, m, lift)
	var r := body_radius(id)
	if r <= 0.0:
		return c
	var other: StringName = GenesisScript.LINKS[i][1 if source else 0]
	var d := body_point(i, other, m, lift) - c
	return c + d.normalized() * r * LIMB_CLEARANCE if d.length() > 1e-4 else c


## Radius of a round body a thread ends on (0 for MIKU, the ring and the belt).
static func body_radius(id: StringName) -> float:
	match id:
		&"planet_forming":
			return GenesisLayout.PLANET_RADIUS
		&"moon_0":
			return GenesisLayout.MOON_RADII[0]
		&"moon_1":
			return GenesisLayout.MOON_RADII[1]
		&"planet_far_0":
			return GenesisLayout.FAR_RADII[0]
		&"planet_far_1":
			return GenesisLayout.FAR_RADII[1]
	return 0.0


## Ribbon width of link `i`.
static func width_of(i: int) -> float:
	var a: StringName = GenesisScript.LINKS[i][0]
	var b: StringName = GenesisScript.LINKS[i][1]
	if b == &"moon_0" or b == &"moon_1":
		return WIDTH_MOON
	return WIDTH if a == &"miku" else WIDTH_BODY


## Centre of body `id` as seen by link `i` (MIKU: where the thread leaves her hair strand).
static func body_point(i: int, id: StringName, m: float, lift := 0.0) -> Vector3:
	match id:
		&"miku":
			return Miku.figure_pose(m, lift) * hair_point(i)
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


## Object-space point (sculpture of MIKU) where link `i` leaves her hair: on its link strand,
## HAIR_OVERLAP before the strand's tip.
static func hair_point(i: int) -> Vector3:
	var root := GenesisLayout.anchor("miku_body", "hair_root", Miku.HAIR_ROOT_FALLBACK)
	var k := MIKU_LINKS.find(i)
	var curves := Miku.hair_link_curves()
	if k < 0 or k >= curves.size():
		return root + Vector3(0.0, 2.5, -1.5)
	return root + HairRibbons.curve_point(curves[k], 1.0 - HAIR_OVERLAP)


## Object-space direction of the hair strand of link `i` where its thread leaves it.
static func hair_tangent(i: int) -> Vector3:
	var k := MIKU_LINKS.find(i)
	var curves := Miku.hair_link_curves()
	if k < 0 or k >= curves.size():
		return Vector3.UP
	var c := curves[k]
	return (HairRibbons.curve_point(c, 1.0 - HAIR_OVERLAP * 0.5) - HairRibbons.curve_point(c, 1.0 - HAIR_OVERLAP * 1.5)).normalized()


## Arc a -> b whose start leaves along `tangent` (as close as HAIR_TANGENT_MIN_COS allows):
## returns [height, bulge direction] for RelationThread (quadratic arc, control point on the start
## tangent and above the chord's middle).
static func tangent_arc(a: Vector3, b: Vector3, tangent: Vector3) -> Array:
	var chord := b - a
	var chord_len := chord.length()
	if chord_len < 1e-4:
		return [0.0, Vector3.UP]
	var c_dir := chord / chord_len
	var tn := tangent.normalized()
	var cs := tn.dot(c_dir)
	if cs < HAIR_TANGENT_MIN_COS:
		var side := tn - c_dir * cs
		side = side.normalized() if side.length() > 1e-5 else RelationThread.bulge_dir(a, b, Vector3.UP)
		var sn := sqrt(1.0 - HAIR_TANGENT_MIN_COS * HAIR_TANGENT_MIN_COS)
		tn = c_dir * HAIR_TANGENT_MIN_COS + side * sn
		cs = HAIR_TANGENT_MIN_COS
	var ctrl := a + tn * (chord_len * 0.5 / cs)
	var off := ctrl - (a + b) * 0.5
	if off.length() < 1e-5:
		return [0.0, RelationThread.bulge_dir(a, b, Vector3.UP)]
	return [off.length() * 0.5, off.normalized()]


## Pulse position 0..1 along thread `i` at ambient time `m` (< 0 = no pulse): one eased travel of
## PULSE_TRAVEL seconds per period, only once the thread is fully woven.
static func pulse_at(i: int, woven: float, m: float, period: float) -> float:
	if woven < 0.999:
		return -1.0
	var phase := fposmod(m + Motion.hash01(i * 23 + 9) * period, period)
	if phase > PULSE_TRAVEL:
		return -1.0
	return Motion.eased(phase / PULSE_TRAVEL, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## Control point of the quadratic arc a -> b (RelationThread convention).
static func arc_control(a: Vector3, b: Vector3, height: float, up: Vector3) -> Vector3:
	return (a + b) * 0.5 + RelationThread.bulge_dir(a, b, up) * (2.0 * height)


## The first part [0, w] of the arc a -> b as (end, height, up) for RelationThread.build_*: de
## Casteljau gives the sub-arc's control point a + w (c - a); expressed as a bulge perpendicular
## to the new chord (the along-chord part of the offset is dropped — invisible while it grows).
static func partial_arc(a: Vector3, b: Vector3, height: float, up: Vector3, w: float) -> Array:
	var c := arc_control(a, b, height, up)
	var e := RelationThread.arc_point(a, b, height, w, up)
	var q := a + (c - a) * w
	var chord := e - a
	var off := q - (a + e) * 0.5
	var perp := off - chord * (off.dot(chord) / maxf(chord.length_squared(), 1e-9))
	var dir := perp.normalized() if perp.length() > 1e-5 else RelationThread.bulge_dir(a, e, up)
	return [e, perp.length() * 0.5, dir]


func _bulge(i: int) -> Vector3:
	return (BULGE.get(i, Vector3.UP) as Vector3).normalized()


## Arc of thread `i` for its current ends: MIKU's threads leave along their hair strand; the others
## bulge by ARC of the chord towards their BULGE direction.
func _set_arc(i: int, m: float, lift: float) -> void:
	var a := _ends_a[i]
	var b := _ends_b[i]
	if GenesisScript.LINKS[i][0] == &"miku":
		var tw := Miku.figure_pose(m, lift).basis * hair_tangent(i)
		var arc := tangent_arc(a, b, tw)
		_heights[i] = arc[0]
		_ups[i] = arc[1]
	else:
		_heights[i] = a.distance_to(b) * ARC
		_ups[i] = _bulge(i) if _kinds[i] != 1 else Vector3.UP


func _build(i: int, w: float) -> void:
	_built_w[i] = w
	var a := _ends_a[i]
	var b := _ends_b[i]
	var up := _ups[i]
	var h := _heights[i]
	if w >= 0.999:
		threads[i].mesh = RelationThread.build_crossed(a, b, h, width_of(i), SEGMENTS, up)
		return
	var p := partial_arc(a, b, h, up, w)
	threads[i].mesh = RelationThread.build_crossed(a, p[0], p[1], width_of(i), maxi(6, int(SEGMENTS * w)), p[2])


func _update() -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var m := MotionClock.now()
	var any := false
	var pulsing := false
	var wave := GenesisChoreography.stable_wave(g, t, _wave_hops)
	var lift := GenesisChoreography.head_lift(g, t)
	for i in threads.size():
		var w := GenesisChoreography.link(g, t, i)
		var mi := threads[i]
		if _kinds[i] == 1:
			var pv := _pivot_of[i]
			var idx := int(pv.get_meta(&"moon"))
			pv.rotation.y = TAU * GenesisLayout.orbit_phase(GenesisLayout.MOON_PHASES[idx], GenesisLayout.MOON_PERIODS[idx], m)
		if w <= 0.0:
			mi.visible = false
			_built_w[i] = -1.0
			pulses.hide_mote(i * 2)
			pulses.hide_mote(i * 2 + 1)
			continue
		any = true
		mi.visible = true
		var moved := false
		if _kinds[i] == 2:
			var ea := endpoint(i, true, m, lift)
			var eb := endpoint(i, false, m, lift)
			var step := HAIR_REBUILD_STEP if GenesisScript.LINKS[i][0] == &"miku" else REBUILD_STEP
			if ea.distance_to(_ends_a[i]) > step or eb.distance_to(_ends_b[i]) > REBUILD_STEP:
				_ends_a[i] = ea
				_ends_b[i] = eb
				_set_arc(i, m, lift)
				moved = true
		if moved or _built_w[i] < 0.0 or absf(w - _built_w[i]) > WEAVE_STEP or (w >= 0.999 and _built_w[i] < 0.999):
			_build(i, w)
		# The single stable wave takes over the thread while it runs through it (the whole graph
		# answers the world that holds); otherwise the ambient pulse, a pair of motes on the arc.
		var wp := GenesisChoreography.wave_on_link(wave, _hops[i]) if w >= 0.999 else -1.0
		var lit := INTENSITY * (1.0 + WAVE_GLOW * sin(PI * clampf(wave - _hops[i], 0.0, 1.0))) if wp >= 0.0 else INTENSITY
		if not is_equal_approx(lit, _intensity_written[i]):
			_intensity_written[i] = lit
			_mats[i].set_shader_parameter("intensity", lit)
		var p := wp if wp >= 0.0 else pulse_at(i, w, m, _periods[i])
		if p < 0.0:
			pulses.hide_mote(i * 2)
			pulses.hide_mote(i * 2 + 1)
			continue
		pulsing = true
		var pos := RelationThread.arc_point(_ends_a[i], _ends_b[i], _heights[i], p, _ups[i])
		if _kinds[i] == 1:
			pos = to_local(_pivot_of[i].global_transform * pos)
		var env := sin(PI * p)
		var core := WAVE_CORE if wp >= 0.0 else PULSE_CORE
		var halo := WAVE_HALO if wp >= 0.0 else PULSE_HALO
		var hdr := WAVE_HDR if wp >= 0.0 else PULSE_HDR
		# The wave's pulse stays bright end to end (it hands over to the next hop).
		var a := maxf(env, 0.55) if wp >= 0.0 else env
		pulses.set_mote(i * 2, pos, core, Color(hdr, hdr, hdr, a))
		pulses.set_mote(i * 2 + 1, pos, halo, Color(1, 1, 1, 0.22 * a))
	pulses.visible = pulsing
	if pulsing:
		pulses.commit()
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
	var h := _heights[i]
	for k in PICK_SEGMENTS:
		var p0 := RelationThread.arc_point(a, b, h, float(k) / PICK_SEGMENTS, _ups[i])
		var p1 := RelationThread.arc_point(a, b, h, float(k + 1) / PICK_SEGMENTS, _ups[i])
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
