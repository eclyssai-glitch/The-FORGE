class_name HairRibbons
extends RefCounted
## MIKU's hair as narrow ribbons generated at runtime from control-point curves.
##
## - `nebula` (Loop 4) makes the hair ONE nebula mass: a single root, tufts of 5–10 strands
##   rising in an S (back and up), varied lengths, tips opening into filaments, plus optional
##   long "link strands" that end exactly at given points (where the relation threads start).
##   `s_path` / `link_curve` are its building blocks.
## - `generate_curves` (legacy fan) makes N deterministic curves (seeded) that leave `hair_root`
##   along a direction (up/back) and flow in long waves.
## - `build` turns curves into one ArrayMesh of ribbons: UV.x runs along each strand 0 -> 1
##   (root -> tip, by arc length), UV.y across the ribbon 0 -> 1; width tapers to the tip.
##   UV2 = (strand index / (n - 1), per-strand hash in [0, 1]) for shader variation.
##   COLOR = white with alpha = strand opacity (per-strand 0.55..1, fading to 0 at the tip), as
##   MaterialLibrary.miku_hair() expects.
##   TANGENT follows the strand (for anisotropic highlights), NORMAL is the ribbon face normal.
##   `crossed = true` adds a second ribbon rotated 90 degrees around each strand (reads from
##   every angle; a flat ribbon vanishes edge-on). Both ribbons share UVs/colour.
##   CUSTOM0 (RGBA float) = (link strand 0/1, tuft share, length share, 0) for the shader.
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


## Link strands keep this share of their root width and opacity at the tip (a thread continues).
const LINK_TIP_RATIO := 0.55
const LINK_TIP_ALPHA := 0.8

## Defaults of `nebula` (any key may be overridden through its `options`).
const NEBULA_DEFAULTS := {
	"strands_min": 5, # strands per tuft (inclusive range)
	"strands_max": 10,
	"points": 12, # control points per strand
	"spread": 0.38, # half-angle (rad) of the cone the tuft headings fan in
	"lift": 0.75, # how far the heading turns from `direction` towards world up by the tip (rad)
	"s_amount": 0.42, # S undulation of the heading (rad): first up, then back, then up again
	"length_range": Vector2(0.55, 1.15), # tuft length share of `length`
	"strand_length_range": Vector2(0.6, 1.0), # strand length share of its tuft
	"root_radius": 0.035, # every strand starts within this radius of the single root
	"tip_open": 0.13, # how far apart the strands of a tuft spread at the tip (share of length)
	"wave": 0.05, # small per-strand lateral wave (share of length)
}


