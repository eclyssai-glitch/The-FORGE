class_name WorkSite
extends Node3D
## One work world of the living prototype (Loop 5), drawn from its WorldBuild. Owner: animator.
## Matter is FRAGMENTS (one MultiMesh): a drifting cloud of raw matter, then a core of packed
## pebbles (and a compressed core body that grows as the core is pressed), then three shells of
## plates laid one by one. A fragment never pops: it flies from its place in the cloud to its
## slot along a curve that passes through `via` — the palm of the hand that is working the world
## (WorkWorld.set_via) — so matter visibly goes through the hands. Arrivals are staggered.
## Failure: a crack opens a wedge of the outer shells (plates pushed out, seam heat in the
## material), an imbalance tilts and wobbles the whole world, a collapse lets the wedge's plates
## fall away into floating rubble. Dismantling sends plates back to the cloud through the hand.
## Before ADJUST the shells sit slightly askew; aligning brings them into one sphere.
## Instance custom data (for the art-director's world material): (arrival 0..1, crack heat 0..1,
## energy 0..1, shell 0..1). Pick body: layer 2, meta entity_id = id, group of the entity.

const CORE_FRAGMENTS := 34
const LAYER_FRAGMENTS: Array[int] = [40, 52, 64]
const LAYER_RADIUS: Array[float] = [0.55, 0.74, 0.93]
const CORE_RADIUS := 0.38
const CORE_BODY := 0.34
const PLATE_THICKNESS := 0.085
## Cloud: radius range (x r), flattening, and contraction when gathered.
const CLOUD := Vector2(1.25, 1.95)
const CLOUD_FLAT := 0.45
const GATHERED := 0.6
const STAGGER := 0.7
## Crack wedge: direction (local; towards MIKU and the camera) and half angle (rad).
const CRACK_HALF_ANGLE := 0.75
const CRACK_PUSH := 0.22
## Imbalance: tilt (rad) and wobble.
const TILT := 0.42
const WOBBLE := 0.12
## Misalignment of the shells before ADJUST (rad).
const ASKEW := 0.28
## Updates of a dormant world per second (its cloud drifts slowly).
const DORMANT_HZ := 10.0

var id: StringName = &""
var radius := 1.0
var build := WorldBuild.new()
var visual: Node3D
var fragments: MultiMeshInstance3D
var core_body: MeshInstance3D
var material: Material
var core_material: Material
var pick_body: StaticBody3D
## World point the flying matter passes through (the working hand's palm); INF = none.
var via := Vector3.INF

var _count := 0
var _group := PackedInt32Array()
var _slot := PackedVector3Array()
var _normal := PackedVector3Array()
var _cloud := PackedVector3Array()
var _stagger := PackedFloat32Array()
var _size := PackedVector3Array()
var _spin_axis := PackedVector3Array()
var _spin_rate := PackedFloat32Array()
var _wedge := PackedFloat32Array()
var _fall_order := PackedFloat32Array()
var _fall_t := PackedFloat32Array()
var _askew: Array[Quaternion] = []
var _crack_dir := Vector3.ZERO
var _tilt_axis := Vector3.RIGHT
var _time := 0.0
var _since_draw := 1.0
var _tilt := SecondOrder.new(0.45, 0.25, 0.0, 0.0)
var _spin := 0.0
var _applied := Vector4(-1, -1, -1, -1)


func _init(world_id: StringName = &"world_a", center := Vector3.ZERO, r := 1.0, seed_value := 1) -> void:
	id = world_id
	radius = r
	name = "WorkSite_" + String(world_id)
	position = center
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_generate(seed_value)
	material = LivingMaterials.get_material(&"world").duplicate()
	core_material = LivingMaterials.get_material(&"world").duplicate()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = _count
	fragments = MultiMeshInstance3D.new()
	fragments.name = "Fragments"
	fragments.multimesh = mm
	fragments.material_override = material
	visual.add_child(fragments)
	core_body = MeshInstance3D.new()
	core_body.name = "CoreBody"
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 32
	sph.rings = 16
	core_body.mesh = sph
	core_body.material_override = core_material
	core_body.scale = Vector3.ONE * 0.001
	visual.add_child(core_body)
	pick_body = StaticBody3D.new()
	pick_body.name = "Pick"
	pick_body.collision_layer = 2
	pick_body.collision_mask = 0
	pick_body.set_meta(&"entity_id", id)
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius * 1.7
	shape.shape = s
	pick_body.add_child(shape)
	add_child(pick_body)
	set_meta(&"entity_id", id)
	set_meta(&"focus_bounds", AABB(Vector3.ONE * -radius * 1.8, Vector3.ONE * radius * 3.6))


