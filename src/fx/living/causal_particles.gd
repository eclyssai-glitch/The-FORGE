class_name CausalParticles
extends Node3D
## Particles of the living prototype (Loop 5) — only where they explain an action. Owner: animator.
## There is no ambient emitter: every mote is emitted by a cause, through one of these calls:
##   compress(at, radius, strength)   matter squeezed by the hands: motes drawn INTO the point;
##   fragments(at, dir, strength)     chips thrown out of a crack / collapse;
##   energy(thread_id, strength)      energy carried along an intent thread, MIKU -> hand
##                                    (positions re-read from IntentThreads each frame);
##   form(at, radius)                 a stage of a world settling (a ring of motes that fades).
## CPU pool on one MultiMesh (billboard quads, per-instance colour for the fade); the pool size
## and every count scale with Quality.profile["particles"]. Nothing is allocated per frame;
## the MultiMesh is written only while motes live.

const GROUP := &"living_particles"
const POOL := 900
const LIFE := {&"compress": 0.9, &"fragments": 1.6, &"energy": 0.7, &"form": 1.3}
const SIZE := {&"compress": 0.035, &"fragments": 0.05, &"energy": 0.03, &"form": 0.03}

enum Kind { COMPRESS, FRAGMENTS, ENERGY, FORM }
const KEYS: Array[StringName] = [&"compress", &"fragments", &"energy", &"form"]

var threads: IntentThreads
var mm: MultiMeshInstance3D
var quality := 1.0
## Live motes now (tests/debug).
var alive := 0
## Motes emitted per kind since composition (tests: no kind is ever emitted without a cause).
var emitted := {&"compress": 0, &"fragments": 0, &"energy": 0, &"form": 0}

var _kind := PackedInt32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _target := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _thread := PackedInt32Array()
var _s := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _next := 0
var _dirty := false


func _init() -> void:
	name = "CausalParticles"
	_rng.seed = 7707
	for arr in [_kind, _thread]:
		(arr as PackedInt32Array).resize(POOL)
	for arr in [_pos, _vel, _target]:
		(arr as PackedVector3Array).resize(POOL)
	for arr in [_age, _life, _size, _s]:
		(arr as PackedFloat32Array).resize(POOL)
	for i in POOL:
		_life[i] = 0.0
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	m.mesh = quad
	m.instance_count = POOL
	m.visible_instance_count = 0
	mm = MultiMeshInstance3D.new()
	mm.name = "Motes"
	mm.multimesh = m
	mm.material_override = LivingMaterials.get_material(&"mote")
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)


func _ready() -> void:
	add_to_group(GROUP)
	if not Quality.profile.is_empty():
		_on_quality(Quality.profile)
	Quality.profile_changed.connect(_on_quality)


func _on_quality(profile: Dictionary) -> void:
	quality = clampf(float(profile.get("particles", 1.0)), 0.0, 1.0)


func compress(at: Vector3, radius: float, strength := 1.0) -> void:
	var n := _count(14.0 * strength)
	for k in n:
		var dir := _rand_dir()
		var i := _spawn(Kind.COMPRESS, at + dir * radius * _rng.randf_range(1.1, 1.8))
		_target[i] = at
		_vel[i] = Vector3.ZERO


func fragments(at: Vector3, dir: Vector3, strength := 1.0) -> void:
	var n := _count(18.0 * strength)
	for k in n:
		var d := (dir.normalized() + _rand_dir() * 0.7).normalized()
		var i := _spawn(Kind.FRAGMENTS, at + _rand_dir() * 0.05)
		_vel[i] = d * _rng.randf_range(0.6, 1.8) * strength


func energy(thread_id: int, strength := 1.0) -> void:
	if threads == null:
		return
	var n := _count(4.0 * strength)
	for k in n:
		var i := _spawn(Kind.ENERGY, Vector3.ZERO)
		_thread[i] = thread_id
		_s[i] = -float(k) * 0.12
		_vel[i] = Vector3.ZERO


func form(at: Vector3, radius: float) -> void:
	var n := _count(22.0)
	for k in n:
		var ang := TAU * float(k) / float(maxi(n, 1))
		var i := _spawn(Kind.FORM, at + Vector3(cos(ang), 0.0, sin(ang)) * radius)
		_vel[i] = Vector3(cos(ang), 0.15, sin(ang)) * radius * 0.5


func step(dt: float) -> void:
	if alive == 0 and not _dirty:
		return
	var m := mm.multimesh
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var face := cam.global_transform.basis if cam != null else Basis.IDENTITY
	var n := 0
	for i in POOL:
		if _life[i] <= 0.0:
			continue
		_age[i] += dt
		var t := _age[i] / _life[i]
		if t >= 1.0:
			_life[i] = 0.0
			continue
		match _kind[i]:
			Kind.COMPRESS:
				_pos[i] = _pos[i].lerp(_target[i], 1.0 - exp(-dt * 3.5))
			Kind.FRAGMENTS:
				_vel[i] *= exp(-dt * 1.2)
				_vel[i] += Vector3.DOWN * dt * 0.6
				_pos[i] += _vel[i] * dt
			Kind.ENERGY:
				_s[i] += dt / _life[i]
				var tid := _thread[i]
				if threads == null or tid < 0 or tid >= threads.threads.size():
					_life[i] = 0.0
					continue
				_pos[i] = threads.point_at(tid, clampf(_s[i], 0.0, 1.0))
			Kind.FORM:
				_vel[i] *= exp(-dt * 1.5)
				_pos[i] += _vel[i] * dt
		var fade := sin(PI * clampf(t, 0.0, 1.0))
		if _kind[i] == Kind.ENERGY and _s[i] < 0.0:
			fade = 0.0
		var sz := _size[i] * (0.6 + 0.4 * fade)
		m.set_instance_transform(n, Transform3D(face.scaled_local(Vector3.ONE * sz), _pos[i]))
		m.set_instance_color(n, Color(1.0, 1.0, 1.0, fade))
		n += 1
	alive = n
	m.visible_instance_count = n
	_dirty = n > 0


func _count(base: float) -> int:
	return maxi(int(round(base * quality)), 1 if quality > 0.0 else 0)


func _spawn(kind: Kind, at: Vector3) -> int:
	var i := _next
	_next = (_next + 1) % POOL
	var key: StringName = KEYS[kind]
	_kind[i] = kind
	_pos[i] = at
	_age[i] = 0.0
	_life[i] = float(LIFE[key]) * _rng.randf_range(0.8, 1.2)
	_size[i] = float(SIZE[key]) * _rng.randf_range(0.7, 1.3)
	_thread[i] = -1
	emitted[key] = int(emitted[key]) + 1
	_dirty = true
	alive += 1
	return i


func _rand_dir() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length_squared() > 1e-6 else Vector3.UP
