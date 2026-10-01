class_name AuxiliaryHands
extends Node3D
## The two auxiliary hands (docs/contracts/loop-04.md). Owner: animator.
## Night-stone sculptures (assets/meshes/hand_left|hand_right.obj, MaterialLibrary.hand_stone(),
## one duplicate per hand for its own kintsugi `veins`). Left cradles the new world from below
## (palm up), right shapes it from above (palm down). Poses: GenesisLayout.hand_rest.
##
## Narrative (GenesisChoreography): before hands.summoned they wait in the mist below (hidden);
## at hands.summoned they rise slowly and heavily, easing in and out and settling after a small
## overshoot, fading out of the mist on the way (never a pop). While the world forms
## (dust.gathered -> planet.stable) the kintsugi wakes; on each act of formation (seeded, each
## layer) the right hand presses down a little and tilts (it sculpts), the left lifts to cradle.
## Ambient (MotionClock): a slow, heavy breathing drift of each hand (different phases).
## The wrists dissolve into mist: a soft cloud of dim NEBULA/LILAC motes drifts around each
## forearm (the tapering forearm of the sculpture fades into it).
## Entities `hand_left`, `hand_right`: each hand pivot is its visual root (group, focus bounds of
## the hand without the forearm, label anchor at the knuckles), picked through a trimesh body of
## the sculpture (layer 2), disabled while the hands are in the mist. Audio anchor `hands` =
## a node between both palms.

const LEFT := &"hand_left"
const RIGHT := &"hand_right"
const HANDS: Array[StringName] = [&"hand_left", &"hand_right"]
const MESH_PATHS := {&"hand_left": "res://assets/meshes/hand_left.obj", &"hand_right": "res://assets/meshes/hand_right.obj"}

## Ambient drift (units / rad) and periods (s) — slow and heavy.
const DRIFT := 0.07
const DRIFT_TILT := 0.012
const DRIFT_PERIODS := Vector2(Palette.T_BREATH_SLOW * 1.3, Palette.T_BREATH_SLOW * 1.7)
## Sculpting: the right hand presses down (units, along -palm) and pitches (rad); the left lifts.
const PRESS_DEPTH := 0.2
const PRESS_TILT := 0.045
const CRADLE_LIFT := 0.1
## Working hands draw in slightly towards the planet (units).
const WORK_CLOSE := 0.1
## Mist around each forearm: motes, size, colour, alpha; the cloud spans from the wrist
## (MIST_FROM along the forearm) to its end.
const MIST_MOTES := 90
const MIST_SIZE := 1.25
const MIST_ALPHA := 0.075
const MIST_FROM := 0.4
## Dust shed by the forearm where the stone ends: fine motes born around the cut that drift away
## along the arm and sink, fading (ambient life cycle) — the stone dissolves into the mist, no
## cylindrical cut. Count, size, life (s), drift (units over a life), alpha.
const SHED_MOTES := 70
const SHED_SIZE := 0.07
const SHED_LIFE := 9.0
const SHED_DRIFT := 2.4
const SHED_ALPHA := 0.5
## Radius of the forearm at its end (sculpture units) when the JSON has no `forearm_radius`.
const SHED_RING := 0.7
## Hook for hand_stone's dissolve towards the forearm (art-director): when the shader declares
## these uniforms the hand writes the object-space origin (wrist centre), the unit axis towards the
## forearm end and the fade span (distances along the axis where the stone starts / ends fading).
const DISSOLVE_ORIGIN := &"dissolve_origin"
const DISSOLVE_AXIS := &"dissolve_axis"
const DISSOLVE_SPAN := &"dissolve_span"
## Share of wrist -> forearm end where the fade starts and ends (only used by the shader hook).
const DISSOLVE_FROM := 0.15
const DISSOLVE_TO := 0.95
## Release after planet.stable (GenesisChoreography.hands_release): each hand withdraws along its
## own direction (world units) and opens (rad) — the gesture of letting the world go.
const RELEASE_LEFT := Vector3(-0.9, -1.2, 0.25)
const RELEASE_RIGHT := Vector3(1.3, 0.35, -0.35)
const RELEASE_OPEN_LEFT := 0.22
const RELEASE_OPEN_RIGHT := -0.2
const SELECT_RATE := 6.0

