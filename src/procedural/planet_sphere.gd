class_name PlanetSphere
extends RefCounted
## UV sphere for planets and moons, with analytic normals and tangents.
## Position = r * (sin(theta) sin(phi), cos(theta), sin(theta) cos(phi)); phi from +Z towards +X.
## UV.x = phi / TAU (seam column duplicated, 0 -> 1), UV.y = theta / PI (0 north pole, 1 south).
## TANGENT = d/dphi (direction of increasing UV.x), w = +1 (same as SurfaceTool.generate_tangents,
## checked in the tests). Pole rows emit one triangle per sector
## (no degenerate triangles).

## (sectors, rings) per QualityProfiles.Level (LOW, MEDIUM, HIGH, ULTRA).
const SEGMENTS_BY_LEVEL: Array[Vector2i] = [Vector2i(48, 24), Vector2i(64, 32), Vector2i(96, 48),
	Vector2i(128, 64)]


static func segments_for_level(level: int) -> Vector2i:
	return SEGMENTS_BY_LEVEL[clampi(level, 0, SEGMENTS_BY_LEVEL.size() - 1)]


static func build_for_level(radius: float, level: int) -> ArrayMesh:
	var s := segments_for_level(level)
	return build(radius, s.x, s.y)


static func triangle_count(sectors: int, rings: int) -> int:
	return 2 * sectors * (rings - 1)


static func build(radius: float, sectors := 96, rings := 48) -> ArrayMesh:
	var ns := maxi(sectors, 3)
	var nr := maxi(rings, 2)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for r in nr + 1:
		var v := float(r) / float(nr)
		var theta := PI * v
		for s in ns + 1:
			var u := float(s) / float(ns)
			var phi := TAU * u
			var n := Vector3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
			if r == 0:
				n = Vector3.UP
			elif r == nr:
				n = Vector3.DOWN
			verts.append(n * radius)
			normals.append(n)
			var t := Vector3(cos(phi), 0.0, -sin(phi))
			tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
			uvs.append(Vector2(u, v))
	var row := ns + 1
	for r in nr:
		for s in ns:
			var a := r * row + s
			var b := a + 1
			var c := a + row
			var d := c + 1
			# clockwise seen from outside (Godot front face)
			if r != 0:
				indices.append_array(PackedInt32Array([a, b, d]))
			if r != nr - 1:
				indices.append_array(PackedInt32Array([a, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
