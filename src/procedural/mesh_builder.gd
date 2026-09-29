class_name MeshBuilder
extends RefCounted
## Static procedural mesh builders. Every function returns a fresh single-surface ArrayMesh
## (PRIMITIVE_TRIANGLES, indexed) with unit normals, UVs in [0, 1] and front faces wound for
## Godot (clockwise seen from the front). Build meshes once and reuse them; never per frame.
##
## Conventions shared by all builders (see docs/PROCEDURAL.md for counts and dimensions):
## - Y is up. Meshes are centred on their local origin unless stated otherwise.
## - Hard edges are split (separate vertices) so shading stays crisp on architectural edges;
##   curved walls keep smooth normals along the curve.
## - Angles around Y are measured from +Z towards +X: a point at angle `a` and radius `r` sits at
##   (r·sin a, y, r·cos a). This is exactly what `Basis(Vector3.UP, a)` does to the +Z axis, so a
##   mesh built around +Z is placed at angle `a` by a pure Y rotation.
## - Faceted meshes (`icosphere(flat = true)`, `shard`) also carry barycentric vertex colours
##   (1,0,0)/(0,1,0)/(0,0,1) per triangle in ARRAY_COLOR so shaders can draw facet edges.


## Minimal geometry accumulator. `tri` fixes the winding from the vertex normals, so callers only
## need to supply correct outward normals.
class Geo extends RefCounted:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var use_colors := false

	func v(p: Vector3, n: Vector3, uv: Vector2, color := Color.WHITE) -> int:
		verts.append(p)
		normals.append(n.normalized())
		uvs.append(Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0)))
		colors.append(color)
		return verts.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		var n := normals[a] + normals[b] + normals[c]
		# Godot front face: clockwise seen from the front, i.e. (b-a)x(c-a) points inwards.
		if g.dot(n) > 0.0:
			indices.append(a)
			indices.append(c)
			indices.append(b)
		else:
			indices.append(a)
			indices.append(b)
			indices.append(c)

	## Quad a-b-c-d given in perimeter order (either direction).
	func quad(a: int, b: int, c: int, d: int) -> void:
		tri(a, b, c)
		tri(a, c, d)

	## Flat triangle from positions; the normal is oriented away from `inside`.
	func flat_tri(p0: Vector3, p1: Vector3, p2: Vector3, inside: Vector3,
			uv0: Vector2, uv1: Vector2, uv2: Vector2) -> void:
		var n := (p1 - p0).cross(p2 - p0).normalized()
		if n.dot((p0 + p1 + p2) / 3.0 - inside) < 0.0:
			n = -n
		var a := v(p0, n, uv0, Color(1, 0, 0))
		var b := v(p1, n, uv1, Color(0, 1, 0))
		var c := v(p2, n, uv2, Color(0, 0, 1))
		tri(a, b, c)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		if use_colors:
			arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func _polar(r: float, a: float, y: float) -> Vector3:
	return Vector3(r * sin(a), y, r * cos(a))


static func _radial(a: float) -> Vector3:
	return Vector3(sin(a), 0.0, cos(a))


## Annular sector (one segment of a segmented ring).
## Orientation: centred on angle 0, i.e. on the +Z axis, spanning angles
## [-angle_span/2, +angle_span/2] (the +u / "end" side lies towards +X). Radially it occupies
## r_in..r_out from the local origin (the origin is the ring axis, not the segment centroid,
## whose local position is ~(0, 0, (r_in + r_out)/2)). Vertically y ∈ [-height/2, +height/2].
## Faces: top, bottom, outer wall, inner wall, two side caps. Normals are flat on every edge and
## smooth along the arc on the curved walls.
## UV: top/bottom u = along the arc (0 at -span/2 → 1 at +span/2), v = radial (0 inner → 1 outer);
## walls u = along the arc, v = vertical (0 bottom → 1 top); side caps u = radial, v = vertical.
## Counts: vertices = 8·(arc_steps+1) + 8, triangles = 8·arc_steps + 4.
static func annular_segment(r_in: float, r_out: float, height: float, angle_span: float,
		arc_steps := 6) -> ArrayMesh:
	var g := Geo.new()
	var steps := maxi(arc_steps, 1)
	var h2 := height * 0.5
	var half := angle_span * 0.5
	for face in 4:
		# 0 = top, 1 = bottom, 2 = outer wall, 3 = inner wall.
		var row: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
		for s in steps + 1:
			var u := float(s) / float(steps)
			var a := -half + angle_span * u
			match face:
				0:
					row[0].append(g.v(_polar(r_in, a, h2), Vector3.UP, Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_out, a, h2), Vector3.UP, Vector2(u, 1.0)))
				1:
					row[0].append(g.v(_polar(r_in, a, -h2), Vector3.DOWN, Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_out, a, -h2), Vector3.DOWN, Vector2(u, 1.0)))
				2:
					row[0].append(g.v(_polar(r_out, a, -h2), _radial(a), Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_out, a, h2), _radial(a), Vector2(u, 1.0)))
				3:
					row[0].append(g.v(_polar(r_in, a, -h2), -_radial(a), Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_in, a, h2), -_radial(a), Vector2(u, 1.0)))
		for s in steps:
			g.quad(row[0][s], row[0][s + 1], row[1][s + 1], row[1][s])
	for side: float in [-1.0, 1.0]:
		var a := half * side
		# Tangent d/da of the arc is (cos a, 0, -sin a); the cap faces away from the segment.
		var n := Vector3(cos(a), 0.0, -sin(a)) * side
		var i0 := g.v(_polar(r_in, a, -h2), n, Vector2(0.0, 0.0))
		var i1 := g.v(_polar(r_out, a, -h2), n, Vector2(1.0, 0.0))
		var i2 := g.v(_polar(r_out, a, h2), n, Vector2(1.0, 1.0))
		var i3 := g.v(_polar(r_in, a, h2), n, Vector2(0.0, 1.0))
		g.quad(i0, i1, i2, i3)
	return g.commit()