var hands: Dictionary = {}
var pivots: Dictionary = {}
var anchor_node: Node3D

var _mats: Dictionary = {}
var _bodies: Dictionary = {}
var _mist: Dictionary = {}
var _mist_seed: Dictionary = {}
var _shed: Dictionary = {}
## Per hand: [wrist, forearm end, ring radius] in pivot space, and per-mote seeds.
var _shed_frame: Dictionary = {}
var _shed_seed: Dictionary = {}
var _select: Dictionary = {LEFT: 0.0, RIGHT: 0.0}
var _veins_written: Dictionary = {LEFT: -1.0, RIGHT: -1.0}
var _present := -1.0


func _ready() -> void:
	for id: StringName in HANDS:
		_build_hand(id)
	anchor_node = Node3D.new()
	anchor_node.name = "HandsAnchor"
	anchor_node.position = (GenesisLayout.HAND_LEFT_POS + GenesisLayout.HAND_RIGHT_POS) * 0.5
	anchor_node.set_meta(&"audio_anchor", &"hands")
	add_child(anchor_node)
	Simulation.world_rebuilt.connect(_update.bind(0.0))
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _build_hand(id: StringName) -> void:
	var left := id == LEFT
	var mesh_name := String(id)
	var pivot := Node3D.new()
	pivot.name = "HandLeft" if left else "HandRight"
	pivot.transform = GenesisLayout.hand_rest(left)
	pivot.add_to_group(SessionState.entity_group(id))
	# Focus on the hand itself (palm to fingertips), not on the whole forearm.
	var a := GenesisLayout.anchors(mesh_name)
	var hb := AABB(Vector3.ZERO, Vector3.ZERO)
	for k in ["palm_center", "wrist_center", "tip_thumb", "tip_index", "tip_middle", "tip_ring", "tip_little"]:
		if a.get(k) is Vector3:
			hb = hb.expand(a[k])
	hb = hb.grow(0.5)
	pivot.set_meta(CameraDirector.FOCUS_BOUNDS_META, hb)
	pivot.set_meta(&"label_anchor", GenesisLayout.anchor(mesh_name, "tip_middle", Vector3.ZERO) * 0.55)
	pivot.set_meta(&"label_radius", 2.2)
	add_child(pivot)
	pivots[id] = pivot

	var mi := MeshInstance3D.new()
	mi.name = "Stone"
	mi.mesh = load(MESH_PATHS[id]) as Mesh
	var mat := MaterialLibrary.hand_stone().duplicate() as ShaderMaterial
	mi.material_override = mat
	pivot.add_child(mi)
	hands[id] = mi
	_mats[id] = mat

	var sb := StaticBody3D.new()
	sb.name = "PickBody"
	sb.collision_layer = 2
	sb.collision_mask = 0
	sb.set_meta(&"entity_id", id)
	var shape := CollisionShape3D.new()
	shape.shape = mi.mesh.create_trimesh_shape() if mi.mesh else BoxShape3D.new()
	sb.add_child(shape)
	pivot.add_child(sb)
	_bodies[id] = sb

	# Mist around the forearm (pivot space: from the wrist towards the forearm end).
	var mist := MoteCloud.new()
	mist.name = "Mist"
	mist.setup(MIST_MOTES, Palette.NEBULA.lerp(Palette.LILAC, 0.35), MIST_SIZE, Vector2(2.0, 6.0), true,
		AABB(Vector3(-9, -4, -4), Vector3(18, 8, 8)))
	mist.min_visible = 30
	pivot.add_child(mist)
	_mist[id] = mist
	var wrist := GenesisLayout.anchor(mesh_name, "wrist_center", Vector3(-2.0 if left else 2.0, 0, 0))
	var arm_end := GenesisLayout.anchor(mesh_name, "forearm_end", Vector3(-5.4 if left else 5.3, 0, 0))
	var seeds := PackedVector3Array()
	var extra := PackedFloat32Array()
	for i in MIST_MOTES:
		var u := lerpf(MIST_FROM, 1.25, pow(Motion.hash01(i * 13 + (1 if left else 2)), 0.7))
		var ang := TAU * Motion.hash01(i * 29 + 5)
		var rad := 0.35 + 1.1 * Motion.hash01(i * 31 + 7) * u
		seeds.append(wrist.lerp(arm_end, u) + Vector3(0.0, cos(ang), sin(ang)) * rad)
		extra.append(Motion.hash01(i * 37 + 11))
	_mist_seed[id] = [seeds, extra]

	# Dust shed at the end of the stone.
	var shed := MoteCloud.new()
	shed.name = "Shed"
	shed.setup(SHED_MOTES, Palette.PEARL.lerp(Palette.LILAC, 0.45), SHED_SIZE, Vector2(1.0, 3.0), true,
		AABB(Vector3(-12, -8, -6), Vector3(24, 14, 12)))
	shed.min_visible = 20
	pivot.add_child(shed)
	_shed[id] = shed
	var fr: Variant = GenesisLayout.anchors(mesh_name).get("forearm_radius", SHED_RING)
	_shed_frame[id] = [wrist, arm_end, float(fr)]
	var sseeds := PackedVector3Array()
	for i in SHED_MOTES:
		sseeds.append(Vector3(Motion.hash01(i * 41 + (3 if left else 4)), Motion.hash01(i * 43 + 5), Motion.hash01(i * 47 + 6)))
	_shed_seed[id] = sseeds

	# Shader hook: the stone fades towards the forearm when hand_stone supports it.
	_set_if_declared(mat, DISSOLVE_ORIGIN, wrist)
	_set_if_declared(mat, DISSOLVE_AXIS, (arm_end - wrist).normalized())
	var span := wrist.distance_to(arm_end)
	_set_if_declared(mat, DISSOLVE_SPAN, Vector2(span * DISSOLVE_FROM, span * DISSOLVE_TO))


