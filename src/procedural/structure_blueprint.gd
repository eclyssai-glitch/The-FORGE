class_name StructureBlueprint
extends RefCounted
## Pure, deterministic data for the ORIGIN CHAMBER structure: a lens-shaped "vessel" of stacked,
## segmented rings around the suspended core at the origin. No nodes, no meshes, no clock.
##
## Shape (layer_count = 5, see docs/PROCEDURAL.md): five rings at y = -1.84 … +1.84, the middle
## one centred on the core (y = 0). Outer and inner radii follow an elliptical (lens) profile, widest
## at the equator; every ring is split into annular-sector segments separated by a small gap.
## Segment counts are 16/20/24/20/16 = 96 = OriginChamberScript.FRAGMENT_COUNT.
##
## SEGMENT ORIENTATION (for placement/animation): the segment mesh from
## `MeshBuilder.annular_segment(**segment_mesh_params(layer))` is centred on angle 0, i.e. on the
## local +Z axis, with the ring axis at the local origin (the segment sits at radius
## radius_inner..radius_outer along +Z; its centroid is `segment_pivot(layer)` ≈ (0, 0, r_mid)).
## Angles are measured around +Y from +Z towards +X, so `segment_transform(i)` is only
## `Basis(Vector3.UP, angle)` plus the layer height. Global index i runs layer by layer, bottom
## (layer 0) to top, and inside a layer in increasing angle.

const TOTAL_SEGMENTS := 96
## Radius of the suspended core (for clearance checks; the core mesh itself belongs to OriginCore).
const CORE_RADIUS := 0.55
## |y| of the outermost rings (t = ±1). Rings are evenly spaced in between.
const HALF_SPAN_Y := 1.84
## Lens profile: outer/inner radius at the equator (t = 0) and at the poles (|t| = 1).
const OUTER_EQUATOR := 3.05
const OUTER_POLE := 2.2
const INNER_EQUATOR := 2.1
const INNER_POLE := 1.4
## Ring height (vertical) at the equator and at the poles (linear in |t|).
const HEIGHT_EQUATOR := 0.19
const HEIGHT_POLE := 0.14
## Physical gap between neighbouring segments, measured at the mid radius (world units).
const SEGMENT_GAP := 0.05
const ARC_STEPS := 6
## Assembly twist magnitude range (rad); sign alternates per layer.
const TWIST_MIN := 0.45
const TWIST_MAX := 0.85
## Random per-layer jitter added to the phase (rad).
const PHASE_JITTER := 0.04
## Vertical ribs linking the rings in the final form.
const RIB_COUNT := 12
const RIB_RADIUS := 2.15
const RIB_WIDTH := 0.055
const RIB_DEPTH := 0.08
## How far each rib tip is recessed *into* the outermost rings (world units, >= 0). The ribs span
## exactly from the bottom face of the lowest ring to the top face of the highest ring, minus this
## inset at each end, so the tips are buried in the ring body (no protruding "rebar", and no
## coplanar cap fighting the ring face). Must stay below half the pole ring height (0.07).
const RIB_INSET := 0.02
## Scatter shell ("loose fragments"): segment centroids at this distance from the core.
const SCATTER_MIN := 3.5
const SCATTER_MAX := 4.8
const SCATTER_SCALE_MIN := 0.35
const SCATTER_SCALE_MAX := 0.6
## Vertical component of the scatter direction (keeps fragments above the floor at y = -3.2).
const SCATTER_DIR_Y_MIN := -0.5
const SCATTER_DIR_Y_MAX := 0.72

var seed_value := 7
## One Dictionary per layer, bottom to top: {"index", "y", "height", "radius_inner",
## "radius_outer", "segment_count", "gap", "twist", "phase", "first_segment"}.
var layers: Array[Dictionary] = []
var _scatter: Array[Transform3D] = []


