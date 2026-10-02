class_name IntentThreads
extends Node3D
## MIKU's intent threads (Loop 5): intention and control, never decoration. Owner: animator.
## Each thread ties one of MIKU's fingertips to a puppet hand (its back, or a fingertip when an
## angry MIKU drives a hand with several threads) and lives a ThreadCycle: cast from her finger
## (it grows from her towards the hand), pulled (tension), relaxed (it sags), faded. While it
## lives its ends are re-read every frame, so it follows both her gesture and the hand's inertia.
## The tension is what moves the hand (tension_on(hand) -> PuppetHand.pull).
##
## Geometry: SEGMENTS thin cylinders of a MultiMesh per thread, along a curve that sags with
## gravity in proportion to (1 - tension) and trembles a little when taut and MIKU's composure is
## lost (`tremble`). Radius grows with tension. Material: LivingMaterials &"thread" duplicated per
## thread, uniforms `tension` and `presence` written when they change. Pool without limit:
## a thread node is reused once its cycle is GONE. Nothing is allocated per frame.

const GROUP := &"living_threads"
const SEGMENTS := 28
const RADIUS := Vector2(0.007, 0.017)
## Sag (share of the length) of a slack thread.
const SAG := 0.14
## Taut tremble: amplitude (share of length) and frequency (Hz) at tremble 1.
const TREMBLE_AMP := 0.006
const TREMBLE_HZ := 23.0

## Returns MIKU's fingertip in world space: func(side: int, finger: int) -> Vector3.
var miku_tip: Callable
## 0..1, set by MIKU (lost composure = taut threads tremble).
var tremble := 0.0
var threads: Array[Dictionary] = []

var _time := 0.0
var _mesh: CylinderMesh


func _init() -> void:
	name = "IntentThreads"
	_mesh = CylinderMesh.new()
	_mesh.top_radius = 1.0
	_mesh.bottom_radius = 1.0
	_mesh.height = 1.0
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_mesh.cap_top = false
	_mesh.cap_bottom = false


func _ready() -> void:
	add_to_group(GROUP)


## Casts a thread from MIKU's finger (`side` 0 left / 1 right, `finger` 0..4) to `hand`
## (`hand_point` -1 = the back of the hand, 0..4 = a fingertip). Returns its id.
func cast(side: int, finger: int, hand: PuppetHand, hand_point := -1, force := 0.0, speed := 1.0) -> int:
	var id := _free_slot()
	var t: Dictionary = threads[id]
	t["side"] = side
	t["finger"] = finger
	t["hand"] = hand
	t["point"] = hand_point
	t["target"] = Vector3.ZERO
	t["phase0"] = float(id) * 1.7
	(t["cycle"] as ThreadCycle).start(force, speed)
	(t["node"] as MultiMeshInstance3D).visible = true
	return id


## Casts a thread to a fixed world point (no hand: e.g. the configuration artifact).
func cast_to_point(side: int, finger: int, target: Vector3, force := 0.0, speed := 1.0) -> int:
	var id := cast(side, finger, null, -1, force, speed)
	threads[id]["target"] = target
	return id


func pull(id: int, force: float) -> void:
	if id >= 0 and id < threads.size():
		(threads[id]["cycle"] as ThreadCycle).pull(force)


func relax(id: int) -> void:
	if id >= 0 and id < threads.size():
		(threads[id]["cycle"] as ThreadCycle).relax()


## Relaxes every thread tied to `hand`.
func relax_hand(hand: PuppetHand) -> void:
	for t in threads:
		if t["hand"] == hand:
			(t["cycle"] as ThreadCycle).relax()


func relax_all() -> void:
	for t in threads:
		(t["cycle"] as ThreadCycle).relax()


## Pulls every live thread tied to `hand` with `force`.
func pull_hand(hand: PuppetHand, force: float) -> void:
	for t in threads:
		var c := t["cycle"] as ThreadCycle
		if t["hand"] == hand and c.is_alive() and c.phase != ThreadCycle.Phase.FADE:
			c.pull(force)


## True when `hand` has a thread that is alive (cast, pulled, relaxing or fading).
func has_live_thread(hand: PuppetHand) -> bool:
	for t in threads:
		var c := t["cycle"] as ThreadCycle
		if t["hand"] == hand and c.is_alive() and c.phase != ThreadCycle.Phase.FADE:
			return true
	return false


## Tension that reaches `hand` (the strongest of its responding threads; 0 if none responds).
func tension_on(hand: PuppetHand) -> float:
	var best := 0.0
	for t in threads:
		var c := t["cycle"] as ThreadCycle
		if t["hand"] == hand and c.responding():
			best = maxf(best, c.tension.y)
	return best


