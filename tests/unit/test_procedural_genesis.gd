extends GutTest
## GENESIS geometry: baked sculptures (OBJ + JSON from tools/sculpt) and runtime generators
## (HairRibbons, OrbitLine, PlanetSphere, AsteroidField, RelationThread).

const MESH_DIR := "res://assets/meshes/"
const BUDGET := {"miku_body": 120000, "hand_left": 60000, "hand_right": 60000}


func _meta(name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(MESH_DIR + name + ".json")
	var data: Variant = JSON.parse_string(text)
	assert_true(data is Dictionary, "%s.json parses" % name)
	return data if data is Dictionary else {}


func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _arrays(name: String) -> Array:
	var mesh: Mesh = load(MESH_DIR + name + ".obj")
	assert_not_null(mesh, "%s.obj loads as a Mesh" % name)
	if mesh == null:
		return []
	assert_eq(mesh.get_surface_count(), 1, "%s single surface" % name)
	return mesh.surface_get_arrays(0)


# ------------------------------------------------------------------ sculptures

func test_sculptures_load_within_budget_with_vertex_ao() -> void:
	for name: String in BUDGET:
		var arrays := _arrays(name)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tris := idx.size() / 3
		assert_gt(tris, 10000, "%s is a real sculpture" % name)
		assert_lte(tris, int(BUDGET[name]), "%s within the triangle budget" % name)
		assert_eq(normals.size(), verts.size(), "%s has one normal per vertex" % name)
		assert_eq(colors.size(), verts.size(), "%s has vertex colours (AO)" % name)
		var lo := 1.0
		var hi := 0.0
		var grey := true
		for c in colors:
			lo = minf(lo, c.r)
			hi = maxf(hi, c.r)
			if absf(c.r - c.g) > 0.01 or absf(c.r - c.b) > 0.01:
				grey = false
		assert_true(grey, "%s AO is stored as grey RGB" % name)
		assert_lt(lo, 0.5, "%s AO darkens crevices" % name)
		assert_gt(hi, 0.9, "%s AO leaves open surfaces bright" % name)
		var bad := 0
		for n in normals:
			if absf(n.length() - 1.0) > 0.02:
				bad += 1
		assert_eq(bad, 0, "%s normals are unit length" % name)


func test_sculpture_normals_point_outwards() -> void:
	for name: String in BUDGET:
		var arrays := _arrays(name)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var wrong := 0
		var tris := idx.size() / 3
		for t in tris:
			var a := verts[idx[3 * t]]
			var g := (verts[idx[3 * t + 1]] - a).cross(verts[idx[3 * t + 2]] - a)
			var n := normals[idx[3 * t]] + normals[idx[3 * t + 1]] + normals[idx[3 * t + 2]]
			# Godot front faces are clockwise: the geometric normal opposes the vertex normal
			if g.dot(n) > 0.0:
				wrong += 1
		assert_lt(float(wrong) / float(tris), 0.001, "%s winding agrees with outward normals" % name)


func test_sculpture_bounds_match_metadata() -> void:
	for name: String in BUDGET:
		var mesh: Mesh = load(MESH_DIR + name + ".obj")
		var meta := _meta(name)
		if mesh == null or meta.is_empty():
			continue
		var aabb := mesh.get_aabb()
		var b: Dictionary = meta["bounds"]
		assert_almost_eq(aabb.position, _v3(b["min"]), Vector3.ONE * 0.01, "%s AABB min" % name)
		assert_almost_eq(aabb.end, _v3(b["max"]), Vector3.ONE * 0.01, "%s AABB max" % name)
		assert_eq(int(meta["triangles"]), (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3,
			"%s triangle count in metadata" % name)


func test_miku_scale_frame_and_anchors() -> void:
	var meta := _meta("miku_body")
	var mesh: Mesh = load(MESH_DIR + "miku_body.obj")
	if meta.is_empty() or mesh == null:
		return
	var aabb := mesh.get_aabb()
	assert_between(aabb.size.y, 5.8, 6.2, "MIKU is about 6 units tall")
	assert_true(aabb.has_point(Vector3.ZERO), "origin (waist) is inside the figure bounds")
	var a: Dictionary = meta["anchors"]
	for key in ["head_top", "forehead", "hair_root", "hair_root_tangent", "palm_left", "palm_right",
			"chest", "gown_hem_center"]:
		assert_true(a.has(key), "anchor %s" % key)
	var top := _v3(a["head_top"])
	assert_almost_eq(top.y, aabb.end.y, 0.08, "head_top near the top of the bounds")
	var forehead := _v3(a["forehead"])
	assert_gt(forehead.z, 0.1, "forehead faces +Z")
	assert_between(forehead.y, 1.2, top.y, "forehead below the head top")
	var root := _v3(a["hair_root"])
	var tangent := _v3(a["hair_root_tangent"])
	assert_lt(root.z, forehead.z, "hair root behind the face")
	assert_almost_eq(tangent.length(), 1.0, 0.01, "hair tangent is unit")
	assert_gt(tangent.y, 0.3, "hair leaves upwards")
	assert_lt(tangent.z, -0.3, "hair leaves backwards")
	assert_gt(_v3(a["palm_left"]).x, 0.6, "her left palm on +X")
	assert_lt(_v3(a["palm_right"]).x, -0.6, "her right palm on -X")
	assert_gt(_v3(a["chest"]).z, 0.1, "chest anchor on the front")
	var hem := _v3(a["gown_hem_center"])
	assert_almost_eq(hem.y, aabb.position.y, 0.3, "hem centre near the bottom")
	assert_between(float(a["gown_hem_radius"]), 0.8, 1.6, "hem radius")
	for key: String in a:
		if a[key] is Array:
			assert_true(aabb.grow(0.05).has_point(_v3(a[key])) or key.ends_with("tangent") or key.ends_with("normal"),
				"anchor %s inside bounds" % key)


func test_giant_hands_scale_and_anchors() -> void:
	for side in ["left", "right"]:
		var meta := _meta("hand_" + side)
		var mesh: Mesh = load(MESH_DIR + "hand_" + side + ".obj")
		if meta.is_empty() or mesh == null:
			continue
		var a: Dictionary = meta["anchors"]
		for key in ["palm_center", "palm_normal", "wrist_center", "forearm_dir", "tip_thumb", "tip_index",
				"tip_middle", "tip_ring", "tip_little"]:
			assert_true(a.has(key), "%s anchor %s" % [side, key])
		assert_almost_eq(_v3(a["palm_center"]), Vector3.ZERO, Vector3.ONE * 1e-3, "%s origin = palm centre" % side)
		var along := 0.0
		# unfolded wrist -> middle tip is 7 units; the posed (curled) chord is shorter
		var chord := _v3(a["wrist_center"]).distance_to(_v3(a["tip_middle"]))
		along = float(meta["wrist_to_middle_tip"])
		assert_almost_eq(chord, along, 0.01, "%s metadata chord" % side)
		assert_between(chord, 5.6, 7.2, "%s wrist -> middle fingertip about 7 units" % side)
		var pn := _v3(a["palm_normal"])
		assert_almost_eq(pn.length(), 1.0, 0.01, "%s palm normal unit" % side)
		if side == "left":
			assert_gt(pn.y, 0.6, "left palm faces up")
			assert_gt(_v3(a["tip_middle"]).x, 1.0, "left fingers towards +X")
			assert_lt(_v3(a["forearm_dir"]).x, -0.6, "left forearm towards -X")
		else:
			assert_lt(pn.y, -0.6, "right palm faces down")
			assert_lt(_v3(a["tip_middle"]).x, -1.0, "right fingers towards -X")
			assert_gt(_v3(a["forearm_dir"]).x, 0.6, "right forearm towards +X")
		var aabb := mesh.get_aabb().grow(0.05)
		for key in ["wrist_center", "tip_thumb", "tip_index", "tip_middle", "tip_ring", "tip_little"]:
			assert_true(aabb.has_point(_v3(a[key])), "%s %s inside bounds" % [side, key])


func test_right_hand_is_not_a_mirror_of_the_left() -> void:
	var l := _meta("hand_left")
	var r := _meta("hand_right")
	if l.is_empty() or r.is_empty():
		return
	var la: Dictionary = l["anchors"]
	var ra: Dictionary = r["anchors"]
	# mirror the left through the YZ plane and flip Y (palm up -> palm down): a pure mirror copy
	# would land every fingertip on the right hand's; its own pose moves them by > 0.3 units
	var moved := 0
	for key in ["tip_thumb", "tip_index", "tip_middle", "tip_ring", "tip_little"]:
		var p := _v3(la[key])
		var mirrored := Vector3(-p.x, -p.y, p.z)
		if mirrored.distance_to(_v3(ra[key])) > 0.3:
			moved += 1
	assert_gte(moved, 3, "right hand has its own pose")


# ------------------------------------------------------------------ runtime generators

func _surface(mesh: ArrayMesh) -> Array:
	assert_eq(mesh.get_surface_count(), 1)
	return mesh.surface_get_arrays(0)


func _assert_uv_range(uvs: PackedVector2Array, label: String) -> void:
	var bad := 0
	for uv in uvs:
		if uv.x < -1e-5 or uv.x > 1.0 + 1e-5 or uv.y < -1e-5 or uv.y > 1.0 + 1e-5:
			bad += 1
	assert_eq(bad, 0, "%s UVs in [0,1]" % label)


func _assert_winding(arrays: Array, label: String) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var wrong := 0
	var degenerate := 0
	for t in idx.size() / 3:
		var a := verts[idx[3 * t]]
		var g := (verts[idx[3 * t + 1]] - a).cross(verts[idx[3 * t + 2]] - a)
		if g.length() < 1e-9:
			degenerate += 1
			continue
		if g.dot(normals[idx[3 * t]] + normals[idx[3 * t + 1]] + normals[idx[3 * t + 2]]) > 0.0:
			wrong += 1
	assert_eq(degenerate, 0, "%s no degenerate triangles" % label)
	assert_eq(wrong, 0, "%s clockwise front faces" % label)


func test_hair_curves_are_deterministic_and_flow_up_back() -> void:
	var root := Vector3(0, 1.9, -0.4)
	var dir := Vector3(0, 0.8, -0.6)
	var a := HairRibbons.generate_curves(root, dir, 24, 11)
	var b := HairRibbons.generate_curves(root, dir, 24, 11)
	var c := HairRibbons.generate_curves(root, dir, 24, 12)
	assert_eq(a.size(), 24)
	assert_eq(a, b, "same seed -> same curves")
	assert_ne(a, c, "other seed -> other curves")
	for curve in a:
		assert_lt(curve[0].distance_to(root), 0.15, "strand starts at the hair root")
		var end := curve[curve.size() - 1]
		assert_gt(end.y, root.y + 2.0, "strand rises")
		assert_lt(end.z, root.z, "strand flows back")


func test_hair_ribbons_uv_and_taper() -> void:
	var curves := HairRibbons.generate_curves(Vector3.ZERO, Vector3.UP, 6, 3, 8.0)
	var mesh := HairRibbons.build(curves, 0.08, 0.1, 32)
	var arrays := _surface(mesh)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(verts.size(), 6 * 32 * 2, "two vertices per sample")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 6 * 31 * 6, "two triangles per segment")
	_assert_uv_range(uvs, "hair")
	_assert_uv_range(uv2s, "hair uv2")
	_assert_winding(arrays, "hair")
	# strand 0: UV.x goes 0 -> 1 monotonically, the ribbon narrows to the tip
	assert_almost_eq(uvs[0].x, 0.0, 1e-5)
	assert_almost_eq(uvs[2 * 31].x, 1.0, 1e-5)
	for k in 31:
		assert_true(uvs[2 * (k + 1)].x > uvs[2 * k].x, "UV.x increases along the strand")
	var w0 := verts[0].distance_to(verts[1])
	var w1 := verts[2 * 31].distance_to(verts[2 * 31 + 1])
	assert_almost_eq(w0, 0.08, 1e-4, "root width")
	assert_almost_eq(w1, 0.008, 1e-4, "tip width")
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(colors.size(), verts.size(), "vertex colour per vertex (alpha = opacity)")
	assert_gt(colors[0].a, 0.5, "opaque at the root")
	assert_almost_eq(colors[2 * 31].a, 0.0, 1e-4, "transparent at the tip")
	var again := HairRibbons.build(curves, 0.08, 0.1, 32)
	assert_eq(again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], verts, "deterministic mesh")
	var crossed := HairRibbons.build(curves, 0.08, 0.1, 32, Vector3.BACK, true)
	var carr := crossed.surface_get_arrays(0)
	assert_eq((carr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 2 * verts.size(), "crossed doubles the ribbons")
	_assert_winding(carr, "crossed hair")


func test_hair_nebula_is_one_mass_of_tufts_rising_in_s() -> void:
	var root := Vector3(0, 1.6, -0.2)
	var dir := Vector3(0, 0.55, -0.83)
	var a := HairRibbons.nebula(root, dir, 41, 8, 10.0)
	var b := HairRibbons.nebula(root, dir, 41, 8, 10.0)
	var c := HairRibbons.nebula(root, dir, 42, 8, 10.0)
	var curves: Array[PackedVector3Array] = a["curves"]
	var groups: PackedInt32Array = a["groups"]
	assert_eq(curves, b["curves"], "same seed -> same mass")
	assert_ne(curves, c["curves"], "other seed -> other mass")
	assert_eq(groups.size(), curves.size(), "one tuft index per strand")
	assert_eq((a["links"] as PackedInt32Array).size(), 0, "no link strands unless asked")
	var per_tuft := {}
	for g in groups:
		per_tuft[g] = int(per_tuft.get(g, 0)) + 1
	assert_eq(per_tuft.size(), 8, "8 tufts")
	for g: int in per_tuft:
		assert_between(int(per_tuft[g]), 5, 10, "tuft %d has 5-10 strands" % g)
	var shortest := INF
	var longest := 0.0
	for curve in curves:
		assert_lt(curve[0].distance_to(root), 0.04, "single root")
		var end := curve[curve.size() - 1]
		assert_gt(end.y, root.y + 1.0, "strand rises")
		assert_lt(end.z, root.z - 1.0, "strand flows back")
		var l := 0.0
		for k in range(1, curve.size()):
			l += curve[k].distance_to(curve[k - 1])
		shortest = minf(shortest, l)
		longest = maxf(longest, l)
	assert_gt(longest / shortest, 1.6, "varied lengths")
	# tips open like filaments: strands of a tuft are close at the root, apart at the tip
	var root_gap := 0.0
	var tip_gap := 0.0
	var pairs := 0
	for i in curves.size():
		for j in range(i + 1, curves.size()):
			if groups[i] != groups[j]:
				continue
			root_gap += curves[i][1].distance_to(curves[j][1])
			tip_gap += curves[i][curves[i].size() - 1].distance_to(curves[j][curves[j].size() - 1])
			pairs += 1
	assert_gt(tip_gap, root_gap * 3.0, "tufts open towards the tips")
	# S: the elevation of the path turns up, then back down, then up again (>= 2 inflections)
	var path := HairRibbons.s_path(root, dir.normalized(), 10.0, 24, 0.75, 0.42, 0.0)
	var elev := PackedFloat32Array()
	for k in range(1, path.size()):
		var seg := (path[k] - path[k - 1]).normalized()
		elev.append(asin(seg.y))
	var turns := 0
	for k in range(2, elev.size()):
		if signf(elev[k] - elev[k - 1]) != signf(elev[k - 1] - elev[k - 2]):
			turns += 1
	assert_gte(turns, 2, "S-shaped heading")


func test_hair_link_strands_end_at_their_points_and_are_marked() -> void:
	var root := Vector3(0, 1.6, -0.2)
	var dir := Vector3(0, 0.55, -0.83)
	var ends := PackedVector3Array([Vector3(-1.2, 3.8, -1.6), Vector3(0.9, 4.6, -2.6)])
	var m := HairRibbons.nebula(root, dir, 7, 6, 8.0, ends)
	var curves: Array[PackedVector3Array] = m["curves"]
	var links: PackedInt32Array = m["links"]
	assert_eq(links.size(), 2, "one link strand per end point")
	for i in links.size():
		var curve := curves[links[i]]
		assert_almost_eq(curve[curve.size() - 1], ends[i], Vector3.ONE * 1e-4, "link strand ends at its point")
		assert_almost_eq(curve[0], root, Vector3.ONE * 1e-5, "link strand starts at the root")
		assert_gt((curve[1] - curve[0]).normalized().dot(dir.normalized()), 0.6, "leaves with the mass")
	var mesh := HairRibbons.build(curves, 0.08, 0.15, 24, Vector3.BACK, false, links, m["groups"])
	var arr := mesh.surface_get_arrays(0)
	var custom: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var colors: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	assert_eq(custom.size(), colors.size() * 4, "CUSTOM0 RGBA per vertex")
	assert_ne(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0, 0, "CUSTOM0 in the surface format")
	var per_curve := 24 * 2
	for c in curves.size():
		var tip := (c + 1) * per_curve - 1
		if links.has(c):
			assert_eq(custom[4 * c * per_curve], 1.0, "link flag on link strand %d" % c)
			assert_gte(colors[tip].a, HairRibbons.LINK_TIP_ALPHA - 1e-4, "link strand stays visible at its tip")
		else:
			assert_eq(custom[4 * c * per_curve], 0.0, "no link flag on strand %d" % c)
			assert_almost_eq(colors[tip].a, 0.0, 1e-4, "ordinary strand fades out")
		assert_between(custom[4 * c * per_curve + 2], 0.0, 1.0, "length share")
	_assert_winding(arr, "nebula hair")
	_assert_uv_range(arr[Mesh.ARRAY_TEX_UV], "nebula hair")


func test_orbit_line_phase_uv() -> void:
	var mesh := OrbitLine.build(4.0, 3.0, 0.05, 128)
	var arrays := _surface(mesh)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(verts.size(), 129 * 2)
	_assert_uv_range(uvs, "orbit band")
	_assert_winding(arrays, "orbit band")
	assert_almost_eq(OrbitLine.point(4.0, 3.0, 0.0), Vector3(0, 0, 3), Vector3.ONE * 1e-5, "phase 0 at +Z")
	assert_almost_eq(OrbitLine.point(4.0, 3.0, 0.25), Vector3(4, 0, 0), Vector3.ONE * 1e-5, "phase 0.25 at +X")
	for k in 129:
		assert_almost_eq(uvs[2 * k].x, float(k) / 128.0, 1e-5, "UV.x = phase")
		var mid := (verts[2 * k] + verts[2 * k + 1]) * 0.5
		assert_almost_eq(mid, OrbitLine.point(4.0, 3.0, float(k) / 128.0), Vector3.ONE * 1e-4)
	var tube := OrbitLine.build_tube(4.0, 3.0, 0.02, 128, 4)
	var tarr := _surface(tube)
	_assert_uv_range(tarr[Mesh.ARRAY_TEX_UV], "orbit tube")
	_assert_winding(tarr, "orbit tube")
	var line := OrbitLine.build_line(2.0, 2.0, 64)
	assert_eq(line.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINE_STRIP)
	var lv: PackedVector3Array = line.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_almost_eq(lv[0], lv[64], Vector3.ONE * 1e-5, "line closes")


func test_planet_sphere_counts_uv_and_tangents() -> void:
	for level in 4:
		var s := PlanetSphere.segments_for_level(level)
		var mesh := PlanetSphere.build_for_level(1.6, level)
		var arrays := _surface(mesh)
		assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3,
			PlanetSphere.triangle_count(s.x, s.y), "level %d triangle count" % level)
	assert_lt(PlanetSphere.triangle_count(48, 24), PlanetSphere.triangle_count(128, 64), "LOW < ULTRA")
	var mesh := PlanetSphere.build(1.6, 32, 16)
	var arrays := _surface(mesh)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_assert_uv_range(arrays[Mesh.ARRAY_TEX_UV], "planet")
	_assert_winding(arrays, "planet")
	for v in verts:
		assert_almost_eq(v.length(), 1.6, 1e-4)
	assert_almost_eq(mesh.get_aabb().size, Vector3.ONE * 3.2, Vector3.ONE * 0.01, "AABB")
	# tangents agree with Godot's own MikkTSpace generation (direction and binormal sign)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_tangents()
	var ref: PackedFloat32Array = st.commit_to_arrays()[Mesh.ARRAY_TANGENT]
	var mine: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var row := 33
	var checked := 0
	var agree := 0
	for r in range(2, 15):
		for sct in range(1, 32):
			var i := r * row + sct
			checked += 1
			var t_mine := Vector3(mine[4 * i], mine[4 * i + 1], mine[4 * i + 2])
			var t_ref := Vector3(ref[4 * i], ref[4 * i + 1], ref[4 * i + 2])
			if t_mine.dot(t_ref) > 0.9 and signf(mine[4 * i + 3]) == signf(ref[4 * i + 3]):
				agree += 1
	assert_eq(agree, checked, "analytic tangents match SurfaceTool.generate_tangents")


