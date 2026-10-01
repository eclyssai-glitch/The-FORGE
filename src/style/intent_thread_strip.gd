class_name IntentThreadStrip
extends RefCounted
## Reference encoder of the intent_thread() mesh contract (owner: art-director; the thread's owner may
## use it or write the same layout itself). The material widens a centre-line strip on screen, so
## the mesh carries no width: for every curve sample P_i (origin first) two vertices at P_i with
## UV (u_i, 0) / (u_i, 1) — u by arc length, 0 at the origin, 1 at the hand — and NORMAL = the curve
## tangent at P_i. Rewriting an ImmediateMesh each frame is cheap for the few dozen samples a thread
## needs.

## Margin (world units) added around the curve's AABB: the ribbon is widened on screen.
const AABB_MARGIN := 0.08


## Clears `mesh` and writes the strip of `points` (local space of the thread's MeshInstance3D) with
## `material`. Fewer than 2 points leave the mesh empty. Returns the AABB to set as custom_aabb.
static func fill(mesh: ImmediateMesh, points: PackedVector3Array, material: Material) -> AABB:
	mesh.clear_surfaces()
	var n := points.size()
	if n < 2:
		return AABB()
	var lengths := arc_lengths(points)
	var total := maxf(lengths[n - 1], 1e-6)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	var box := AABB(points[0], Vector3.ZERO)
	for i in n:
		var t := tangent(points, i)
		var u := lengths[i] / total
		for side in 2:
			mesh.surface_set_normal(t)
			mesh.surface_set_uv(Vector2(u, float(side)))
			mesh.surface_add_vertex(points[i])
		box = box.expand(points[i])
	mesh.surface_end()
	return box.grow(AABB_MARGIN)


## Cumulative arc length at every sample (0 at the first).
static func arc_lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(points.size())
	var acc := 0.0
	for i in points.size():
		if i > 0:
			acc += points[i].distance_to(points[i - 1])
		out[i] = acc
	return out


## Unit tangent at sample `i` (central difference; ends use the one-sided one). Never null: a
## degenerate curve falls back to +Y.
static func tangent(points: PackedVector3Array, i: int) -> Vector3:
	var a := points[maxi(i - 1, 0)]
	var b := points[mini(i + 1, points.size() - 1)]
	var d := b - a
	return d / d.length() if d.length() > 1e-6 else Vector3.UP