## Sets `uniform` on `mat` only when its shader declares it (forward-compatible material hooks).
static func _set_if_declared(mat: ShaderMaterial, uniform: StringName, value: Variant) -> bool:
	if mat == null or mat.shader == null:
		return false
	for u: Dictionary in mat.shader.get_shader_uniform_list():
		if StringName(u.get("name", "")) == uniform:
			mat.set_shader_parameter(uniform, value)
			return true
	return false


func _update(delta: float) -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var m := MotionClock.now()
	var rise := GenesisChoreography.hands_rise(g, t)
	var vis := GenesisChoreography.hands_visible(g, t)
	var work := GenesisChoreography.hands_work(g, t)
	var press := GenesisChoreography.sculpt_press(g, t)
	var release := GenesisChoreography.hands_release(g, t)
	var present := vis
	for id: StringName in HANDS:
		var left := id == LEFT
		var pivot: Node3D = pivots[id]
		var rest := GenesisLayout.hand_rest(left)
		var off := GenesisLayout.HAND_SUMMON_OFFSET * (1.0 - rise)
		var ph := TAU * m / (DRIFT_PERIODS.x if left else DRIFT_PERIODS.y) + (0.0 if left else 2.1)
		var drift := Vector3(0.3 * sin(ph * 0.7), sin(ph), 0.25 * cos(ph * 0.8)) * DRIFT * rise
		var palm_n := rest.basis.y.normalized() * (1.0 if left else -1.0) # palm normal (up for left, down for right)
		var towards := (GenesisLayout.PLANET_CENTER - rest.origin).normalized()
		var work_off := towards * WORK_CLOSE * work
		var tilt := Basis.IDENTITY
		if left:
			work_off += Vector3.UP * CRADLE_LIFT * press
		else:
			work_off += palm_n * PRESS_DEPTH * press
			tilt = Basis(rest.basis.z.normalized(), PRESS_TILT * press)
		var sway := Basis(Vector3.FORWARD, DRIFT_TILT * sin(ph * 0.9)) * Basis(Vector3.RIGHT, DRIFT_TILT * 0.7 * cos(ph * 0.6))
		if release > 0.0:
			# Letting go: withdraw along the hand's own direction, the palm opening as it leaves.
			work_off += (RELEASE_LEFT if left else RELEASE_RIGHT) * release
			var axis := rest.basis.x.normalized() if left else rest.basis.z.normalized()
			tilt = Basis(axis, (RELEASE_OPEN_LEFT if left else RELEASE_OPEN_RIGHT) * release) * tilt
		pivot.transform = Transform3D(tilt * sway * rest.basis, rest.origin + off + drift + work_off)
		var v := GenesisChoreography.veins(g, t, not left)
		if not is_equal_approx(v, float(_veins_written[id])):
			_veins_written[id] = v
			(_mats[id] as ShaderMaterial).set_shader_parameter("veins", v)
		(_mats[id] as ShaderMaterial).set_shader_parameter("motion_time", m)
		_update_mist(id, m, vis)
		_update_shed(id, m, vis)
		var want := 1.0 if Session.selected == id else (0.5 if Session.hovered == id else 0.0)
		var cur := float(_select[id])
		if not is_equal_approx(cur, want):
			cur = move_toward(cur, want, SELECT_RATE * delta) if delta > 0.0 else want
			_select[id] = cur
			(_mats[id] as ShaderMaterial).set_shader_parameter("select", cur)
	if not is_equal_approx(present, _present):
		_present = present
		var shown := present > 0.001
		for id: StringName in HANDS:
			var mi: MeshInstance3D = hands[id]
			(pivots[id] as Node3D).visible = shown
			# Fade out of the mist: transparency only while fading (opaque pipeline otherwise).
			mi.transparency = 1.0 - present if present < 0.999 else 0.0
			(_bodies[id] as StaticBody3D).collision_layer = 2 if present > 0.5 else 0


