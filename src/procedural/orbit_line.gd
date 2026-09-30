class_name OrbitLine
extends RefCounted
## Orbit guides: an ellipse (or circle) in the local XZ plane, centred on the origin.
## Phase p in [0, 1] maps to the angle a = TAU * p measured from +Z towards +X (project
## convention), so `point(rx, rz, p)` = (rx * sin a, 0, rz * cos a).
## - `build` : thin flat band (triangles), UV.x = phase (seam duplicated so it reaches 1),
##             UV.y = 0 on the inner edge, 1 on the outer edge; normal +Y.
## - `build_line`: PRIMITIVE_LINE_STRIP through `segments + 1` points (closed), UV.x = phase.
## - `build_tube`: thin tube around the ellipse (reads at grazing angles, where a flat band
##                 vanishes), UV.x = phase, UV.y = 0 -> 1 around the section.

static func point(radius_x: float, radius_z: float, phase: float) -> Vector3:
	var a := TAU * phase
	return Vector3(radius_x * sin(a), 0.0, radius_z * cos(a))


## Outward unit normal of the ellipse (in XZ) at `phase`.
static func outward(radius_x: float, radius_z: float, phase: float) -> Vector3:
	var a := TAU * phase
	var n := Vector3(sin(a) / maxf(radius_x, 1e-6), 0.0, cos(a) / maxf(radius_z, 1e-6))
	return n.normalized()


static func build(radius_x: float, radius_z: float, width: float, segments := 256) -> ArrayMesh:
	var segs := maxi(segments, 3)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in segs + 1:
		var p := float(k) / float(segs)
		var c := point(radius_x, radius_z, p)
		var o := outward(radius_x, radius_z, p)
		verts.append(c - o * width * 0.5)
		verts.append(c + o * width * 0.5)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(p, 0.0))
		uvs.append(Vector2(p, 1.0))
	for k in segs:
		var a := 2 * k
		# seen from +Y, inner(k) -> outer(k) -> outer(k+1) turns clockwise for increasing phase
		for tri in [[a, a + 1, a + 3], [a, a + 3, a + 2]]:
			var i0: int = tri[0]
			var i1: int = tri[1]
			var i2: int = tri[2]
			var g := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
			if g.y > 0.0:
				indices.append_array(PackedInt32Array([i0, i2, i1]))
			else:
				indices.append_array(PackedInt32Array([i0, i1, i2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func build_line(radius_x: float, radius_z: float, segments := 256) -> ArrayMesh:
	var segs := maxi(segments, 3)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for k in segs + 1:
		var p := float(k) / float(segs)
		verts.append(point(radius_x, radius_z, p))
		uvs.append(Vector2(p, 0.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return mesh


static func build_tube(radius_x: float, radius_z: float, radius: float, segments := 256,
		radial := 4) -> ArrayMesh:
	var segs := maxi(segments, 3)
	var m := maxi(radial, 3)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in segs + 1:
		var p := float(k) / float(segs)
		var c := point(radius_x, radius_z, p)
		var o := outward(radius_x, radius_z, p)
		for j in m + 1:
			var ang := TAU * float(j) / float(m)
			var dir := o * cos(ang) + Vector3.UP * sin(ang)
			verts.append(c + dir * radius)
			normals.append(dir)
			uvs.append(Vector2(p, float(j) / float(m)))
	var row := m + 1
	for k in segs:
		for j in m:
			var i0 := k * row + j
			for tri in [[i0, i0 + 1, i0 + row + 1], [i0, i0 + row + 1, i0 + row]]:
				var a: int = tri[0]
				var b: int = tri[1]
				var c: int = tri[2]
				var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
				if g.dot(normals[a] + normals[b] + normals[c]) > 0.0:
					indices.append_array(PackedInt32Array([a, c, b]))
				else:
					indices.append_array(PackedInt32Array([a, b, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