func _ready() -> void:
	add_to_group(SessionState.entity_group(id))
	_draw(0.0)


## Local direction of the crack wedge (faces MIKU and the camera).
func crack_direction() -> Vector3:
	return _crack_dir


## World position of the crack's centre on the outer shell (where MIKU looks when it breaks).
func crack_point() -> Vector3:
	return visual.global_transform * (_crack_dir * radius * LAYER_RADIUS[2])


func step(dt: float) -> void:
	_time += dt
	_since_draw += dt
	build.cool(dt)
	_tilt.step(build.imbalance, dt)
	if build.stage == WorldBuild.Stage.STABLE and not build.is_broken():
		_spin += dt * 0.12
	var awake := build.stage != WorldBuild.Stage.DORMANT or build.energy > 0.0 or via != Vector3.INF
	if awake or _since_draw >= 1.0 / DORMANT_HZ:
		_draw(_since_draw)


## Redraws every fragment; `dt` = seconds since the last draw (rubble keeps falling).
func _draw(dt: float) -> void:
	_since_draw = 0.0
	var b := build
	# The whole world: tilt and wobble when unbalanced, slow turn when stable.
	var wob := sin(_time * 2.3) * WOBBLE * _tilt.y + sin(_time * 3.7 + 1.0) * WOBBLE * 0.5 * _tilt.y
	visual.transform = Transform3D(Basis(Vector3.UP, _spin) * Basis(_tilt_axis, _tilt.y * TILT + wob),
		Vector3(0.0, -_tilt.y * radius * 0.12, 0.0))
	var mm := fragments.multimesh
	var gathered := lerpf(1.0, GATHERED, smoothstep(0.0, 1.0, b.gather))
	var via_local := visual.global_transform.affine_inverse() * via if via != Vector3.INF else Vector3.INF
	var swirl := _time * (0.05 + 0.1 * b.gather)
	for i in _count:
		var g := _group[i]
		var p := b.core if g == 0 else b.layers[g - 1]
		var q := clampf(p * (1.0 + STAGGER) - _stagger[i] * STAGGER, 0.0, 1.0)
		q = q * q * (3.0 - 2.0 * q)
		# Cloud place: drifting, contracting when gathered.
		var c := _cloud[i]
		var ang := swirl / maxf(c.length() / radius, 0.5)
		var cloud := Basis(Vector3.UP, ang) * c * gathered
		cloud.y += sin(_time * 0.4 + float(i)) * radius * 0.04
		# Slot: askew before alignment; pushed out by the crack; fallen when collapsed.
		var slot := _slot[i]
		var nrm := _normal[i]
		if g > 0:
			var sk := _askew[g - 1].slerp(Quaternion.IDENTITY, b.align)
			slot = sk * slot
			nrm = sk * nrm
		var heat := 0.0
		if g >= 2 and _wedge[i] > 0.0:
			heat = b.crack * _wedge[i]
			slot += nrm * radius * CRACK_PUSH * heat
			if g == 3 and b.collapsed > 0.0 and _fall_order[i] < b.collapsed:
				_fall_t[i] += dt
				var t := _fall_t[i]
				slot += nrm * radius * 0.9 * (1.0 - exp(-t * 0.9)) + Vector3.DOWN * radius * 1.5 * (1.0 - exp(-t * 0.6))
				heat = 1.0
			elif _fall_t[i] > 0.0 and q < 0.999:
				_fall_t[i] = maxf(_fall_t[i] - dt * 2.0, 0.0)
		# Flight from the cloud to the slot through the working hand.
		var pos := slot
		if q < 1.0:
			var ctrl := via_local if via_local != Vector3.INF else (cloud + slot) * 0.5 + Vector3.UP * radius * 0.4
			var u := 1.0 - q
			pos = cloud * u * u + ctrl * 2.0 * u * q + slot * q * q
		var tumble := Basis(_spin_axis[i], _time * _spin_rate[i] + float(i))
		var seat := MikuMannequin._basis_y(nrm)
		var basis := tumble.slerp(seat, q) if q > 0.0 else tumble
		# Raw matter is grit; it becomes a plate as it is laid.
		var grow := lerpf(0.32, 1.0, q) if g > 0 else lerpf(0.6, 1.0, q)
		mm.set_instance_transform(i, Transform3D(basis.scaled_local(_size[i] * grow), pos))
		mm.set_instance_custom_data(i, Color(q, heat, b.energy, float(g) / 3.0))
	var core_s := radius * CORE_BODY * smoothstep(0.35, 1.0, b.core)
	core_body.scale = Vector3.ONE * maxf(core_s, 0.001)
	core_body.visible = core_s > 0.002
	var params := Vector4(b.progress(), b.crack, b.energy, b.align)
	if not params.is_equal_approx(_applied):
		_applied = params
		for m in [material, core_material]:
			LivingMaterials.set_param(m, &"build", params.x)
			LivingMaterials.set_param(m, &"crack", params.y)
			LivingMaterials.set_param(m, &"energy", params.z)


