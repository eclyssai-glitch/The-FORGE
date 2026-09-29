extends GutTest
## MeshBuilder: counts, unit normals, winding vs normals, no degenerate triangles, AABB, UVs.

const EPS := 1e-4


## Structural checks shared by every builder. Returns the surface arrays.
func _check_mesh(mesh: ArrayMesh, label: String) -> Array:
	assert_not_null(mesh, label)
	assert_eq(mesh.get_surface_count(), 1, "%s single surface" % label)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_gt(verts.size(), 0, "%s has vertices" % label)
	assert_gt(idx.size(), 0, "%s has indices" % label)
	assert_eq(idx.size() % 3, 0, "%s triangle list" % label)
	assert_eq(normals.size(), verts.size(), "%s normal per vertex" % label)
	assert_eq(uvs.size(), verts.size(), "%s uv per vertex" % label)
	var bad_normals := 0
	for n in normals:
		if absf(n.length() - 1.0) > 1e-3:
			bad_normals += 1
	assert_eq(bad_normals, 0, "%s normals are unit length" % label)
	var bad_uv := 0
	for uv in uvs:
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			bad_uv += 1
	assert_eq(bad_uv, 0, "%s UVs in [0,1]" % label)
	var degenerate := 0
	var wrong_winding := 0
	for t in floori(idx.size() / 3.0):
		var a := verts[idx[3 * t]]
		var b := verts[idx[3 * t + 1]]
		var c := verts[idx[3 * t + 2]]
		var g := (b - a).cross(c - a)
		if g.length() * 0.5 < 1e-8:
			degenerate += 1
			continue
		var n := normals[idx[3 * t]] + normals[idx[3 * t + 1]] + normals[idx[3 * t + 2]]
		# Godot front faces are clockwise: (b-a)x(c-a) points against the outward normal.
		if g.dot(n) >= 0.0:
			wrong_winding += 1
	assert_eq(degenerate, 0, "%s has no degenerate triangles" % label)
	assert_eq(wrong_winding, 0, "%s winding agrees with normals" % label)
	return arrays