@warning_ignore("shadowed_global_identifier")
static func build(layer_count: int = 5, seed: int = 7) -> StructureBlueprint:
	var bp := StructureBlueprint.new()
	bp.seed_value = seed
	var n := maxi(layer_count, 1)
	var counts := _distribute(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var first := 0
	for k in n:
		var t := 0.0 if n == 1 else lerpf(-1.0, 1.0, float(k) / float(n - 1))
		var a := absf(t)
		var r_out := _lens(OUTER_EQUATOR, OUTER_POLE, a)
		var r_in := _lens(INNER_EQUATOR, INNER_POLE, a)
		var count: int = counts[k]
		var pitch := TAU / float(count)
		var twist := rng.randf_range(TWIST_MIN, TWIST_MAX) * (1.0 if k % 2 == 0 else -1.0)
		var phase := (0.5 * pitch if k % 2 == 1 else 0.0) + rng.randf_range(-PHASE_JITTER, PHASE_JITTER)
		bp.layers.append({
			"index": k,
			"y": t * HALF_SPAN_Y,
			"height": lerpf(HEIGHT_EQUATOR, HEIGHT_POLE, a),
			"radius_inner": r_in,
			"radius_outer": r_out,
			"segment_count": count,
			"gap": SEGMENT_GAP / ((r_in + r_out) * 0.5),
			"twist": twist,
			"phase": phase,
			"first_segment": first,
		})
		first += count
	var srng := RandomNumberGenerator.new()
	srng.seed = seed * 7919 + 104729
	for i in TOTAL_SEGMENTS:
		bp._scatter.append(bp._make_scatter(i, srng))
	return bp


## Segment counts per layer: tent weights (6 at the equator → 4 at the poles) scaled to exactly
## TOTAL_SEGMENTS with largest-remainder rounding. For 5 layers: 16, 20, 24, 20, 16.
static func _distribute(n: int) -> PackedInt32Array:
	var weights := PackedFloat32Array()
	var total := 0.0
	for k in n:
		var t := 0.0 if n == 1 else lerpf(-1.0, 1.0, float(k) / float(n - 1))
		weights.append(6.0 - 2.0 * absf(t))
		total += weights[k]
	var counts := PackedInt32Array()
	var rema: Array[Vector2] = []
	var assigned := 0
	for k in n:
		var exact := weights[k] / total * TOTAL_SEGMENTS
		counts.append(int(floor(exact)))
		assigned += counts[k]
		rema.append(Vector2(exact - floor(exact), k))
	rema.sort_custom(func(p: Vector2, q: Vector2) -> bool:
		return p.x > q.x or (p.x == q.x and p.y < q.y))
	for j in TOTAL_SEGMENTS - assigned:
		counts[int(rema[j % n].y)] += 1
	return counts


## Elliptical lens profile: `equator` at a = 0, `pole` at a = 1.
static func _lens(equator: float, pole: float, a: float) -> float:
	var k := 1.0 - (pole / equator) * (pole / equator)
	return equator * sqrt(1.0 - k * a * a)


func segment_count_total() -> int:
	var total := 0
	for layer in layers:
		total += int(layer["segment_count"])
	return total


## Layer of global segment i (0..95), or -1 when out of range.
func segment_layer(i: int) -> int:
	if i < 0:
		return -1
	for layer in layers:
		if i < int(layer["first_segment"]) + int(layer["segment_count"]):
			return int(layer["index"])
	return -1


## Index of global segment i inside its layer, or -1 when out of range.
func segment_index_in_layer(i: int) -> int:
	var l := segment_layer(i)
	return -1 if l < 0 else i - int(layers[l]["first_segment"])


## Global index of the first segment of `layer` (segments of a layer are contiguous).
func layer_first_segment(layer: int) -> int:
	return int(layers[layer]["first_segment"])


## Final angle (rad, around +Y from +Z towards +X) of segment i, plus twist_amount·layer.twist.
func segment_angle(i: int, twist_amount: float = 0.0) -> float:
	var layer := layers[segment_layer(i)]
	var k := segment_index_in_layer(i)
	return float(layer["phase"]) + TAU * float(k) / float(layer["segment_count"]) \
		+ twist_amount * float(layer["twist"])


## Final (assembled) transform of segment i: rotation around Y to its angle + layer height.
## twist_amount = 1 gives the pre-lock assembly pose; 0 is the locked final form.
func segment_transform(i: int, twist_amount: float = 0.0) -> Transform3D:
	var layer := layers[segment_layer(i)]
	return Transform3D(Basis(Vector3.UP, segment_angle(i, twist_amount)),
		Vector3(0.0, float(layer["y"]), 0.0))


## Arguments for MeshBuilder.annular_segment for this layer:
## {"r_in", "r_out", "height", "angle_span", "arc_steps"}.
func segment_mesh_params(layer: int) -> Dictionary:
	var l := layers[layer]
	return {
		"r_in": float(l["radius_inner"]),
		"r_out": float(l["radius_outer"]),
		"height": float(l["height"]),
		"angle_span": TAU / float(l["segment_count"]) - float(l["gap"]),
		"arc_steps": ARC_STEPS,
	}


## Local-space centroid of a segment mesh of `layer` (on +Z at the mid radius). Rotate/scale
## fragments around this point so they spin in place instead of orbiting the ring axis.
func segment_pivot(layer: int) -> Vector3:
	var l := layers[layer]
	return Vector3(0.0, 0.0, (float(l["radius_inner"]) + float(l["radius_outer"])) * 0.5)


## Deterministic "loose fragment" transform of segment i: the segment centroid lies on a shell
## SCATTER_MIN..SCATTER_MAX from the core, roughly outwards of its final angle, with a random
## rotation and uniform scale SCATTER_SCALE_MIN..SCATTER_SCALE_MAX.
func scatter_transform(i: int) -> Transform3D:
	return _scatter[i]


## Blend helper: fragment pose between scatter (t = 0) and final (t = 1), interpolating the
## centroid position linearly and the rotation/scale by slerp/lerp around the centroid.
func assembly_transform(i: int, t: float, twist_amount: float = 0.0) -> Transform3D:
	var pivot := segment_pivot(segment_layer(i))
	var a := scatter_transform(i)
	var b := segment_transform(i, twist_amount)
	var s := lerpf(a.basis.get_scale().x, 1.0, t)
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)
	var basis := Basis(q).scaled(Vector3.ONE * s)
	var centre := (a * pivot).lerp(b * pivot, t)
	return Transform3D(basis, centre - basis * pivot)


