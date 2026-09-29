extends GutTest
## StructureBlueprint: counts, determinism, radii/limits, index mapping, final vs scatter poses.

const EPS := 1e-4
const FLOOR_Y := -3.2

var bp: StructureBlueprint


func before_each() -> void:
	bp = StructureBlueprint.build()


func _centroid(i: int, tr: Transform3D) -> Vector3:
	return tr * bp.segment_pivot(bp.segment_layer(i))


func test_default_build_has_five_layers_and_96_segments() -> void:
	assert_eq(bp.layers.size(), OriginChamberScript.LAYER_COUNT)
	assert_eq(bp.segment_count_total(), OriginChamberScript.FRAGMENT_COUNT)
	assert_eq(StructureBlueprint.TOTAL_SEGMENTS, OriginChamberScript.FRAGMENT_COUNT)


func test_segment_count_per_layer() -> void:
	var counts: Array[int] = []
	for l in bp.layers:
		counts.append(int(l["segment_count"]))
	assert_eq(counts, [16, 20, 24, 20, 16] as Array[int])


func test_other_layer_counts_still_sum_to_96() -> void:
	for n in [1, 2, 3, 4, 6, 7, 9]:
		var other := StructureBlueprint.build(n, 3)
		assert_eq(other.layers.size(), n)
		assert_eq(other.segment_count_total(), 96, "layer_count %d sums to 96" % n)


func test_layer_dictionaries_have_contract_keys() -> void:
	for l in bp.layers:
		for key in ["index", "y", "height", "radius_inner", "radius_outer", "segment_count",
				"gap", "twist", "phase"]:
			assert_true(l.has(key), "layer has key %s" % key)


func test_same_seed_is_deterministic() -> void:
	var a := StructureBlueprint.build(5, 7)
	var b := StructureBlueprint.build(5, 7)
	assert_eq(a.layers, b.layers)
	for i in 96:
		assert_eq(a.scatter_transform(i), b.scatter_transform(i))
		assert_eq(a.segment_transform(i, 0.5), b.segment_transform(i, 0.5))


func test_different_seed_varies_pose_not_dimensions() -> void:
	var a := StructureBlueprint.build(5, 7)
	var b := StructureBlueprint.build(5, 8)
	var phase_differs := false
	for k in a.layers.size():
		var la := a.layers[k]
		var lb := b.layers[k]
		for key in ["y", "height", "radius_inner", "radius_outer", "segment_count", "gap"]:
			assert_eq(la[key], lb[key], "%s independent of seed" % key)
		if not is_equal_approx(float(la["phase"]), float(lb["phase"])) \
				or not is_equal_approx(float(la["twist"]), float(lb["twist"])):
			phase_differs = true
	assert_true(phase_differs, "seed changes phase/twist")
	var scatter_differs := 0
	for i in 96:
		if not a.scatter_transform(i).is_equal_approx(b.scatter_transform(i)):
			scatter_differs += 1
	assert_eq(scatter_differs, 96, "seed changes every scatter pose")


func test_radii_clear_the_core_and_stay_inside_limit() -> void:
	for l in bp.layers:
		var r_in := float(l["radius_inner"])
		var r_out := float(l["radius_outer"])
		assert_gt(r_in, 1.1, "inner radius clears the core")
		assert_gt(r_in, StructureBlueprint.CORE_RADIUS * 2.0)
		assert_lt(r_in, r_out)
		assert_lte(r_out, 3.2, "outer radius within 3.2")
	assert_lte(bp.max_outer_radius(), 3.2)


func test_lens_silhouette_widest_at_equator() -> void:
	var mid := bp.layers.size() >> 1
	for k in bp.layers.size():
		if k == mid:
			continue
		assert_lt(float(bp.layers[k]["radius_outer"]), float(bp.layers[mid]["radius_outer"]))
	for k in mid:
		var lo := float(bp.layers[k]["radius_outer"])
		var hi := float(bp.layers[k + 1]["radius_outer"])
		assert_lt(lo, hi, "outer radius grows towards the equator")
		assert_almost_eq(lo, float(bp.layers[bp.layers.size() - 1 - k]["radius_outer"]), EPS,
			"symmetric")


func test_layers_sorted_by_y_without_vertical_overlap() -> void:
	for k in bp.layers.size() - 1:
		var a := bp.layers[k]
		var b := bp.layers[k + 1]
		assert_lt(float(a["y"]), float(b["y"]))
		assert_lt(float(a["y"]) + float(a["height"]) * 0.5, float(b["y"]) - float(b["height"]) * 0.5,
			"rings do not overlap vertically")
	assert_between(float(bp.layers[0]["y"]), -2.2, -1.6)
	assert_between(float(bp.layers[4]["y"]), 1.6, 2.2)
	var mid := bp.layers[2]
	assert_almost_eq(float(mid["y"]), 0.0, EPS, "core at the centre of the middle layer")


func test_segments_in_a_layer_do_not_overlap() -> void:
	for k in bp.layers.size():
		var p := bp.segment_mesh_params(k)
		var pitch := TAU / float(bp.layers[k]["segment_count"])
		assert_gt(float(p["angle_span"]), 0.0)
		assert_lt(float(p["angle_span"]), pitch)
		assert_gt(float(bp.layers[k]["gap"]), 0.0)
		assert_almost_eq(float(p["angle_span"]) + float(bp.layers[k]["gap"]), pitch, EPS)
		assert_eq(p["r_in"], bp.layers[k]["radius_inner"])
		assert_eq(p["r_out"], bp.layers[k]["radius_outer"])
		assert_eq(p["height"], bp.layers[k]["height"])