## Icosphere of `radius` centred on the origin; `subdivisions` ≥ 0 (triangles = 20·4^s).
## flat = true: faceted shell, 3 unique vertices per triangle with the face normal, per-facet UV
## (0,0)/(1,0)/(0.5,1) and barycentric vertex colours. flat = false: shared vertices, smooth
## radial normals, spherical UV (u = longitude, v = latitude from the top).
static func icosphere(radius: float, subdivisions: int, flat := true) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var pts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in pts.size():
		pts[i] = pts[i].normalized()
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10),
		Vector3i(0, 10, 11), Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2),
		Vector3i(10, 7, 6), Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2),
		Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9), Vector3i(4, 9, 5),
		Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	for _s in maxi(subdivisions, 0):
		var cache := {}
		var next: Array[Vector3i] = []
		for f in faces:
			var ab := _midpoint(pts, cache, f.x, f.y)
			var bc := _midpoint(pts, cache, f.y, f.z)
			var ca := _midpoint(pts, cache, f.z, f.x)
			next.append(Vector3i(f.x, ab, ca))
			next.append(Vector3i(f.y, bc, ab))
			next.append(Vector3i(f.z, ca, bc))
			next.append(Vector3i(ab, bc, ca))
		faces = next
	var g := Geo.new()
	if flat:
		g.use_colors = true
		for f in faces:
			g.flat_tri(pts[f.x] * radius, pts[f.y] * radius, pts[f.z] * radius, Vector3.ZERO,
				Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0))
	else:
		for p in pts:
			var uv := Vector2(atan2(p.x, p.z) / TAU + 0.5, acos(clampf(p.y, -1.0, 1.0)) / PI)
			g.v(p * radius, p, uv)
		for f in faces:
			g.tri(f.x, f.y, f.z)
	return g.commit()


static func _midpoint(pts: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	pts.append(((pts[a] + pts[b]) * 0.5).normalized())
	cache[key] = pts.size() - 1
	return pts.size() - 1


## Thin ring (torus of rectangular section) around the Y axis, centred on the origin.
## radius = centre-line radius; thickness = radial extent (radius ± thickness/2);
## width = vertical extent (y ∈ ±width/2). Faces: top, bottom, outer, inner; flat edges, smooth
## around the circumference. UV: u = around the ring (0..1 from +Z towards +X), v across the face
## (radial on top/bottom, vertical on walls).
## Counts: vertices = 8·(segments+1), triangles = 8·segments.
static func ring(radius: float, thickness: float, width: float, segments := 128) -> ArrayMesh:
	var g := Geo.new()
	var n_seg := maxi(segments, 3)
	var r_in := radius - thickness * 0.5
	var r_out := radius + thickness * 0.5
	var h2 := width * 0.5
	for face in 4:
		var row: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
		for s in n_seg + 1:
			var u := float(s) / float(n_seg)
			var a := TAU * u
			match face:
				0:
					row[0].append(g.v(_polar(r_in, a, h2), Vector3.UP, Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_out, a, h2), Vector3.UP, Vector2(u, 1.0)))
				1:
					row[0].append(g.v(_polar(r_in, a, -h2), Vector3.DOWN, Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_out, a, -h2), Vector3.DOWN, Vector2(u, 1.0)))
				2:
					row[0].append(g.v(_polar(r_out, a, -h2), _radial(a), Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_out, a, h2), _radial(a), Vector2(u, 1.0)))
				3:
					row[0].append(g.v(_polar(r_in, a, -h2), -_radial(a), Vector2(u, 0.0)))
					row[1].append(g.v(_polar(r_in, a, h2), -_radial(a), Vector2(u, 1.0)))
		for s in n_seg:
			g.quad(row[0][s], row[0][s + 1], row[1][s + 1], row[1][s])
	return g.commit()