func _generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var groups: Array[int] = [CORE_FRAGMENTS]
	groups.append_array(LAYER_FRAGMENTS)
	# The crack wedge faces MIKU (at the world origin) and the camera, a little to the side.
	var to_miku := -position
	to_miku.y = 0.0
	_crack_dir = (to_miku.normalized() * 0.8 + Vector3(0.0, 0.45, 0.0) + Vector3(0.0, 0.0, 0.5)).normalized()
	_tilt_axis = _crack_dir.cross(Vector3.UP).normalized()
	for k in LAYER_FRAGMENTS.size():
		var ax := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		_askew.append(Quaternion(ax, ASKEW * (1.0 + 0.3 * k) * (1.0 if k % 2 == 0 else -1.0)))
	for g in groups.size():
		var n: int = groups[g]
		var shell_r := radius * (CORE_RADIUS if g == 0 else LAYER_RADIUS[g - 1])
		var side := sqrt(4.0 * PI * shell_r * shell_r / float(n)) * 1.08
		for k in n:
			# Fibonacci sphere, rotated per shell so the shells do not line up.
			var yy := 1.0 - (float(k) + 0.5) / float(n) * 2.0
			var rr := sqrt(maxf(1.0 - yy * yy, 0.0))
			var th := PI * (3.0 - sqrt(5.0)) * float(k) + float(g) * 1.3
			var dir := Vector3(cos(th) * rr, yy, sin(th) * rr)
			var slot := dir * shell_r
			if g == 0:
				slot = dir * shell_r * pow(rng.randf_range(0.35, 1.0), 0.5)
			_group.append(g)
			_slot.append(slot)
			_normal.append(dir)
			var cd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1) * CLOUD_FLAT, rng.randf_range(-1, 1))
			cd = cd.normalized() if cd.length_squared() > 1e-6 else Vector3.RIGHT
			_cloud.append(cd * radius * rng.randf_range(CLOUD.x, CLOUD.y))
			_stagger.append(rng.randf())
			if g == 0:
				var s := radius * rng.randf_range(0.11, 0.17)
				_size.append(Vector3(s, s * rng.randf_range(0.7, 1.0), s * rng.randf_range(0.8, 1.1)))
			else:
				_size.append(Vector3(side, radius * PLATE_THICKNESS, side * rng.randf_range(0.85, 1.05)))
			_spin_axis.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
			_spin_rate.append(rng.randf_range(0.15, 0.6))
			var w := 0.0
			if g >= 2:
				var a := dir.angle_to(_crack_dir)
				w = clampf(1.0 - a / CRACK_HALF_ANGLE, 0.0, 1.0)
			_wedge.append(w)
			_fall_order.append(1.0 - w + rng.randf() * 0.15)
			_fall_t.append(0.0)
	_count = _group.size()