func test_global_index_mapping_round_trips() -> void:
	var expected_layer := 0
	var expected_index := 0
	for i in 96:
		if expected_index >= int(bp.layers[expected_layer]["segment_count"]):
			expected_layer += 1
			expected_index = 0
		assert_eq(bp.segment_layer(i), expected_layer)
		assert_eq(bp.segment_index_in_layer(i), expected_index)
		assert_eq(bp.layer_first_segment(bp.segment_layer(i)) + bp.segment_index_in_layer(i), i)
		expected_index += 1
	assert_eq(bp.segment_layer(-1), -1)
	assert_eq(bp.segment_layer(96), -1)
	assert_eq(bp.segment_index_in_layer(96), -1)


func test_final_transform_is_y_rotation_plus_height() -> void:
	for i in 96:
		var l := bp.layers[bp.segment_layer(i)]
		var tr := bp.segment_transform(i)
		assert_almost_eq(tr.origin, Vector3(0.0, float(l["y"]), 0.0), Vector3.ONE * EPS)
		assert_true(tr.basis.is_equal_approx(Basis(Vector3.UP, bp.segment_angle(i))))
		assert_almost_eq(tr.basis.determinant(), 1.0, EPS)
		# Mesh axis +Z maps to the segment direction (sin a, 0, cos a).
		var a := bp.segment_angle(i)
		assert_almost_eq(tr.basis * Vector3.BACK, Vector3(sin(a), 0.0, cos(a)), Vector3.ONE * EPS)


func test_final_angles_evenly_spaced_and_twist_applies() -> void:
	for k in bp.layers.size():
		var l := bp.layers[k]
		var first := bp.layer_first_segment(k)
		var n := int(l["segment_count"])
		for j in n:
			var expected := float(l["phase"]) + TAU * j / n
			assert_almost_eq(bp.segment_angle(first + j), expected, EPS)
			assert_almost_eq(bp.segment_angle(first + j, 1.0), expected + float(l["twist"]), EPS)
		assert_gt(absf(float(l["twist"])), 0.1, "assembly twist is noticeable")
	var twisted := bp.segment_transform(0, 1.0)
	assert_false(twisted.basis.is_equal_approx(bp.segment_transform(0).basis))


func test_final_centroids_inside_vessel() -> void:
	for i in 96:
		var c := _centroid(i, bp.segment_transform(i))
		var l := bp.layers[bp.segment_layer(i)]
		var r := Vector2(c.x, c.z).length()
		assert_between(r, float(l["radius_inner"]), float(l["radius_outer"]))
		assert_lt(c.length(), bp.max_outer_radius())


func test_scatter_outside_vessel_and_within_shell() -> void:
	var r_max := bp.max_outer_radius()
	for i in 96:
		var tr := bp.scatter_transform(i)
		var c := _centroid(i, tr)
		assert_gt(c.length(), r_max, "scatter %d outside the vessel radius" % i)
		assert_gte(c.length(), 3.2 - EPS)
		assert_lte(c.length(), 5.0, "scatter %d within 5.0" % i)
		assert_gt(c.y, FLOOR_Y + 0.5, "scatter above the floor")
		var s := tr.basis.get_scale()
		assert_almost_eq(s.x, s.y, EPS, "uniform scale")
		assert_almost_eq(s.x, s.z, EPS, "uniform scale")
		assert_between(s.x, 0.35 - EPS, 0.6 + EPS)


func test_scatter_poses_are_distinct() -> void:
	var seen := {}
	for i in 96:
		var c := _centroid(i, bp.scatter_transform(i)).snapped(Vector3.ONE * 0.001)
		seen[c] = true
	assert_eq(seen.size(), 96)


func test_assembly_transform_blends_scatter_to_final() -> void:
	for i in [0, 17, 40, 63, 95]:
		assert_true(bp.assembly_transform(i, 0.0).is_equal_approx(bp.scatter_transform(i)))
		assert_true(bp.assembly_transform(i, 1.0).is_equal_approx(bp.segment_transform(i)))
		assert_true(bp.assembly_transform(i, 1.0, 1.0).is_equal_approx(bp.segment_transform(i, 1.0)))
		var mid := _centroid(i, bp.assembly_transform(i, 0.5))
		var expect := (_centroid(i, bp.scatter_transform(i)) + _centroid(i, bp.segment_transform(i))) * 0.5
		assert_almost_eq(mid, expect, Vector3.ONE * EPS, "centroid moves linearly")


func test_ribs_link_every_layer() -> void:
	var ribs := bp.rib_transforms()
	assert_between(ribs.size(), 8, 12)
	var p := bp.rib_mesh_params()
	assert_gt(float(p["height"]), 0.0)
	assert_gt(float(p["width"]), 0.0)
	assert_gt(float(p["depth"]), 0.0)
	var bottom := bp.layers[0]
	var top := bp.layers[bp.layers.size() - 1]
	for tr in ribs:
		var r := Vector2(tr.origin.x, tr.origin.z).length()
		for l in bp.layers:
			assert_between(r, float(l["radius_inner"]), float(l["radius_outer"]),
				"rib passes through every ring")
		var lo := tr.origin.y - float(p["height"]) * 0.5
		var hi := tr.origin.y + float(p["height"]) * 0.5
		assert_lte(lo, float(bottom["y"]) - float(bottom["height"]) * 0.5)
		assert_gte(hi, float(top["y"]) + float(top["height"]) * 0.5)
		# Rib back (+Z) faces outwards.
		assert_gt((tr.basis * Vector3.BACK).dot(Vector3(tr.origin.x, 0.0, tr.origin.z).normalized()),
			0.999)