## The mist around a forearm: motes drift slowly along and around the arm (ambient), always dim.
func _update_mist(id: StringName, m: float, vis: float) -> void:
	var mist: MoteCloud = _mist[id]
	if vis <= 0.001:
		return
	var data: Array = _mist_seed[id]
	var seeds: PackedVector3Array = data[0]
	var extra: PackedFloat32Array = data[1]
	var col := Color(1, 1, 1, 0)
	for i in mist.visible_count:
		var e := extra[i]
		var ph := TAU * (m / (22.0 + 14.0 * e) + e)
		var p := seeds[i] + Vector3(0.35 * sin(ph), 0.25 * sin(ph * 1.3 + e * 5.0), 0.3 * cos(ph * 0.8))
		col.a = MIST_ALPHA * vis * (0.55 + 0.45 * sin(ph * 0.5 + e * 3.0))
		mist.set_mote(i, p, 0.7 + 0.6 * e, col)
	mist.commit()


## Dust shed where the stone ends (ambient life cycle): each mote is born on a ring around the
## forearm near its end, drifts outwards along the arm, spreads and sinks a little, fading in and out.
func _update_shed(id: StringName, m: float, vis: float) -> void:
	var shed: MoteCloud = _shed[id]
	shed.visible = vis > 0.001
	if not shed.visible:
		return
	var fr: Array = _shed_frame[id]
	var wrist: Vector3 = fr[0]
	var arm_end: Vector3 = fr[1]
	var ring: float = fr[2]
	var axis := (arm_end - wrist).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	var up := side.cross(axis).normalized()
	var seeds: PackedVector3Array = _shed_seed[id]
	var col := Color(1, 1, 1, 0)
	for i in shed.visible_count:
		var s := seeds[i]
		var u := fposmod(m / (SHED_LIFE * (0.75 + 0.5 * s.z)) + s.y, 1.0)
		var ang := TAU * s.x + 0.8 * u
		var r := ring * (0.75 + 0.35 * s.z) * (1.0 + 0.8 * u)
		var born := wrist.lerp(arm_end, 0.72 + 0.3 * s.z)
		var p := born + axis * SHED_DRIFT * u * (0.5 + 0.5 * s.x) + (side * cos(ang) + up * sin(ang)) * r - up * 0.9 * u * u
		col.a = SHED_ALPHA * vis * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.45, 1.0, u)) * (0.5 + 0.5 * s.y)
		shed.set_mote(i, p, 0.6 + 0.9 * s.z * (1.0 - 0.5 * u), col)
	shed.commit()


## Kintsugi level last written for a hand (tests/debug).
func veins_of(id: StringName) -> float:
	return float(_veins_written.get(id, -1.0))
