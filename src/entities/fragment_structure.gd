class_name FragmentStructure
extends Node3D
## The construct of the ORIGIN CHAMBER: 96 segments from StructureBlueprint, one MultiMesh per
## layer (instance k = segment layer_first_segment(l) + k), all with MaterialLibrary.structure()
## (use_custom_data). Owner: animator. The whole state is a function of Simulation.world +
## Simulation.time (Choreography); ambient drift of loose fragments uses real time.
##
##   hidden -> FRAGMENTS_EMITTED: fly out of the core to the scatter shell (raw, drifting)
##   STRUCTURE_SEEDED: BONE construction guides appear at each layer's radius
##   LAYER_ADDED(l): segments fly to the twisted assembly pose, EMBER edges while they fly
##   MATERIALS_APPLIED: finish raw -> dark metal          VERIFICATION: PALE flashes per check
##   STRUCTURE_FINALIZED: twist -> 0 (rings lock), ribs grow from the equator, EMBER arcs
##
## INSTANCE_CUSTOM: r = assembly, g = verify flash, b = selection/hover (BONE), a = build energy.
## Material uniforms owned here: finish, final_lock, energy (scan_* belong to VerificationArray).
## Selection: loose fragments pick as &"fragment_field" (one sphere per loose fragment, moved
## only when their pose changes); a fully seated layer picks as &"layer_<l>" (ring trimesh).

const SEED := 7
const FIELD_ID := &"fragment_field"
const PICK_LAYER := 2
const FRAGMENT_PICK_RADIUS := 0.3
## Ambient drift of loose fragments (world units / radians).
const DRIFT := 0.07
const SPIN := 0.28
const HIGHLIGHT_SPEED := 4.0

var blueprint: StructureBlueprint

var _mmi: Array[MultiMeshInstance3D] = []
var _mm: Array[MultiMesh] = []
var _ribs: MultiMeshInstance3D
var _guides: Array[MeshInstance3D] = []
var _guide_mats: Array[ShaderMaterial] = []
var _layer_bodies: Array[StaticBody3D] = []
var _layer_shapes: Array[CollisionShape3D] = []
var _frag_shapes: Array[CollisionShape3D] = []
var _material: ShaderMaterial

## Caches so MultiMesh buffers are only written when something changes.
var _custom_cache := PackedColorArray()
var _twist_cache := PackedFloat32Array()
var _moving := PackedByteArray()
var _frag_pick_on := PackedByteArray()
var _layer_pick_on := PackedByteArray()
var _layer_hl := PackedFloat32Array()
var _field_hl := 0.0
var _rib_xfs: Array[Transform3D] = []
var _rib_key := Vector2(-1, -1)
var _uniform_key := Vector3(-1, -1, -1)
var _force := true


func _ready() -> void:
	blueprint = StructureBlueprint.build(OriginChamberScript.LAYER_COUNT, SEED)
	_material = MaterialLibrary.structure()
	var n_layers := blueprint.layers.size()
	_layer_hl.resize(n_layers)
	_twist_cache.resize(n_layers)
	_layer_pick_on.resize(n_layers)
	for l in n_layers:
		_build_layer(l)
	_build_ribs()
	_build_fragment_picks()
	_custom_cache.resize(blueprint.segment_count_total())
	_moving.resize(blueprint.segment_count_total())
	_frag_pick_on.resize(blueprint.segment_count_total())
	Simulation.world_rebuilt.connect(_on_world_rebuilt)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


## Last INSTANCE_CUSTOM written for global segment i (r assembly, g flash, b highlight,
## a build energy). Mirrors the MultiMesh buffer (readable headless, for tests and debug).
func segment_state(i: int) -> Color:
	return _custom_cache[i]


func _on_world_rebuilt() -> void:
	_force = true