func cycle(id: int) -> ThreadCycle:
	return threads[id]["cycle"] if id >= 0 and id < threads.size() else null


## Threads alive now.
func alive_count() -> int:
	var n := 0
	for t in threads:
		if (t["cycle"] as ThreadCycle).is_alive():
			n += 1
	return n


## World ends of thread `id` now: [from, to].
func ends(id: int) -> PackedVector3Array:
	var t: Dictionary = threads[id]
	return PackedVector3Array([t["a"], t["b"]])


## Point at share `s` (0 = MIKU's finger, 1 = the hand) along thread `id`, on its sagging curve.
func point_at(id: int, s: float) -> Vector3:
	var t: Dictionary = threads[id]
	var c := t["cycle"] as ThreadCycle
	var a: Vector3 = t["a"]
	var b: Vector3 = t["b"]
	var u := clampf(s, 0.0, 1.0) * c.reach
	var length := (b - a).length()
	var sag := Vector3.DOWN * length * SAG * pow(1.0 - clampf(c.tension.y, 0.0, 1.0), 1.5)
	return a + (b - a) * u + sag * sin(PI * u)


func step(dt: float) -> void:
	_time += dt
	for t in threads:
		var c := t["cycle"] as ThreadCycle
		if not c.is_alive():
			continue
		c.step(dt)
		_update_ends(t)
		_draw(t)
		if not c.is_alive():
			(t["node"] as MultiMeshInstance3D).visible = false


func _update_ends(t: Dictionary) -> void:
	if miku_tip.is_valid():
		t["a"] = miku_tip.call(int(t["side"]), int(t["finger"]))
	var h: PuppetHand = t["hand"]
	if h != null and is_instance_valid(h):
		t["b"] = h.anchor() if int(t["point"]) < 0 else h.fingertip(int(t["point"]))
	else:
		t["b"] = t["target"]


func _draw(t: Dictionary) -> void:
	var c := t["cycle"] as ThreadCycle
	var mm := (t["node"] as MultiMeshInstance3D).multimesh
	var a: Vector3 = t["a"]
	var b: Vector3 = t["b"]
	var span := b - a
	var length := span.length()
	if length < 1e-4:
		mm.visible_instance_count = 0
		return
	var ten := clampf(c.tension.y, 0.0, 1.0)
	var sag := Vector3.DOWN * length * SAG * pow(1.0 - ten, 1.5)
	# Lateral axis for the tremble (perpendicular to the thread, roughly horizontal).
	var side := span.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-8 else Vector3.RIGHT
	var amp := TREMBLE_AMP * length * tremble * smoothstep(0.5, 0.9, ten)
	var ph: float = t["phase0"]
	var r := lerpf(RADIUS.x, RADIUS.y, ten) * clampf(c.presence.y * 1.5, 0.0, 1.0)
	var n := int(ceil(c.reach * SEGMENTS))
	mm.visible_instance_count = n
	var prev := a
	for i in n:
		var s1 := minf(float(i + 1) / SEGMENTS, c.reach)
		var p := a + span * s1 + sag * sin(PI * s1) \
			+ side * amp * sin(PI * s1) * sin(_time * TAU * TREMBLE_HZ + ph + s1 * 9.0)
		var d := p - prev
		var l := d.length()
		var basis := MikuMannequin._basis_y(d if l > 1e-6 else span)
		mm.set_instance_transform(i, Transform3D(basis.scaled_local(Vector3(r, maxf(l, 1e-4), r)), (prev + p) * 0.5))
		prev = p
	var mat: Material = t["mat"]
	if absf(float(t["applied_t"]) - ten) > 0.01:
		t["applied_t"] = ten
		LivingMaterials.set_param(mat, &"tension", ten)
	var pr := clampf(c.presence.y, 0.0, 1.0)
	if absf(float(t["applied_p"]) - pr) > 0.01:
		t["applied_p"] = pr
		LivingMaterials.set_param(mat, &"presence", pr)


func _free_slot() -> int:
	for i in threads.size():
		if not (threads[i]["cycle"] as ThreadCycle).is_alive():
			return i
	var node := MultiMeshInstance3D.new()
	node.name = "Thread%d" % threads.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = SEGMENTS
	mm.visible_instance_count = 0
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := LivingMaterials.get_material(&"thread").duplicate()
	node.material_override = mat
	add_child(node)
	threads.append({"cycle": ThreadCycle.new(), "node": node, "mat": mat, "side": 0, "finger": 1,
		"hand": null, "point": -1, "target": Vector3.ZERO, "a": Vector3.ZERO, "b": Vector3.ZERO,
		"phase0": 0.0, "applied_t": -1.0, "applied_p": -1.0})
	return threads.size() - 1