func _make_scatter(i: int, rng: RandomNumberGenerator) -> Transform3D:
	var l := segment_layer(i)
	var az := segment_angle(i) + rng.randf_range(-0.8, 0.8)
	var dir_y := clampf(float(layers[l]["y"]) / HALF_SPAN_Y * 0.35 + rng.randf_range(-0.3, 0.3),
		SCATTER_DIR_Y_MIN, SCATTER_DIR_Y_MAX)
	var h := sqrt(1.0 - dir_y * dir_y)
	var centre := Vector3(h * sin(az), dir_y, h * cos(az)) * rng.randf_range(SCATTER_MIN, SCATTER_MAX)
	# Uniform random rotation (Shoemake).
	var u1 := rng.randf()
	var u2 := rng.randf() * TAU
	var u3 := rng.randf() * TAU
	var q := Quaternion(sqrt(1.0 - u1) * sin(u2), sqrt(1.0 - u1) * cos(u2),
		sqrt(u1) * sin(u3), sqrt(u1) * cos(u3)).normalized()
	var basis := Basis(q).scaled(Vector3.ONE * rng.randf_range(SCATTER_SCALE_MIN, SCATTER_SCALE_MAX))
	return Transform3D(basis, centre - basis * segment_pivot(l))


## Transforms of the vertical ribs (RIB_COUNT) that appear in the final form. Each rib mesh
## (MeshBuilder.rib(**rib_mesh_params())) is placed at RIB_RADIUS, its flat back (+Z) facing
## outwards, aligned with every other gap of the middle ring, spanning all layers. The origin is
## the vertical midpoint of the ring stack, so scaling Y about it (rib growth) stays inside it.
func rib_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var mid := layers[layers.size() >> 1]
	var offset := float(mid["phase"]) + PI / float(mid["segment_count"])
	var y_mid := (float(layers[0]["y"]) + float(layers[layers.size() - 1]["y"])) * 0.5
	for r in RIB_COUNT:
		var a := offset + TAU * float(r) / float(RIB_COUNT)
		out.append(Transform3D(Basis(Vector3.UP, a),
			Vector3(RIB_RADIUS * sin(a), y_mid, RIB_RADIUS * cos(a))))
	return out


## Arguments for MeshBuilder.rib: {"height", "width", "depth"}. height = ring-stack span (bottom
## face of the lowest ring → top face of the highest) − 2·RIB_INSET.
func rib_mesh_params() -> Dictionary:
	var bottom := layers[0]
	var top := layers[layers.size() - 1]
	var span := float(top["y"]) + float(top["height"]) * 0.5 \
		- (float(bottom["y"]) - float(bottom["height"]) * 0.5)
	return {"height": span - 2.0 * RIB_INSET, "width": RIB_WIDTH, "depth": RIB_DEPTH}


## Largest outer radius of any ring.
func max_outer_radius() -> float:
	var m := 0.0
	for l in layers:
		m = maxf(m, float(l["radius_outer"]))
	return m