func _build_layer(l: int) -> void:
	var p := blueprint.segment_mesh_params(l)
	var layer := blueprint.layers[l]
	var n := int(layer["segment_count"])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshBuilder.annular_segment(p["r_in"], p["r_out"], p["height"], p["angle_span"], p["arc_steps"])
	mm.instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Layer%d" % l
	mmi.multimesh = mm
	mmi.material_override = _material
	# Loose fragments travel up to ~5 units out; keep culling stable while they fly.
	mmi.custom_aabb = AABB(Vector3(-5.5, -5.5, -5.5), Vector3(11, 11, 11))
	add_child(mmi)
	_mm.append(mm)
	_mmi.append(mmi)

	# Construction guide: thin BONE hairline at the layer's mid radius (seeded axis).
	var r_mid := (float(p["r_in"]) + float(p["r_out"])) * 0.5
	var guide := MeshInstance3D.new()
	guide.name = "Guide%d" % l
	guide.mesh = MeshBuilder.ring(r_mid, 0.05, 0.012, 96)
	guide.position.y = float(layer["y"])
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := MaterialLibrary.halo().duplicate() as ShaderMaterial
	gm.set_shader_parameter("color", Palette.BONE)
	gm.set_shader_parameter("strength", 0.0)
	guide.material_override = gm
	guide.visible = false
	add_child(guide)
	_guides.append(guide)
	_guide_mats.append(gm)

	# Pick: ring solid of the layer (hollow centre so the core stays pickable).
	var body := StaticBody3D.new()
	body.name = "PickLayer%d" % l
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("entity_id", OriginChamberScript.layer_entity(l))
	body.position.y = float(layer["y"])
	var shape := CollisionShape3D.new()
	shape.shape = MeshBuilder.ring(r_mid, float(p["r_out"]) - float(p["r_in"]), float(p["height"]), 48).create_trimesh_shape()
	shape.disabled = true
	body.add_child(shape)
	add_child(body)
	_layer_bodies.append(body)
	_layer_shapes.append(shape)


func _build_ribs() -> void:
	var p := blueprint.rib_mesh_params()
	_rib_xfs = blueprint.rib_transforms()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshBuilder.rib(p["height"], p["width"], p["depth"])
	mm.instance_count = _rib_xfs.size()
	_ribs = MultiMeshInstance3D.new()
	_ribs.name = "Ribs"
	_ribs.multimesh = mm
	_ribs.material_override = _material
	_ribs.visible = false
	add_child(_ribs)


func _build_fragment_picks() -> void:
	var body := StaticBody3D.new()
	body.name = "PickFragments"
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("entity_id", FIELD_ID)
	var sphere := SphereShape3D.new()
	sphere.radius = FRAGMENT_PICK_RADIUS
	for i in blueprint.segment_count_total():
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		shape.disabled = true
		body.add_child(shape)
		_frag_shapes.append(shape)
	add_child(body)


func _update(delta: float) -> void:
	var w := Simulation.world
	var t := Simulation.time
	var rt := Time.get_ticks_msec() * 0.001
	var emitted := w.fragments_at >= 0.0
	var twist := Choreography.twist_amount(w, t)
	var force := _force
	_force = false

	# Material-wide uniforms (shared instance): only when they change.
	var uni := Vector3(Choreography.finish(w, t), Choreography.final_lock(w, t), 1.0)
	if force or not uni.is_equal_approx(_uniform_key):
		_uniform_key = uni
		_material.set_shader_parameter("finish", uni.x)
		_material.set_shader_parameter("final_lock", uni.y)
		_material.set_shader_parameter("energy", uni.z)

	# Is any emitted fragment still loose (not seated)? Decides what "fragment_field" highlights.
	var any_loose := false
	if emitted:
		for l in blueprint.layers.size():
			var seated_at := Choreography.layer_seated_at(w.layer_times[l])
			any_loose = any_loose or seated_at < 0.0 or t < seated_at
	var field_target := 0.0
	if Session.selected == FIELD_ID:
		field_target = 1.0
	elif Session.hovered == FIELD_ID:
		field_target = 0.55
	_field_hl = _approach(_field_hl, field_target, delta)
	for l in blueprint.layers.size():
		_update_layer(l, w, t, rt, delta, twist, emitted, any_loose, force)
	_update_ribs(w, t, force)


func _approach(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, delta * HIGHLIGHT_SPEED) if delta > 0.0 else target