## Hair as ONE nebula mass (Loop 4): every strand starts at the single `root`, leaves along
## `direction` (back) and rises in an S (back, up, back, up: the heading turns towards world up by
## `lift` with an S undulation of `s_amount`); strands are grouped in `tufts` tufts of 5–10 that
## share a path, have varied lengths and open like filaments towards their tips.
## `link_ends` (object space, same frame as `root`) adds one long "link strand" per point: it
## leaves the root inside the tuft whose tip heads closest to that point, follows the tuft's S and
## bends smoothly to end EXACTLY at the point (the hair -> graph continuity: a relation thread
## starts where the link strand ends).
## Returns {"curves": Array[PackedVector3Array], "links": PackedInt32Array (indices of the link
## strands in curves, in the order of link_ends), "groups": PackedInt32Array (tuft of each curve)}.
## Pass "links" and "groups" to `build` so the mesh marks them (CUSTOM0). Deterministic per seed.
static func nebula(root: Vector3, direction: Vector3, seed: int, tufts := 9, length := 10.0,
		link_ends := PackedVector3Array(), options := {}) -> Dictionary:
	var o := NEBULA_DEFAULTS.duplicate()
	o.merge(options, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := direction.normalized()
	var side := _side_of(d)
	var up2 := side.cross(d).normalized()
	var curves: Array[PackedVector3Array] = []
	var groups := PackedInt32Array()
	var tuft_heads: Array[Vector3] = []
	var tuft_params: Array[Vector3] = [] # (length, phase, s sign/scale)
	var npts := int(o["points"])
	var lr: Vector2 = o["length_range"]
	var slr: Vector2 = o["strand_length_range"]
	for t in tufts:
		# tuft heading: fanned around `direction`, evenly by angle with jitter (no clumps)
		var ang := (float(t) + rng.randf_range(0.15, 0.85)) / float(maxi(tufts, 1)) * TAU
		var rad := float(o["spread"]) * sqrt(rng.randf_range(0.15, 1.0))
		var head := (d * cos(rad) + (side * cos(ang) + up2 * sin(ang)) * sin(rad)).normalized()
		var tl := length * rng.randf_range(lr.x, lr.y)
		var phase := rng.randf_range(-0.4, 0.4)
		var s_scale := rng.randf_range(0.7, 1.25)
		tuft_heads.append(head)
		tuft_params.append(Vector3(tl, phase, s_scale))
		var path := s_path(root, head, tl, npts, float(o["lift"]), float(o["s_amount"]) * s_scale, phase)
		var n := rng.randi_range(int(o["strands_min"]), int(o["strands_max"]))
		var t_side := _side_of(head)
		var t_up := t_side.cross(head).normalized()
		for s in n:
			var share := rng.randf_range(slr.x, slr.y)
			var a := rng.randf() * TAU
			var r0 := float(o["root_radius"]) * sqrt(rng.randf())
			var open_dir := (t_side * cos(a) + t_up * sin(a))
			var open := float(o["tip_open"]) * tl * rng.randf_range(0.35, 1.0)
			var w_amp := float(o["wave"]) * tl * rng.randf_range(0.4, 1.0)
			var w_ph := rng.randf() * TAU
			var pts := PackedVector3Array()
			for j in npts:
				var u := float(j) / float(npts - 1)
				var p := curve_point(path, u * share)
				# filaments: together at the root, opening (quadratically) towards the tip
				var spread_k := u * u
				p += open_dir * (r0 * (1.0 - u) + open * spread_k)
				p += t_side.rotated(head, w_ph) * sin(TAU * 1.3 * u + w_ph) * w_amp * u
				pts.append(p)
			curves.append(pts)
			groups.append(t)
	var links := PackedInt32Array()
	for e in link_ends:
		# the tuft whose tip heads most directly towards the end point
		var best := 0
		var best_dot := -2.0
		for t in tufts:
			var path_t := s_path(root, tuft_heads[t], tuft_params[t].x, npts, float(o["lift"]),
				float(o["s_amount"]) * tuft_params[t].z, tuft_params[t].y)
			var tip_dir := (path_t[path_t.size() - 1] - root).normalized()
			var dd := tip_dir.dot((e - root).normalized())
			if dd > best_dot:
				best_dot = dd
				best = t
		links.append(curves.size())
		curves.append(link_curve(root, tuft_heads[best] if tufts > 0 else d, e, npts + 4,
			float(o["lift"]), float(o["s_amount"]) * (tuft_params[best].z if tufts > 0 else 1.0),
			tuft_params[best].y if tufts > 0 else 0.0))
		groups.append(best)
	return {"curves": curves, "links": links, "groups": groups}


## One S-shaped path from `root` along `heading`: arc length `length`, `points` control points.
## The heading turns towards world up by `lift` (rad) along the way, with an S undulation of
## amplitude `s_amount` (rad) — up first, then back — shifted by `phase`.
static func s_path(root: Vector3, heading: Vector3, length: float, points: int, lift := 0.75,
		s_amount := 0.42, phase := 0.0) -> PackedVector3Array:
	var h0 := heading.normalized()
	# plane of the S: heading and the world up (falls back to any perpendicular when vertical)
	var axis := h0.cross(Vector3.UP)
	if axis.length() < 1e-4:
		axis = h0.cross(Vector3.RIGHT)
	axis = axis.normalized()
	var pts := PackedVector3Array()
	var pos := root
	var n := maxi(points, 2)
	var step := length / float(n - 1)
	pts.append(pos)
	for j in range(1, n):
		var u := (float(j) - 0.5) / float(n - 1)
		var theta := lift * u + s_amount * sin(TAU * u + phase)
		# rotating about h0 x UP by +theta turns the heading towards up
		pos += h0.rotated(axis, theta) * step
		pts.append(pos)
	return pts


## A link strand: leaves `root` along `heading` with the mass's S (same `lift`, `s_amount`,
## `phase`) and bends smoothly to end exactly at `end_point` (the tangent at the root is kept).
static func link_curve(root: Vector3, heading: Vector3, end_point: Vector3, points := 16,
		lift := 0.75, s_amount := 0.42, phase := 0.0) -> PackedVector3Array:
	var length := root.distance_to(end_point) * 1.15
	var path := s_path(root, heading, length, points, lift, s_amount, phase)
	var miss := end_point - path[path.size() - 1]
	var out := PackedVector3Array()
	for j in path.size():
		var u := float(j) / float(path.size() - 1)
		# smootherstep-squared: zero value and slope at the root, full correction at the tip
		var k := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
		out.append(path[j] + miss * k)
	return out


static func _side_of(d: Vector3) -> Vector3:
	var side := d.cross(Vector3.UP)
	if side.length() < 1e-4:
		side = d.cross(Vector3.RIGHT)
	return side.normalized()


## Ribbon mesh for all curves (one surface). `width` at the root, `tip_ratio` * width at the
## tip; `samples` points per strand; `facing` is the direction the ribbons face at the root
## (default: +Z, towards the default camera) and is then parallel-transported along each strand.
## `links` (indices into `curves`) marks link strands: they keep LINK_TIP_RATIO of their width
## and LINK_TIP_ALPHA of their opacity at the tip (a relation thread continues from there).
## `groups` (one tuft index per curve, optional) feeds CUSTOM0.g.
## CUSTOM0 (RGBA float, always present) = (1 for a link strand else 0, tuft index / (tufts - 1),
## strand length / longest strand, 0).
static func build(curves: Array[PackedVector3Array], width := 0.06, tip_ratio := 0.15,
		samples := 48, facing := Vector3.BACK, crossed := false, links := PackedInt32Array(),
		groups := PackedInt32Array()) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()
	var n_curves := curves.size()
	var max_group := 0
	for g in groups:
		max_group = maxi(max_group, g)
	var lengths := PackedFloat32Array()
	var longest := 1e-6
	for c in n_curves:
		var l := 0.0
		for k in range(1, curves[c].size()):
			l += curves[c][k].distance_to(curves[c][k - 1])
		lengths.append(l)
		longest = maxf(longest, l)
	for c in n_curves:
		var is_link := links.has(c)
		var link_f := 1.0 if is_link else 0.0
		var group_f := float(groups[c]) / float(maxi(max_group, 1)) if c < groups.size() else 0.0
		var len_f := lengths[c] / longest
		var tip_c := maxf(tip_ratio, LINK_TIP_RATIO) if is_link else tip_ratio
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
				var w := width * lerpf(1.0, tip_c, pow(s, 1.3))
				var alpha := lerpf(1.0, LINK_TIP_ALPHA, s) if is_link else opacity * pow(1.0 - s, 0.6)
				for side in 2:
					var off := (float(side) - 0.5) * w
					verts.append(frames_p[k] + wd * off)
					normals.append(nrm)
					tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
					uvs.append(Vector2(s, float(side)))
					uv2s.append(Vector2(strand_u, strand_h))
					colors.append(Color(1.0, 1.0, 1.0, alpha))
					custom.append_array(PackedFloat32Array([link_f, group_f, len_f, 0.0]))
			for k in count - 1:
				var a := base + 2 * k
				_quad(verts, normals, indices, a, a + 1, a + 3, a + 2)
	return _commit(verts, normals, tangents, uvs, uv2s, colors, indices, custom)


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
		colors: PackedColorArray, indices: PackedInt32Array, custom := PackedFloat32Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := 0
	if custom.size() == verts.size() * 4 and verts.size() > 0:
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh
