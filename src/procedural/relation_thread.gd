class_name RelationThread
extends RefCounted
## Relation threads ("links" of the vault graph): a smooth arc between two points.
## The arc is a quadratic Bezier whose apex sits `height` units away from the chord midpoint,
## bulging towards `up` (its component perpendicular to the chord). UV.x runs 0 -> 1 from `a`
## to `b` (for the travelling pulse), UV.y 0 -> 1 across the ribbon.
## - `build`      : flat ribbon; `facing` = direction the ribbon faces (default: the normal of
##                  the arc plane, i.e. the ribbon lies in the arc plane).
## - `build_crossed`: two ribbons at 90 degrees (in the arc plane + across it); cheap and never
##                  vanishes edge-on (art-director recommendation), UV as `build`.
## - `build_tube` : thin tube with `radial` sides (reads from every angle), UV.y around.

static func bulge_dir(a: Vector3, b: Vector3, up := Vector3.UP) -> Vector3:
	var chord := b - a
	var n := up - chord * (up.dot(chord) / maxf(chord.length_squared(), 1e-12))
	if n.length() < 1e-5:
		n = chord.cross(Vector3.RIGHT)
		if n.length() < 1e-5:
			n = chord.cross(Vector3.BACK)
	return n.normalized()


static func arc_point(a: Vector3, b: Vector3, height: float, t: float, up := Vector3.UP) -> Vector3:
	var c := (a + b) * 0.5 + bulge_dir(a, b, up) * (2.0 * height)
	var s := 1.0 - t
	return a * (s * s) + c * (2.0 * s * t) + b * (t * t)


static func arc_tangent(a: Vector3, b: Vector3, height: float, t: float, up := Vector3.UP) -> Vector3:
	var c := (a + b) * 0.5 + bulge_dir(a, b, up) * (2.0 * height)
	var d := (c - a) * (2.0 * (1.0 - t)) + (b - c) * (2.0 * t)
	return d.normalized() if d.length() > 1e-9 else (b - a).normalized()


static func arc_points(a: Vector3, b: Vector3, height: float, segments := 48, up := Vector3.UP) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(segments, 1)
	for k in n + 1:
		out.append(arc_point(a, b, height, float(k) / float(n), up))
	return out


static func build(a: Vector3, b: Vector3, height: float, width: float, segments := 48,
		up := Vector3.UP, facing := Vector3.ZERO) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var plane_n := (b - a).cross(bulge_dir(a, b, up)).normalized()
	var face := plane_n if facing.length() < 1e-6 else facing.normalized()
	_ribbon(verts, normals, uvs, indices, a, b, height, width, segments, up, face)
	return _commit(verts, normals, uvs, indices)


static func build_crossed(a: Vector3, b: Vector3, height: float, width: float, segments := 48,
		up := Vector3.UP) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bulge := bulge_dir(a, b, up)
	var plane_n := (b - a).cross(bulge).normalized()
	_ribbon(verts, normals, uvs, indices, a, b, height, width, segments, up, plane_n)
	_ribbon(verts, normals, uvs, indices, a, b, height, width, segments, up, bulge)
	return _commit(verts, normals, uvs, indices)


## Appends one ribbon whose faces look along `face` (the width runs along tangent x face).
static func _ribbon(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, a: Vector3, b: Vector3, height: float, width: float,
		segments: int, up: Vector3, face: Vector3) -> void:
	var n := maxi(segments, 1)
	var base := verts.size()
	var prev_w := Vector3.ZERO
	for k in n + 1:
		var t := float(k) / float(n)
		var p := arc_point(a, b, height, t, up)
		var tan := arc_tangent(a, b, height, t, up)
		var w := tan.cross(face)
		if w.length() < 1e-5:
			w = prev_w if prev_w != Vector3.ZERO else tan.cross(Vector3.UP if absf(tan.y) < 0.9 else Vector3.RIGHT)
		w = w.normalized()
		prev_w = w
		var nrm := w.cross(tan).normalized()
		for side in 2:
			verts.append(p + w * ((float(side) - 0.5) * width))
			normals.append(nrm)
			uvs.append(Vector2(t, float(side)))
	for k in n:
		var i := base + 2 * k
		_tri(verts, normals, indices, i, i + 1, i + 3)
		_tri(verts, normals, indices, i, i + 3, i + 2)


static func build_tube(a: Vector3, b: Vector3, height: float, radius: float, segments := 48,
		radial := 5, up := Vector3.UP) -> ArrayMesh:
	var n := maxi(segments, 1)
	var m := maxi(radial, 3)
	var plane_n := (b - a).cross(bulge_dir(a, b, up)).normalized()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in n + 1:
		var t := float(k) / float(n)
		var p := arc_point(a, b, height, t, up)
		var tan := arc_tangent(a, b, height, t, up)
		var e1 := (plane_n - tan * plane_n.dot(tan)).normalized()
		var e2 := tan.cross(e1).normalized()
		for j in m + 1:
			var ang := TAU * float(j) / float(m)
			var dir := e1 * cos(ang) + e2 * sin(ang)
			verts.append(p + dir * radius)
			normals.append(dir)
			uvs.append(Vector2(t, float(j) / float(m)))
	var row := m + 1
	for k in n:
		for j in m:
			var i0 := k * row + j
			_tri(verts, normals, indices, i0, i0 + 1, i0 + row + 1)
			_tri(verts, normals, indices, i0, i0 + row + 1, i0 + row)
	return _commit(verts, normals, uvs, indices)


static func _tri(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		i0: int, i1: int, i2: int) -> void:
	var g := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
	if g.dot(normals[i0] + normals[i1] + normals[i2]) > 0.0:
		indices.append_array(PackedInt32Array([i0, i2, i1]))
	else:
		indices.append_array(PackedInt32Array([i0, i1, i2]))


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