func _update_layer(l: int, w: WorldState, t: float, rt: float, delta: float, twist: float,
		emitted: bool, any_loose: bool, force: bool) -> void:
	var layer := blueprint.layers[l]
	var n := int(layer["segment_count"])
	var first := int(layer["first_segment"])
	var y := float(layer["y"])
	var layer_at: float = w.layer_times[l] if l < w.layer_times.size() else -1.0
	var seated_at := Choreography.layer_seated_at(layer_at)
	var seated := seated_at >= 0.0 and t >= seated_at
	var mm := _mm[l]
	_mmi[l].visible = emitted

	# Guide (seeded axis).
	var g := Choreography.guide_strength(w, l, t)
	_guides[l].visible = g > 0.002
	if _guides[l].visible:
		_guide_mats[l].set_shader_parameter("strength", g)

	# Layer pick only when the whole ring is seated.
	var pick_on := 1 if seated else 0
	if force or _layer_pick_on[l] != pick_on:
		_layer_pick_on[l] = pick_on
		_layer_shapes[l].set_deferred("disabled", not seated)

	if not emitted:
		for k in n:
			var i0 := first + k
			if _frag_pick_on[i0] != 0:
				_frag_pick_on[i0] = 0
				_frag_shapes[i0].set_deferred("disabled", true)
		return

	var id := OriginChamberScript.layer_entity(l)
	var hl_target := 1.0 if Session.selected == id else (0.55 if Session.hovered == id else 0.0)
	_layer_hl[l] = _approach(_layer_hl[l], hl_target, delta)
	var flash := Choreography.check_flash(w, t, y)
	var twist_changed := force or not is_equal_approx(_twist_cache[l], twist)
	_twist_cache[l] = twist
	var pivot := blueprint.segment_pivot(l)

	for k in n:
		var i := first + k
		var a := Choreography.assembly(k, n, layer_at, t)
		# Field highlight: loose fragments, or the whole construct once nothing is loose.
		var hl := maxf(_layer_hl[l], _field_hl if (a < 1.0 or not any_loose) else 0.0)
		var custom := Color(a, flash, hl, Choreography.build_energy(k, n, layer_at, t))
		if force or not custom.is_equal_approx(_custom_cache[i]):
			_custom_cache[i] = custom
			mm.set_instance_custom_data(k, custom)
		if a >= 1.0:
			if twist_changed or _moving[i] != 0:
				mm.set_instance_transform(k, blueprint.segment_transform(i, twist))
				_moving[i] = 0
			if _frag_pick_on[i] != 0:
				_frag_pick_on[i] = 0
				_frag_shapes[i].set_deferred("disabled", true)
			continue
		# Loose or flying: pose from the scatter (after the flight out of the core) to the
		# assembly pose, with real-time drift fading out as the fragment seats.
		var xf: Transform3D
		if a > 0.0:
			xf = blueprint.assembly_transform(i, a, twist)
		else:
			xf = _emission_pose(i, l, Choreography.emission(i, w, t))
		var centre := xf * pivot
		if _frag_pick_on[i] == 0:
			_frag_pick_on[i] = 1
			_frag_shapes[i].set_deferred("disabled", false)
		if not _frag_shapes[i].position.is_equal_approx(centre):
			_frag_shapes[i].position = centre
		var dw := 1.0 - a
		var ph := float(i) * 1.618
		var drift := Vector3(sin(rt * 0.37 + ph), 1.3 * sin(rt * 0.29 + ph * 1.7), cos(rt * 0.33 + ph * 0.6)) * (DRIFT * dw)
		var spin := Basis(Vector3(sin(ph), 0.6, cos(ph * 1.3)).normalized(), sin(rt * 0.21 + ph) * SPIN * dw)
		var basis := spin * xf.basis
		mm.set_instance_transform(k, Transform3D(basis, centre + drift - basis * pivot))
		_moving[i] = 1


## Pose of fragment i during its flight out of the core (e = 0 at the core, 1 at scatter).
func _emission_pose(i: int, l: int, e: float) -> Transform3D:
	var s := blueprint.scatter_transform(i)
	if e >= 1.0:
		return s
	var pivot := blueprint.segment_pivot(l)
	var end := s * pivot
	var start := end.normalized() * (StructureBlueprint.CORE_RADIUS * 0.8)
	var basis := s.basis.scaled(Vector3.ONE * lerpf(0.08, 1.0, e))
	return Transform3D(basis, start.lerp(end, e) - basis * pivot)


func _update_ribs(w: WorldState, t: float, force: bool) -> void:
	var key := Vector2(Choreography.rib_growth(w, t), Choreography.rib_energy(w, t))
	_ribs.visible = key.x > 0.001
	if not _ribs.visible or (not force and key.is_equal_approx(_rib_key)):
		return
	_rib_key = key
	var mm := _ribs.multimesh
	for r in _rib_xfs.size():
		var xf := _rib_xfs[r]
		# Grow from the equator (the rib mesh is centred on its own origin).
		mm.set_instance_transform(r, Transform3D(xf.basis.scaled_local(Vector3(1.0, key.x, 1.0)), xf.origin))
		mm.set_instance_custom_data(r, Color(1.0, 0.0, 0.0, key.y))
