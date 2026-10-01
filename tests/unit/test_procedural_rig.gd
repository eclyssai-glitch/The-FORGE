extends GutTest
## Loop 5 rigs: MikuRig (miku_rig.json over miku_body.obj) and HandRig (hand_rig.json over
## hand_left.obj, right = runtime mirror). Contract bone names and hierarchy, skin weights
## (normalised, <= 4, no orphan, only deforming bones), rest pose == sculpture, bone conventions
## (+X flexes), appearance bone scale, attachments and determinism.

const MESH_DIR := "res://assets/meshes/"

const MIKU_PARENTS := {
	"hips": "root", "spine": "hips", "chest": "spine", "ribcage": "chest", "neck": "chest",
	"head": "neck", "hair_root": "head",
	"clavicle.L": "chest", "upper_arm.L": "clavicle.L", "forearm.L": "upper_arm.L", "hand.L": "forearm.L",
	"clavicle.R": "chest", "upper_arm.R": "clavicle.R", "forearm.R": "upper_arm.R", "hand.R": "forearm.R",
	"thumb.0.L": "hand.L", "thumb.1.L": "thumb.0.L", "index.0.L": "hand.L", "index.1.L": "index.0.L",
	"middle.0.L": "hand.L", "middle.1.L": "middle.0.L", "ring.0.L": "hand.L", "ring.1.L": "ring.0.L",
	"thumb.0.R": "hand.R", "thumb.1.R": "thumb.0.R", "index.0.R": "hand.R", "index.1.R": "index.0.R",
	"middle.0.R": "hand.R", "middle.1.R": "middle.0.R", "ring.0.R": "hand.R", "ring.1.R": "ring.0.R",
	"skirt.0": "hips", "skirt.1": "skirt.0", "skirt.2": "skirt.1",
}
const HAND_PARENTS := {
	"palm": "wrist", "palm_center": "palm",
	"thumb.0": "palm", "thumb.1": "thumb.0", "thumb.2": "thumb.1", "thumb.tip": "thumb.2",
	"index.0": "palm", "index.1": "index.0", "index.2": "index.1", "index.tip": "index.2",
	"middle.0": "palm", "middle.1": "middle.0", "middle.2": "middle.1",
	"ring.0": "palm", "ring.1": "ring.0", "ring.2": "ring.1",
	"little.0": "palm", "little.1": "little.0", "little.2": "little.1",
}


func _rigs() -> Array[RigData]:
	return [MikuRig.data(), HandRig.data(HandRig.Side.LEFT), HandRig.data(HandRig.Side.RIGHT)]


func _bone_global(sk: Skeleton3D, bone: String) -> Transform3D:
	return RigData.global_poses(sk)[sk.find_bone(bone)]


# ------------------------------------------------------------------ skeleton

func test_contract_bones_present_and_hierarchy() -> void:
	var rig := MikuRig.build()
	var sk := MikuRig.get_skeleton(rig)
	assert_not_null(sk, "MikuRig has a Skeleton3D")
	for b: String in MikuRig.CONTRACT_BONES:
		assert_gt(sk.find_bone(b), -1, "MIKU bone %s" % b)
	assert_eq(sk.get_bone_parent(sk.find_bone("root")), -1, "root is the only root")
	assert_eq(sk.get_parentless_bones().size(), 1, "one root bone")
	for b: String in MIKU_PARENTS:
		var i := sk.find_bone(b)
		assert_gt(i, -1, "bone %s" % b)
		assert_eq(sk.get_bone_name(sk.get_bone_parent(i)), MIKU_PARENTS[b], "%s parent" % b)
	rig.free()
	for side in [HandRig.Side.LEFT, HandRig.Side.RIGHT]:
		var h := HandRig.build(side)
		var hs := HandRig.get_skeleton(h)
		for b: String in HandRig.CONTRACT_BONES:
			assert_gt(hs.find_bone(b), -1, "hand bone %s" % b)
		assert_eq(hs.get_bone_parent(hs.find_bone("wrist")), -1, "wrist is the hand root")
		for b: String in HAND_PARENTS:
			assert_eq(hs.get_bone_name(hs.get_bone_parent(hs.find_bone(b))), HAND_PARENTS[b], "hand %s parent" % b)
		h.free()


func test_tree_layout_and_skin() -> void:
	var rig := MikuRig.build(StandardMaterial3D.new())
	assert_eq(rig.name, StringName("MikuRig"))
	var mi := MikuRig.get_mesh_instance(rig)
	assert_not_null(mi, "skinned MeshInstance3D under the skeleton")
	assert_not_null(mi.skin, "skin set")
	assert_eq(mi.skeleton, NodePath(".."), "mesh points at its skeleton")
	assert_true(mi.material_override is StandardMaterial3D, "caller's material applied")
	assert_eq(mi.skin.get_bind_count(), MikuRig.get_skeleton(rig).get_bone_count(), "one bind per bone")
	var arrays := mi.mesh.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size(), 4 * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		"ARRAY_BONES has 4 influences per vertex")
	var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var worst := 0.0
	for v in range(0, w.size(), 4):
		worst = maxf(worst, absf(w[v] + w[v + 1] + w[v + 2] + w[v + 3] - 1.0))
	assert_lt(worst, 1e-3, "weights stay normalised after Godot's 16-bit packing")
	var rig2 := MikuRig.build()
	assert_same(MikuRig.get_mesh_instance(rig2).mesh, mi.mesh, "instances share one mesh")
	assert_same(MikuRig.get_mesh_instance(rig2).skin, mi.skin, "instances share one skin")
	rig.free()
	rig2.free()


func test_rest_frames_are_proper_rotations_along_the_bones() -> void:
	for d in _rigs():
		for i in d.bone_count():
			var b := d.global_rests[i].basis
			assert_almost_eq(b.determinant(), 1.0, 1e-4, "%s %s proper rotation" % [d.rig_name, d.bone_names[i]])
			if d.tails[i].distance_to(d.global_rests[i].origin) > 1e-4:
				var along := (d.tails[i] - d.global_rests[i].origin).normalized()
				assert_gt(along.dot(b.y.normalized()), 0.98, "%s %s +Y towards the tail" % [d.rig_name, d.bone_names[i]])
	# chains: +Y points exactly at the next joint
	var chains := {"miku_rig": [["hips", "spine"], ["spine", "chest"], ["chest", "neck"], ["neck", "head"],
		["clavicle.L", "upper_arm.L"], ["upper_arm.L", "forearm.L"], ["forearm.R", "hand.R"],
		["index.0.L", "index.1.L"], ["thumb.0.R", "thumb.1.R"], ["skirt.0", "skirt.1"], ["skirt.1", "skirt.2"]],
		"hand_rig": [["thumb.0", "thumb.1"], ["thumb.1", "thumb.2"], ["index.0", "index.1"], ["index.1", "index.2"],
		["little.1", "little.2"]]}
	for d: RigData in [MikuRig.data(), HandRig.data(HandRig.Side.RIGHT)]:
		var key := "miku_rig" if d == MikuRig.data() else "hand_rig"
		for pair: Array in chains[key]:
			var a := d.global_rests[d.bone_index(pair[0])]
			var nxt := d.global_rests[d.bone_index(pair[1])].origin
			assert_gt((nxt - a.origin).normalized().dot(a.basis.y.normalized()), 0.9999,
				"%s %s +Y points at %s" % [d.rig_name, pair[0], pair[1]])


# ------------------------------------------------------------------ weights

func test_weights_normalised_max_four_no_orphans() -> void:
	for d in _rigs():
		var n := d.vertices.size()
		assert_eq(d.bones.size(), 4 * n, "%s 4 bone slots per vertex" % d.rig_name)
		var bad_sum := 0
		var orphan := 0
		var bad_bone := 0
		var used := {}
		for v in n:
			var s := 0.0
			var cnt := 0
			for j in 4:
				var w := d.weights[4 * v + j]
				var b := d.bones[4 * v + j]
				if w < 0.0 or b < 0 or b >= d.bone_count():
					bad_bone += 1
				if w > 0.0:
					cnt += 1
					used[b] = true
					if not d.bone_deform[b]:
						bad_bone += 1
				s += w
			if absf(s - 1.0) > 1e-4:
				bad_sum += 1
			if cnt == 0:
				orphan += 1
		assert_eq(bad_sum, 0, "%s weights sum to 1" % d.rig_name)
		assert_eq(orphan, 0, "%s no orphan vertex" % d.rig_name)
		assert_eq(bad_bone, 0, "%s only valid deforming bones, non-negative weights" % d.rig_name)
		for i in d.bone_count():
			if d.bone_deform[i]:
				assert_true(used.has(i), "%s deforming bone %s skins vertices" % [d.rig_name, d.bone_names[i]])


# ------------------------------------------------------------------ rest pose = sculpture

func _obj_vertices(path: String, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached() and out.size() < count:
		var line := f.get_line()
		if line.begins_with("v "):
			var p := line.split(" ", false)
			out.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
	return out


func test_rest_pose_is_the_sculpture() -> void:
	for pair in [[MikuRig.data(), "miku_body"], [HandRig.data(), "hand_left"]]:
		var d: RigData = pair[0]
		var src: String = MESH_DIR + String(pair[1]) + ".obj"
		assert_eq(String(d.meta["source_sha256"]), FileAccess.get_sha256(src), "%s baked from the current %s" % [d.rig_name, src])
		var obj := _obj_vertices(src, d.vertices.size())
		assert_eq(obj.size(), d.vertices.size(), "%s same vertex count as the OBJ" % d.rig_name)
		var err := 0.0
		for i in obj.size():
			err = maxf(err, obj[i].distance_to(d.vertices[i]))
		assert_lt(err, 1e-4, "%s rig vertices == OBJ vertices" % d.rig_name)
		# skinning the rest pose of a freshly built skeleton reproduces the mesh
		var node := d.instantiate("check")
		var skinned := d.skin_vertices(RigData.global_poses(RigData.skeleton_of(node)))
		var e2 := 0.0
		for i in skinned.size():
			e2 = maxf(e2, skinned[i].distance_to(d.vertices[i]))
		assert_lt(e2, 1e-4, "%s rest pose skinning == sculpture" % d.rig_name)
		node.free()


# ------------------------------------------------------------------ conventions

func test_positive_x_flexes() -> void:
	var rig := MikuRig.build()
	var sk := MikuRig.get_skeleton(rig)
	for s in [".L", ".R"]:
		var before := _bone_global(sk, "hand" + s).origin.distance_to(_bone_global(sk, "upper_arm" + s).origin)
		RigData.pose_local(sk, sk.find_bone("forearm" + s), Vector3(0.8, 0, 0))
		var after := _bone_global(sk, "hand" + s).origin.distance_to(_bone_global(sk, "upper_arm" + s).origin)
		assert_lt(after, before - 0.05, "forearm%s +X bends the elbow" % s)
	var face0 := _bone_global(sk, "head").basis.z
	RigData.pose_local(sk, sk.find_bone("head"), Vector3(0.4, 0, 0))
	assert_lt(_bone_global(sk, "head").basis.z.y, face0.y - 0.2, "head +X nods forward/down")
	rig.free()
	for side in [HandRig.Side.LEFT, HandRig.Side.RIGHT]:
		var h := HandRig.build(side)
		var hs := HandRig.get_skeleton(h)
		var palm_n := _bone_global(hs, "palm_center").basis.y
		for f: String in HandRig.FINGERS:
			var b0 := _bone_global(hs, f + ".0")
			assert_gt(b0.basis.z.normalized().dot(palm_n), 0.3, "side %d: %s.0 +Z on the palm side" % [side, f])
			var j0 := _bone_global(hs, f + ".1").origin
			RigData.pose_local(hs, hs.find_bone(f + ".0"), Vector3(0.2, 0, 0))
			var j1 := _bone_global(hs, f + ".1").origin
			assert_gt((j1 - j0).normalized().dot(b0.basis.z.normalized()), 0.9, "side %d: +X flexes %s" % [side, f])
		hs.reset_bone_poses()
		assert_gt(palm_n.y, 0.95, "side %d: palm faces +Y" % side)
		var thumb_z := _bone_global(hs, "thumb.tip").origin.z
		if side == HandRig.Side.LEFT:
			assert_lt(thumb_z, -0.5, "left thumb towards -Z")
		else:
			assert_gt(thumb_z, 0.5, "right thumb towards +Z")
		h.free()


func test_right_hand_is_the_mirror_of_the_left() -> void:
	var l := HandRig.data(HandRig.Side.LEFT)
	var r := HandRig.data(HandRig.Side.RIGHT)
	assert_eq(r.vertices.size(), l.vertices.size())
	for i in range(0, l.vertices.size(), 97):
		assert_almost_eq(r.vertices[i], l.vertices[i] * Vector3(1, 1, -1), Vector3.ONE * 1e-6, "vertex %d mirrored" % i)
	for i in l.bone_count():
		assert_almost_eq(r.global_rests[i].origin, l.global_rests[i].origin * Vector3(1, 1, -1), Vector3.ONE * 1e-5)
	# winding flipped: the face normal of the mirrored triangle still agrees with its normals
	var t := 300
	var a := r.vertices[r.indices[3 * t]]
	var b := r.vertices[r.indices[3 * t + 1]]
	var c := r.vertices[r.indices[3 * t + 2]]
	var fn := (c - a).cross(b - a)   # Godot front faces are clockwise
	assert_gt(fn.dot(r.normals[r.indices[3 * t]]), 0.0, "mirrored winding stays front-facing")


# ------------------------------------------------------------------ appearance

func _skinned(rig: Node3D) -> PackedVector3Array:
	return MikuRig.data().skin_vertices(RigData.global_poses(MikuRig.get_skeleton(rig)))


func _region(d: RigData, bone: String) -> PackedInt32Array:
	var b := d.bone_index(bone)
	var out := PackedInt32Array()
	for v in d.vertices.size():
		if d.bones[4 * v] == b and d.weights[4 * v] > 0.99:
			out.append(v)
	return out


func test_appearance_scales_bones_and_deforms_the_mesh() -> void:
	var d := MikuRig.data()
	var rig := MikuRig.build()
	var rest := _skinned(rig)
	var head := _region(d, "head")
	var rib := _region(d, "ribcage")
	var arm := _region(d, "upper_arm.L")
	assert_gt(head.size(), 100)
	assert_gt(rib.size(), 100)
	MikuRig.apply_appearance(rig, {"neck_length": 1.25})
	var p := _skinned(rig)
	var neck_axis := d.global_rests[d.bone_index("neck")].basis.y.normalized()
	var dy := (p[head[0]] - rest[head[0]]).dot(neck_axis)
	var neck_len := d.global_rests[d.bone_index("head")].origin.distance_to(d.global_rests[d.bone_index("neck")].origin)
	assert_almost_eq(dy, neck_len * 0.25, 0.01, "neck_length 1.25 lifts the head by a quarter neck")
	MikuRig.apply_appearance(rig, {"chest_volume": 1.2})
	p = _skinned(rig)
	var w0 := 0.0
	var w1 := 0.0
	for v in rib:
		w0 = maxf(w0, absf(rest[v].x))
		w1 = maxf(w1, absf(p[v].x))
	assert_gt(w1, w0 * 1.1, "chest_volume widens the chest")
	assert_almost_eq(p[head[0]], rest[head[0]], Vector3.ONE * 1e-4, "neck_length back to default when not given")
	MikuRig.apply_appearance(rig, {"shoulder_width": 1.15})
	p = _skinned(rig)
	assert_gt(p[arm[0]].x, rest[arm[0]].x + 0.02, "shoulder_width moves the left arm out")
	MikuRig.apply_appearance(rig, {"height": 1.1})
	p = _skinned(rig)
	assert_almost_eq(p[head[0]].y, rest[head[0]].y * 1.1, 1e-3, "height scales the figure from the root")
	var clamped := MikuRig.apply_appearance(rig, {"height": 9.0, "chest_volume": -3.0})
	assert_eq(float(clamped["height"]), float(MikuRig.APPEARANCE["height"]["max"]), "clamped to the safe range")
	assert_eq(float(clamped["chest_volume"]), float(MikuRig.APPEARANCE["chest_volume"]["min"]))
	# pose rotations survive an appearance change and resets keep the appearance
	var sk := MikuRig.get_skeleton(rig)
	RigData.pose_local(sk, sk.find_bone("head"), Vector3(0.3, 0, 0))
	var q := sk.get_bone_pose_rotation(sk.find_bone("head"))
	MikuRig.apply_appearance(rig, {"neck_length": 1.2})
	assert_eq(sk.get_bone_pose_rotation(sk.find_bone("head")), q, "appearance keeps pose rotations")
	sk.reset_bone_poses()
	var h_after := _skinned(rig)[head[0]]
	MikuRig.apply_appearance(rig, {"neck_length": 1.2})
	assert_almost_eq(_skinned(rig)[head[0]], h_after, Vector3.ONE * 1e-5, "reset_bone_poses keeps the appearance")
	MikuRig.apply_appearance(rig, {})
	p = _skinned(rig)
	var err := 0.0
	for i in range(0, p.size(), 13):
		err = maxf(err, p[i].distance_to(rest[i]))
	assert_lt(err, 1e-4, "default appearance == sculpture")
	rig.free()


# ------------------------------------------------------------------ limit poses

func _max_edge_stretch(d: RigData, posed: PackedVector3Array) -> float:
	var worst := 0.0
	for t in range(0, d.indices.size(), 3):
		for k in 3:
			var a := d.indices[t + k]
			var b := d.indices[t + (k + 1) % 3]
			var l0 := d.vertices[a].distance_to(d.vertices[b])
			if l0 > 0.004:   # skip sliver edges (their ratio says nothing about the surface)
				worst = maxf(worst, posed[a].distance_to(posed[b]) / l0)
	return worst


func test_limit_poses_do_not_tear() -> void:
	var rig := MikuRig.build()
	var sk := MikuRig.get_skeleton(rig)
	var d := MikuRig.data()
	RigData.pose_local(sk, sk.find_bone("neck"), Vector3(0.0, 0.5, 0.15))
	RigData.pose_local(sk, sk.find_bone("head"), Vector3(0.2, 0.7, 0.35))
	RigData.pose_local(sk, sk.find_bone("forearm.L"), Vector3(1.9, 0, 0))
	RigData.pose_local(sk, sk.find_bone("upper_arm.R"), Vector3(0.3, 0, -1.9))
	RigData.pose_local(sk, sk.find_bone("skirt.1"), Vector3(0.2, 0, 0.15))
	for f in ["index", "middle", "ring", "little"]:
		RigData.pose_local(sk, sk.find_bone(f + ".0.L"), Vector3(1.3, 0, 0))
		RigData.pose_local(sk, sk.find_bone(f + ".1.L"), Vector3(1.7, 0, 0))
	var posed := d.skin_vertices(RigData.global_poses(sk))
	var stretch := _max_edge_stretch(d, posed)
	assert_lt(stretch, 5.0, "MIKU limit pose: no edge pulled apart (max stretch %.2f)" % stretch)
	rig.free()
	var h := HandRig.build(HandRig.Side.RIGHT)
	for f: String in HandRig.FINGERS:
		HandRig.pose_finger(h, f, 1.0)
	var hd := HandRig.data(HandRig.Side.RIGHT)
	var hp := hd.skin_vertices(RigData.global_poses(HandRig.get_skeleton(h)))
	var hs := _max_edge_stretch(hd, hp)
	assert_lt(hs, 5.0, "hand fist: no edge pulled apart (max stretch %.2f)" % hs)
	h.free()


# ------------------------------------------------------------------ attachments, determinism

func test_hair_attaches_to_the_head_and_follows_it() -> void:
	var rig := MikuRig.build()
	add_child_autofree(rig)
	var marker := Node3D.new()
	var ba := MikuRig.attach(rig, "hair_root", marker)
	assert_eq(ba.bone_name, "hair_root")
	var sk := MikuRig.get_skeleton(rig)
	var hr: Dictionary = MikuRig.data().meta["anchors_local"]["hair_root"]
	assert_eq(String(hr["bone"]), "head", "hair root anchor rides the head")
	RigData.pose_local(sk, sk.find_bone("head"), Vector3(0.0, 0.8, 0.0))
	await wait_physics_frames(3)
	var want := sk.global_transform * _bone_global(sk, "hair_root").origin
	assert_almost_eq(marker.global_position, want, Vector3.ONE * 1e-3, "attachment follows the turned head")
	var rest_root := MikuRig.data().global_rests[sk.find_bone("hair_root")].origin
	assert_gt(marker.global_position.distance_to(rest_root), 0.05, "hair root moved with the head")
	assert_almost_eq(MikuRig.anchor(rig, "hair_root"), want, Vector3.ONE * 1e-3, "anchor() == attachment")


func test_build_is_deterministic() -> void:
	var a := RigData.new()
	var b := RigData.new()
	assert_true(a._load("miku_rig") and b._load("miku_rig"), "rig files load")
	assert_eq(a.vertices, b.vertices)
	assert_eq(a.bones, b.bones)
	assert_eq(a.weights, b.weights)
	assert_eq(a.indices, b.indices)
	var s1 := MikuRig.get_skeleton(MikuRig.build())
	var s2 := MikuRig.get_skeleton(MikuRig.build())
	for i in s1.get_bone_count():
		assert_eq(s1.get_bone_rest(i), s2.get_bone_rest(i), "same rest for %s" % s1.get_bone_name(i))
	s1.get_parent().free()
	s2.get_parent().free()
	assert_same(RigData.load_rig("hand_rig").mirror_z(), HandRig.data(HandRig.Side.RIGHT), "mirror built once")
