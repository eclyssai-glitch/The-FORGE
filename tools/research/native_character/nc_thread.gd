class_name NCThread
extends MeshInstance3D
## SPIKE — intention thread between MIKU's fingertip and a puppet hand. Own code (no native node is a
## "rope with tension"): a camera-facing ribbon on a quadratic curve whose sag falls as tension rises.
## Production: art-director's thread material (uniform tension/presence) on a reused mesh.

const SEGMENTS := 24

var tension := 0.0
var presence := 0.0
var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	mesh = _im
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func draw(a: Vector3, b: Vector3, cam: Vector3) -> void:
	_im.clear_surfaces()
	if presence < 0.02:
		return
	var length := a.distance_to(b)
	var sag := length * 0.22 * (1.0 - tension)
	var mid := (a + b) * 0.5 + Vector3.DOWN * sag
	var width := lerpf(0.004, 0.009, tension)
	var c := Color(1.0, 0.86, 0.62).lerp(Color(1.0, 0.97, 0.9), tension)
	c.a = presence * lerpf(0.45, 1.0, tension)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	# the thread grows from her finger towards the hand while presence rises (cause -> effect)
	var reach := clampf(presence * 1.25, 0.0, 1.0)
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS) * reach
		var p := (1.0 - t) * (1.0 - t) * a + 2.0 * (1.0 - t) * t * mid + t * t * b
		var tan := (2.0 * (1.0 - t) * (mid - a) + 2.0 * t * (b - mid)).normalized()
		var side := tan.cross((cam - p).normalized()).normalized() * width
		_im.surface_set_color(c)
		_im.surface_add_vertex(to_local(p - side))
		_im.surface_set_color(c)
		_im.surface_add_vertex(to_local(p + side))
	_im.surface_end()
