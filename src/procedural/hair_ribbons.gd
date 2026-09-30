class_name HairRibbons
extends RefCounted
## MIKU's hair as narrow ribbons generated at runtime from control-point curves.
##
## - `generate_curves` makes N deterministic curves (seeded) that leave `hair_root` along a
##   direction (up/back) and flow in long waves.
## - `build` turns curves into one ArrayMesh of ribbons: UV.x runs along each strand 0 -> 1
##   (root -> tip, by arc length), UV.y across the ribbon 0 -> 1; width tapers to the tip.
##   UV2 = (strand index / (n - 1), per-strand hash in [0, 1]) for shader variation.
##   COLOR = white with alpha = strand opacity (per-strand 0.55..1, fading to 0 at the tip), as
##   MaterialLibrary.miku_hair() expects.
##   TANGENT follows the strand (for anisotropic highlights), NORMAL is the ribbon face normal.
##   `crossed = true` adds a second ribbon rotated 90 degrees around each strand (reads from
##   every angle; a flat ribbon vanishes edge-on). Both ribbons share UVs/colour.
## Curves are Catmull-Rom splines through their points (end points duplicated). Build once.

## Catmull-Rom point on the spline through `points` at t in [0, 1].
static func curve_point(points: PackedVector3Array, t: float) -> Vector3:
	var n := points.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return points[0]
	var f := clampf(t, 0.0, 1.0) * float(n - 1)
	var i := mini(floori(f), n - 2)
	var u := f - float(i)
	var p0 := points[maxi(i - 1, 0)]
	var p1 := points[i]
	var p2 := points[i + 1]
	var p3 := points[mini(i + 2, n - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


## `samples` points evenly spaced in the spline parameter (first = first point, last = last).
static func sample_curve(points: PackedVector3Array, samples: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := maxi(samples, 2)
	for k in count:
		out.append(curve_point(points, float(k) / float(count - 1)))
	return out


## Deterministic hair curves: `count` strands of about `length` units leaving `root` along
## `direction`, fanned inside a cone of half-angle `spread` (radians), each waving sideways with
## `wave_amplitude` over `waves` long periods, the heading bending towards world up as it goes
## (`rise`: 0 = straight, 1 = heading gains one unit of UP by the tip). Same arguments (and seed) always give the same curves.
static func generate_curves(root: Vector3, direction: Vector3, count: int, seed: int,
		length := 10.0, points := 9, spread := 0.5, wave_amplitude := 0.45, waves := 1.4,
		rise := 0.9, root_radius := 0.05) -> Array[PackedVector3Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := direction.normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 1e-4:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var up2 := side.cross(d).normalized()
	var curves: Array[PackedVector3Array] = []
	for s in count:
		# fan: uniform over the cone section, biased a little towards its centre
		var ang := rng.randf() * TAU
		var rad := spread * sqrt(rng.randf())
		var dir_s := (d * cos(rad) + (side * cos(ang) + up2 * sin(ang)) * sin(rad)).normalized()
		var len_s := length * rng.randf_range(0.72, 1.08)
		var phase := rng.randf() * TAU
		var amp := wave_amplitude * rng.randf_range(0.6, 1.2)
		var rise_s := rise * rng.randf_range(0.6, 1.3)
		var start := root + (side * rng.randf_range(-1.0, 1.0) + up2 * rng.randf_range(-1.0, 1.0)) * root_radius
		var s_side := dir_s.cross(up2)
		if s_side.length() < 1e-4:
			s_side = side
		s_side = s_side.normalized()
		var s_up := s_side.cross(dir_s).normalized()
		var pts := PackedVector3Array()
		var pos := start
		var step := len_s / float(maxi(points - 1, 1))
		for j in points:
			var u := float(j) / float(maxi(points - 1, 1))
			if j > 0:
				# heading bends slowly upwards while the strand advances (smoke-like rise)
				var heading := (dir_s + Vector3.UP * rise_s * u).normalized()
				pos += heading * step
			var wave := sin(waves * TAU * u + phase) * amp * u
			var sway := cos(waves * 0.5 * TAU * u + phase * 1.7) * amp * 0.35 * u
			pts.append(pos + s_side * wave + s_up * sway)
		curves.append(pts)
	return curves


## Ribbon mesh for all curves (one surface). `width` at the root, `tip_ratio` * width at the
## tip; `samples` points per strand; `facing` is the direction the ribbons face at the root
## (default: +Z, towards the default camera) and is then parallel-transported along each strand.
static func build(curves: Array[PackedVector3Array], width := 0.06, tip_ratio := 0.15,
		samples := 48, facing := Vector3.BACK, crossed := false) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var n_curves := curves.size()
	for c in n_curves:
		var pts := sample_curve(curves[c], samples)
		var count := pts.size()
		# arc length
		var cum := PackedFloat32Array()
		cum.append(0.0)
		for k in range(1, count):
			cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
		var total := maxf(cum[count - 1], 1e-6)
		var strand_u := float(c) / float(maxi(n_curves - 1, 1))
		var strand_h := fposmod(sin(float(c) * 12.9898 + 78.233) * 43758.5453, 1.0)
		var t_prev := (pts[1] - pts[0]).normalized()
		var w_dir := t_prev.cross(facing)
		if w_dir.length() < 1e-4:
			w_dir = t_prev.cross(Vector3.UP)
		w_dir = w_dir.normalized()
		var opacity := lerpf(0.55, 1.0, fposmod(strand_h * 7.31, 1.0))
		var frames_p := PackedVector3Array()
		var frames_t := PackedVector3Array()
		var frames_w := PackedVector3Array()
		var frames_n := PackedVector3Array()
		for k in count:
			var t: Vector3
			if k == 0:
				t = (pts[1] - pts[0]).normalized()
			elif k == count - 1:
				t = (pts[k] - pts[k - 1]).normalized()
			else:
				t = (pts[k + 1] - pts[k - 1]).normalized()
			# parallel transport of the width direction
			var axis := t_prev.cross(t)
			if axis.length() > 1e-6:
				w_dir = w_dir.rotated(axis.normalized(), t_prev.signed_angle_to(t, axis.normalized()))
			w_dir = (w_dir - t * w_dir.dot(t)).normalized()
			t_prev = t
			frames_p.append(pts[k])
			frames_t.append(t)
			frames_w.append(w_dir)
			frames_n.append(t.cross(w_dir).normalized())
		for layer in (2 if crossed else 1):
			var base := verts.size()
			for k in count:
				var t := frames_t[k]
				var wd := frames_w[k] if layer == 0 else frames_n[k]
				var nrm := t.cross(wd).normalized()
				var s := cum[k] / total
				var w := width * lerpf(1.0, tip_ratio, pow(s, 1.3))
				var alpha := opacity * pow(1.0 - s, 0.6)
				for side in 2:
					var off := (float(side) - 0.5) * w
					verts.append(frames_p[k] + wd * off)
					normals.append(nrm)
					tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
					uvs.append(Vector2(s, float(side)))
					uv2s.append(Vector2(strand_u, strand_h))
					colors.append(Color(1.0, 1.0, 1.0, alpha))
			for k in count - 1:
				var a := base + 2 * k
				_quad(verts, normals, indices, a, a + 1, a + 3, a + 2)
	return _commit(verts, normals, tangents, uvs, uv2s, colors, indices)


static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		a: int, b: int, c: int, d: int) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var i0: int = tri[0]
		var i1: int = tri[1]
		var i2: int = tri[2]
		var g := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		# Godot front faces are clockwise: (b-a)x(c-a) must point against the normal
		if g.dot(normals[i0] + normals[i1] + normals[i2]) > 0.0:
			indices.append_array(PackedInt32Array([i0, i2, i1]))
		else:
			indices.append_array(PackedInt32Array([i0, i1, i2]))


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