## Number of vertical steps used by `rib`.
const RIB_STEPS := 12
## Relative thickness of a rib at its tips (1.0 at mid-height).
const RIB_TIP := 0.5


## Tapered vertical blade centred on the origin: y ∈ ±height/2, x ∈ ±width/2 (tangent),
## z ∈ [-depth/2, +depth/2]. The +Z face (the "back") is flat and vertical so it can sit against
## a surface; width and the -Z extent taper towards both tips (profile RIB_TIP → 1 → RIB_TIP,
## cosine), giving a slim lens-like blade. Flat-shaded facets.
## UV: side faces u across the face, v = vertical (0 bottom → 1 top); caps u,v across.
## Counts: vertices = 16·RIB_STEPS + 8, triangles = 8·RIB_STEPS + 4.
static func rib(height: float, width: float, depth: float) -> ArrayMesh:
	var g := Geo.new()
	var rows: Array[PackedVector3Array] = []  # per step: 4 corners (-x-z, +x-z, +x+z, -x+z)
	var vs: PackedFloat32Array = []
	for s in RIB_STEPS + 1:
		var v := float(s) / float(RIB_STEPS)
		var y := (v - 0.5) * height
		var f := RIB_TIP + (1.0 - RIB_TIP) * cos((v - 0.5) * PI)
		var hw := width * 0.5 * f
		var zb := depth * 0.5
		var zf := zb - depth * f
		rows.append(PackedVector3Array([
			Vector3(-hw, y, zf), Vector3(hw, y, zf), Vector3(hw, y, zb), Vector3(-hw, y, zb)]))
		vs.append(v)
	for s in RIB_STEPS:
		var lo := rows[s]
		var hi := rows[s + 1]
		for side in 4:
			var a := lo[side]
			var b := lo[(side + 1) % 4]
			var c := hi[(side + 1) % 4]
			var d := hi[side]
			var n := (b - a).cross(d - a).normalized()
			var inside := (lo[0] + lo[2] + hi[0] + hi[2]) * 0.25  # slab centroid
			if n.dot((a + b + c + d) * 0.25 - inside) < 0.0:
				n = -n
			g.quad(g.v(a, n, Vector2(0.0, vs[s])), g.v(b, n, Vector2(1.0, vs[s])),
				g.v(c, n, Vector2(1.0, vs[s + 1])), g.v(d, n, Vector2(0.0, vs[s + 1])))
	for cap in 2:
		var r := rows[0] if cap == 0 else rows[RIB_STEPS]
		var n := Vector3.DOWN if cap == 0 else Vector3.UP
		g.quad(g.v(r[0], n, Vector2(0, 0)), g.v(r[1], n, Vector2(1, 0)),
			g.v(r[2], n, Vector2(1, 1)), g.v(r[3], n, Vector2(0, 1)))
	return g.commit()


## Irregular crystalline shard (jittered triangular bipyramid), roughly `size` long along Y and
## ~0.4·size across, centred on the origin. Deterministic for a given seed. Flat facets with
## barycentric vertex colours, per-facet UV. Counts: 18 vertices, 6 triangles.
@warning_ignore("shadowed_global_identifier")
static func shard(size: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ring_pts: Array[Vector3] = []
	var start := rng.randf_range(0.0, TAU)
	for k in 3:
		var a := start + TAU * float(k) / 3.0 + rng.randf_range(-0.35, 0.35)
		var r := size * rng.randf_range(0.14, 0.22)
		ring_pts.append(Vector3(r * sin(a), size * rng.randf_range(-0.08, 0.08), r * cos(a)))
	var top := Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.3, 0.5),
		rng.randf_range(-0.06, 0.06)) * size
	var bottom := Vector3(rng.randf_range(-0.06, 0.06), -rng.randf_range(0.2, 0.4),
		rng.randf_range(-0.06, 0.06)) * size
	var centre := (ring_pts[0] + ring_pts[1] + ring_pts[2]) / 3.0
	var g := Geo.new()
	g.use_colors = true
	for k in 3:
		var p := ring_pts[k]
		var q := ring_pts[(k + 1) % 3]
		g.flat_tri(p, q, top, centre, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
		g.flat_tri(p, q, bottom, centre, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
	return g.commit()
