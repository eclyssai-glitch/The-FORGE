class_name EmissionSparks
extends Node3D
## Short EMBER burst of shards out of the core when FRAGMENTS_EMITTED happens (the energy that
## throws the fragments out). Owner: animator. Deterministic: a MultiMesh of MeshBuilder.shard
## whose poses are a function of the sim time since the event (Choreography.sparks), so seek and
## pause freeze/replay it exactly. Count scales with Quality.profile["particles"].

const MAX_SPARKS := 72
const SEED := 4201
const SPEED_MIN := 2.2
const SPEED_MAX := 5.4
const SIZE := 0.16

var sparks: MultiMeshInstance3D

var _dirs := PackedVector3Array()
var _speeds := PackedFloat32Array()
var _axes := PackedVector3Array()
var _last := -1.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in MAX_SPARKS:
		var z := rng.randf_range(-0.55, 0.9)
		var a := rng.randf() * TAU
		var h := sqrt(1.0 - z * z)
		_dirs.append(Vector3(h * sin(a), z, h * cos(a)))
		_speeds.append(rng.randf_range(SPEED_MIN, SPEED_MAX))
		_axes.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
	var mat := MaterialLibrary.spark(Palette.EMBER)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshBuilder.shard(SIZE, SEED)
	mm.instance_count = MAX_SPARKS
	sparks = MultiMeshInstance3D.new()
	sparks.name = "Sparks"
	sparks.multimesh = mm
	sparks.material_override = mat
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.custom_aabb = AABB(Vector3(-7, -7, -7), Vector3(14, 14, 14))
	sparks.visible = false
	add_child(sparks)
	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)
	_update()


func _process(_delta: float) -> void:
	_update()


func _on_quality(profile: Dictionary) -> void:
	var ratio := clampf(float(profile.get("particles", 1.0)), 0.0, 1.0)
	sparks.multimesh.visible_instance_count = maxi(int(round(MAX_SPARKS * ratio)), 8)


func _update() -> void:
	var p := Choreography.sparks(Simulation.world, Simulation.time)
	var on := p > 0.0 and p < 1.0
	sparks.visible = on
	if not on or is_equal_approx(p, _last):
		return
	_last = p
	var mm := sparks.multimesh
	var travel := Motion.eased(p, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	var size := pow(1.0 - p, 1.4)
	for i in MAX_SPARKS:
		var d := _dirs[i]
		# Shards fly along their direction, long axis aligned with the motion, spinning slightly.
		var basis := Basis(_axes[i], p * 3.0) * _align_y(d)
		basis = basis.scaled(Vector3.ONE * size)
		mm.set_instance_transform(i, Transform3D(basis, d * (0.5 + _speeds[i] * travel)))


static func _align_y(d: Vector3) -> Basis:
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up))
