class_name MoteCloud
extends MultiMeshInstance3D
## A cloud of soft round motes (MaterialLibrary.mote, billboarded, additive) whose positions,
## sizes and colours are written by the owner — the deterministic particle primitive of the GENESIS
## scene (poses are functions of the simulation time or of MotionClock, never of an emitter
## state, so pause/seek/reset are exact). Owner: animator.
## Writes go to a reused PackedFloat32Array (no allocation per frame) and reach the GPU once per
## commit(). Instance colour multiplies the mote colour; RGB may exceed 1 (HDR) for the few
## motes that should bloom (seed, formation sparks). Quality scales the visible count
## (Quality.profile["particles"], with a floor).

## Floats per instance: 12 (Transform3D) + 4 (colour).
const STRIDE := 16

var count := 0
## Instances drawn under the current quality (<= count).
var visible_count := 0
var min_visible := 8

var _buf := PackedFloat32Array()
var _dirty := false


## Builds the cloud: `n` motes of quad edge `size` in `color` (a Palette colour), with a near fade
## (view metres: hidden at x, fully visible from y). `scales_with_quality` = the visible count follows
## Quality.profile["particles"].
func setup(n: int, color: Color, size: float, near_fade := Vector2(1.5, 4.0), scales_with_quality := true,
		bounds := AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))) -> MoteCloud:
	count = n
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := MaterialLibrary.mote(color).duplicate() as ShaderMaterial
	mat.set_shader_parameter("near_fade", near_fade)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = n
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = bounds
	_buf.resize(n * STRIDE)
	_buf.fill(0.0)
	visible_count = n
	mm.visible_instance_count = n
	if scales_with_quality:
		Quality.profile_changed.connect(_on_quality)
		_on_quality(Quality.profile)
	return self


## Mote `i` at `pos` (local), edge scale `s` (× quad size) and colour `c` (alpha = opacity).
func set_mote(i: int, pos: Vector3, s: float, c: Color) -> void:
	var o := i * STRIDE
	_buf[o] = s
	_buf[o + 1] = 0.0
	_buf[o + 2] = 0.0
	_buf[o + 3] = pos.x
	_buf[o + 4] = 0.0
	_buf[o + 5] = s
	_buf[o + 6] = 0.0
	_buf[o + 7] = pos.y
	_buf[o + 8] = 0.0
	_buf[o + 9] = 0.0
	_buf[o + 10] = s
	_buf[o + 11] = pos.z
	_buf[o + 12] = c.r
	_buf[o + 13] = c.g
	_buf[o + 14] = c.b
	_buf[o + 15] = c.a
	_dirty = true


## Hides mote `i` (zero size, transparent).
func hide_mote(i: int) -> void:
	var o := i * STRIDE
	_buf[o] = 0.0
	_buf[o + 5] = 0.0
	_buf[o + 10] = 0.0
	_buf[o + 15] = 0.0
	_dirty = true


## Position of mote `i` as last written (tests/debug).
func mote_position(i: int) -> Vector3:
	var o := i * STRIDE
	return Vector3(_buf[o + 3], _buf[o + 7], _buf[o + 11])


## Colour of mote `i` as last written (tests/debug).
func mote_color(i: int) -> Color:
	var o := i * STRIDE
	return Color(_buf[o + 12], _buf[o + 13], _buf[o + 14], _buf[o + 15])


## Sends the written motes to the GPU (only when something changed).
func commit() -> void:
	if not _dirty or multimesh == null:
		return
	_dirty = false
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buf)


func _on_quality(profile: Dictionary) -> void:
	var ratio := clampf(float(profile.get("particles", 1.0)), 0.0, 1.0)
	visible_count = clampi(int(round(count * ratio)), mini(min_visible, count), count)
	if multimesh:
		multimesh.visible_instance_count = visible_count