func test_asteroid_field_transforms_in_ring_and_deterministic() -> void:
	var a := AsteroidField.transforms(300, 16.0, 19.0, 0.8, 5)
	var b := AsteroidField.transforms(300, 16.0, 19.0, 0.8, 5)
	assert_eq(a.size(), 300)
	assert_eq(a, b, "same seed -> same transforms")
	assert_ne(a, AsteroidField.transforms(300, 16.0, 19.0, 0.8, 6), "seed matters")
	var smallest := 1e9
	var largest := 0.0
	for t in a:
		var p := t.origin
		var r := Vector2(p.x, p.z).length()
		assert_between(r, 16.0 - 1e-4, 19.0 + 1e-4, "in the ring")
		assert_between(p.y, -0.4 - 1e-4, 0.4 + 1e-4, "within the thickness")
		var s := t.basis.get_scale().x
		smallest = minf(smallest, s)
		largest = maxf(largest, s)
		assert_between(s, 0.05 - 1e-4, 0.4 + 1e-4, "scale range")
	assert_gt(largest / smallest, 3.0, "varied scales")
	var mm := AsteroidField.build_multimesh(AsteroidField.rock_mesh(1), a)
	assert_eq(mm.instance_count, 300)
	assert_eq(mm.transform_format, MultiMesh.TRANSFORM_3D)
	assert_not_null(mm.mesh)


