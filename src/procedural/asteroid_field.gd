class_name AsteroidField
extends RefCounted
## Memory belt: deterministic asteroid transforms in a flat ring around the local Y axis, plus an
## irregular low-poly rock mesh per seed. Everything depends only on the arguments (seeded RNG).
## - `transforms`: radius uniform in *area* between inner and outer radius, height with a soft
##   (triangular) distribution inside +-thickness/2, uniform random rotation (Shoemake),
##   uniform scale with a power-law bias (many small rocks, few large).
## - `build_multimesh`: MultiMesh (TRANSFORM_3D) holding a mesh and those transforms.
## - `rock_mesh`: faceted, squashed and dented icosphere; flat normals (split vertices),
##   per-face UV (0,0)(1,0)(0.5,1) and barycentric vertex colours (like MeshBuilder facets).

static func transforms(count: int, inner_radius: float, outer_radius: float, thickness: float,
		seed: int, min_scale := 0.05, max_scale := 0.4, scale_bias := 3.0) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Transform3D] = []
	var r2_in := inner_radius * inner_radius
	var r2_out := outer_radius * outer_radius
	for i in count:
		var ang := rng.randf() * TAU
		var r := sqrt(lerpf(r2_in, r2_out, rng.randf()))
		var y := (rng.randf() - rng.randf()) * 0.5 * thickness
		var pos := Vector3(r * sin(ang), y, r * cos(ang))
		var q := _random_quat(rng)
		var s := lerpf(min_scale, max_scale, pow(rng.randf(), scale_bias))
		out.append(Transform3D(Basis(q).scaled(Vector3.ONE * s), pos))
	return out


static func build_multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	return mm


static func rock_mesh(seed: int, radius := 1.0, subdivisions := 1, roughness := 0.3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var t := (1.0 + sqrt(5.0)) * 0.5
	var pts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in pts.size():
		pts[i] = pts[i].normalized()
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for _s in clampi(subdivisions, 0, 3):
		var mids := {}
		var next: Array[Vector3i] = []
		for f in faces:
			var ab := _mid(pts, mids, f.x, f.y)
			var bc := _mid(pts, mids, f.y, f.z)
			var ca := _mid(pts, mids, f.z, f.x)
			next.append_array([Vector3i(f.x, ab, ca), Vector3i(f.y, bc, ab), Vector3i(f.z, ca, bc),
				Vector3i(ab, bc, ca)])
		faces = next
	# shape: squash to an ellipsoid, then dent each vertex radially (deterministic order)
	var axes := Vector3(rng.randf_range(0.75, 1.15), rng.randf_range(0.55, 0.85), rng.randf_range(0.8, 1.2))
	var dents: Array[Vector3] = []
	for _d in 3:
		dents.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
	for i in pts.size():
		var p := pts[i]
		var k := 1.0 + rng.randf_range(-roughness, roughness * 0.5)
		for d in dents:
			k -= roughness * 0.8 * maxf(p.dot(d) - 0.72, 0.0) / 0.28
		pts[i] = p * axes * k * radius
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for f in faces:
		var a := pts[f.x]
		var b := pts[f.y]
		var c := pts[f.z]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(a + b + c) < 0.0:
			n = -n
		var base := verts.size()
		verts.append_array(PackedVector3Array([a, b, c]))
		normals.append_array(PackedVector3Array([n, n, n]))
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]))
		colors.append_array(PackedColorArray([Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]))
		# clockwise seen from outside
		if (b - a).cross(c - a).dot(n) > 0.0:
			indices.append_array(PackedInt32Array([base, base + 2, base + 1]))
		else:
			indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _mid(pts: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	pts.append(((pts[a] + pts[b]) * 0.5).normalized())
	cache[key] = pts.size() - 1
	return pts.size() - 1


## Uniformly distributed rotation (Shoemake 1992).
static func _random_quat(rng: RandomNumberGenerator) -> Quaternion:
	var u1 := rng.randf()
	var u2 := rng.randf() * TAU
	var u3 := rng.randf() * TAU
	var a := sqrt(1.0 - u1)
	var b := sqrt(u1)
	return Quaternion(a * sin(u2), a * cos(u2), b * sin(u3), b * cos(u3)).normalized()