func _tri_count(arrays: Array) -> int:
	return floori((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3.0)


func _vert_count(arrays: Array) -> int:
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _assert_aabb(actual: AABB, expected: AABB, label: String, tol := 1e-3) -> void:
	assert_almost_eq(actual.position, expected.position, Vector3.ONE * tol, "%s AABB position" % label)
	assert_almost_eq(actual.end, expected.end, Vector3.ONE * tol, "%s AABB end" % label)


func test_annular_segment_structure_counts_and_aabb() -> void:
	var r_in := 1.4
	var r_out := 2.2
	var h := 0.2
	var span := 0.35
	var mesh := MeshBuilder.annular_segment(r_in, r_out, h, span, 6)
	var arrays := _check_mesh(mesh, "annular_segment")
	assert_eq(_vert_count(arrays), 8 * 7 + 8)
	assert_eq(_tri_count(arrays), 8 * 6 + 4)
	var half := span * 0.5
	var expected := AABB(Vector3(-r_out * sin(half), -h * 0.5, r_in * cos(half)),
		Vector3(2.0 * r_out * sin(half), h, r_out - r_in * cos(half)))
	_assert_aabb(mesh.get_aabb(), expected, "annular_segment")


func test_annular_segment_centred_on_positive_z() -> void:
	var mesh := MeshBuilder.annular_segment(1.3, 2.0, 0.2, 0.4, 4)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var centre := Vector3.ZERO
	for v in verts:
		centre += v
		assert_gt(v.z, 0.0, "segment lies on +Z")
	centre /= verts.size()
	assert_almost_eq(centre.x, 0.0, EPS, "symmetric about the Z axis")


func test_annular_segment_uv_runs_along_arc() -> void:
	var mesh := MeshBuilder.annular_segment(1.3, 2.0, 0.2, 0.4, 4)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var checked := 0
	for i in verts.size():
		if normals[i].y > 0.999:
			checked += 1
			var a := atan2(verts[i].x, verts[i].z)
			assert_almost_eq(uvs[i].x, (a + 0.2) / 0.4, 1e-3, "top u follows the arc")
			var r := Vector2(verts[i].x, verts[i].z).length()
			assert_almost_eq(uvs[i].y, (r - 1.3) / 0.7, 1e-3, "top v is radial")
	assert_eq(checked, 2 * 5, "top face vertices found")


func test_blueprint_segment_meshes_valid_for_every_layer() -> void:
	var bp := StructureBlueprint.build()
	for k in bp.layers.size():
		var p := bp.segment_mesh_params(k)
		var mesh := MeshBuilder.annular_segment(p["r_in"], p["r_out"], p["height"], p["angle_span"],
			p["arc_steps"])
		_check_mesh(mesh, "layer %d segment" % k)
		var aabb := mesh.get_aabb()
		assert_almost_eq(aabb.end.z, float(p["r_out"]), 1e-3)
		assert_almost_eq(aabb.size.y, float(p["height"]), 1e-3)


func test_icosphere_flat_counts_radius_and_colours() -> void:
	for s in 3:
		var mesh := MeshBuilder.icosphere(0.55, s, true)
		var arrays := _check_mesh(mesh, "icosphere flat s%d" % s)
		var tris := 20 * int(pow(4, s))
		assert_eq(_tri_count(arrays), tris)
		assert_eq(_vert_count(arrays), tris * 3)
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			assert_almost_eq(v.length(), 0.55, 1e-4)
		assert_eq((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size(), tris * 3,
			"barycentric colours")
		var aabb := mesh.get_aabb()
		assert_lte(aabb.end.x, 0.55 + EPS)
		assert_gte(aabb.position.y, -0.55 - EPS)
		assert_gt(aabb.size.x, 0.55 * 1.6)


func test_icosphere_smooth_shares_vertices() -> void:
	var mesh := MeshBuilder.icosphere(1.0, 2, false)
	var arrays := _check_mesh(mesh, "icosphere smooth")
	assert_eq(_tri_count(arrays), 320)
	assert_eq(_vert_count(arrays), 162)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		assert_almost_eq(normals[i], verts[i].normalized(), Vector3.ONE * 2e-3)
	_assert_aabb(mesh.get_aabb(), AABB(-Vector3.ONE, Vector3.ONE * 2.0), "icosphere smooth", 0.06)


func test_ring_counts_and_aabb() -> void:
	var mesh := MeshBuilder.ring(3.4, 0.04, 0.03, 128)
	var arrays := _check_mesh(mesh, "ring")
	assert_eq(_vert_count(arrays), 8 * 129)
	assert_eq(_tri_count(arrays), 8 * 128)
	var r := 3.42
	_assert_aabb(mesh.get_aabb(), AABB(Vector3(-r, -0.015, -r), Vector3(2 * r, 0.03, 2 * r)), "ring")
	var low := MeshBuilder.ring(1.0, 0.1, 0.1, 3)
	_check_mesh(low, "ring low")


func test_rib_counts_taper_and_aabb() -> void:
	var mesh := MeshBuilder.rib(4.2, 0.06, 0.08)
	var arrays := _check_mesh(mesh, "rib")
	assert_eq(_vert_count(arrays), 16 * MeshBuilder.RIB_STEPS + 8)
	assert_eq(_tri_count(arrays), 8 * MeshBuilder.RIB_STEPS + 4)
	_assert_aabb(mesh.get_aabb(), AABB(Vector3(-0.03, -2.1, -0.04), Vector3(0.06, 4.2, 0.08)), "rib")
	var tip_half_width := 0.0
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		if is_equal_approx(v.y, 2.1):
			tip_half_width = maxf(tip_half_width, absf(v.x))
	assert_almost_eq(tip_half_width, 0.03 * MeshBuilder.RIB_TIP, 1e-4, "tips are thinner")
	assert_lt(tip_half_width, 0.03)


func test_shard_deterministic_and_bounded() -> void:
	var a := MeshBuilder.shard(0.4, 11)
	var b := MeshBuilder.shard(0.4, 11)
	var c := MeshBuilder.shard(0.4, 12)
	var arrays := _check_mesh(a, "shard")
	assert_eq(_vert_count(arrays), 18)
	assert_eq(_tri_count(arrays), 6)
	assert_eq(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	assert_ne(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], c.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var aabb := a.get_aabb()
	assert_lte(aabb.size.y, 0.4 + EPS)
	assert_gte(aabb.size.y, 0.4 * 0.5)
	assert_lte(maxf(aabb.size.x, aabb.size.z), 0.4 * 0.5)
	assert_true(aabb.has_point(Vector3.ZERO), "roughly centred")
	for s in 20:
		_check_mesh(MeshBuilder.shard(0.3, 1000 + s), "shard seed %d" % s)