func test_asteroid_rock_mesh() -> void:
	var m1 := AsteroidField.rock_mesh(9, 1.0, 1)
	var m2 := AsteroidField.rock_mesh(9, 1.0, 1)
	var m3 := AsteroidField.rock_mesh(10, 1.0, 1)
	var arrays := _surface(m1)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, 80, "80 facets at subdivision 1")
	_assert_uv_range(arrays[Mesh.ARRAY_TEX_UV], "rock")
	_assert_winding(arrays, "rock")
	assert_eq(m2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_VERTEX], "deterministic")
	assert_ne(m3.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_VERTEX], "seed matters")
	var aabb := m1.get_aabb()
	assert_lt(aabb.size.y, aabb.size.x, "squashed irregular body")
	assert_lt(aabb.size.x, 2.4)


func test_relation_thread_arc() -> void:
	var a := Vector3(0, 6, -0.5)
	var b := Vector3(0, 1, 4)
	var pts := RelationThread.arc_points(a, b, 1.5, 40)
	assert_eq(pts.size(), 41)
	assert_almost_eq(pts[0], a, Vector3.ONE * 1e-5, "starts at a")
	assert_almost_eq(pts[40], b, Vector3.ONE * 1e-5, "ends at b")
	var mid := (a + b) * 0.5
	var apex := pts[20]
	assert_almost_eq(apex.distance_to(mid), 1.5, 1e-3, "apex height")
	assert_gt((apex - mid).dot(Vector3.UP), 0.0, "bulges towards up")
	var mesh := RelationThread.build(a, b, 1.5, 0.04, 40)
	var arrays := _surface(mesh)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	_assert_uv_range(uvs, "thread")
	_assert_winding(arrays, "thread")
	assert_almost_eq(uvs[0].x, 0.0, 1e-6)
	assert_almost_eq(uvs[uvs.size() - 1].x, 1.0, 1e-6)
	var cross := RelationThread.build_crossed(a, b, 1.5, 0.04, 40)
	var carr := _surface(cross)
	assert_eq((carr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 4 * 41, "two ribbons")
	_assert_uv_range(carr[Mesh.ARRAY_TEX_UV], "thread crossed")
	_assert_winding(carr, "thread crossed")
	var tube := RelationThread.build_tube(a, b, 1.5, 0.02, 40, 5)
	var tarr := _surface(tube)
	_assert_uv_range(tarr[Mesh.ARRAY_TEX_UV], "thread tube")
	_assert_winding(tarr, "thread tube")
	assert_eq(RelationThread.build(a, b, 1.5, 0.04, 40).surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
		arrays[Mesh.ARRAY_VERTEX], "deterministic")
