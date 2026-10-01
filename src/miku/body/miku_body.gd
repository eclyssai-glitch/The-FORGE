class_name MikuBody
extends Node3D
## Thin adapter between MIKU's runtime and her rig (Loop 5). Owner: animator.
## Builds the rig — the procedural-modeler's `MikuRig.build()` when that class exists in the
## project, else the development stand-in MikuMannequin (docs/ANIMATION.md, "Living —
## integration") — finds its Skeleton3D, resolves the bones (RigBones) and owns the MikuMotor
## that poses it. Also: the halo behind her head, her pick body (entity `miku`, layer 2) and the
## APPEARANCE values with real support, each eased by a spring so a change is seen happening:
##   height          -> scale of this node (the whole figure)
##   shoulder_width  -> offset of the upper arms from the clavicles (pose position)
##   neck_length     -> offset of the head from the neck (pose position)
##   chest_volume    -> uniform scale of the chest bone (its children counter-scaled)
##   halo_radius     -> scale of the halo
##   glow            -> `glow` of the body material(s)

const ENTITY := &"miku"
const RIG_CLASS := &"MikuRig"
## Appearance easing [f, zeta]: a little overshoot, the body "settles" into its new shape.
const APPEARANCE_SPRING := Vector2(0.5, 0.55)
## Halo: radius (units) and where it sits relative to the head bone (rest model offset).
const HALO_RADIUS := 0.36
const HALO_OFFSET := Vector3(0.0, 0.3, -0.24)
## Pick capsule (model space): radius, height and centre.
const PICK_RADIUS := 0.6
const PICK_HEIGHT := 5.9
const PICK_CENTER := Vector3(0.0, -1.2, 0.0)

var rig_root: Node3D
var skeleton: Skeleton3D
var map: RigBones
var motor: MikuMotor
var using_fallback := false
var halo: MeshInstance3D
var pick_body: StaticBody3D
var body_materials: Array[Material] = []

var _app: Dictionary = {}
var _app_goal: Dictionary = {}
var _b_ua := PackedInt32Array([-1, -1])
var _b_head := -1
var _b_chest := -1
var _chest_children := PackedInt32Array()


func _init() -> void:
	name = "MikuBody"
	rig_root = build_rig()
	using_fallback = rig_root.name.begins_with("MikuMannequin")
	add_child(rig_root)
	skeleton = find_skeleton(rig_root)
	if skeleton == null:
		push_warning("MikuBody: the rig has no Skeleton3D; using the stand-in.")
		rig_root.queue_free()
		rig_root = MikuMannequin.build()
		using_fallback = true
		add_child(rig_root)
		skeleton = find_skeleton(rig_root)
	map = RigBones.new(skeleton)
	motor = MikuMotor.new(skeleton, map)
	_b_ua[0] = map.bone("upper_arm.L")
	_b_ua[1] = map.bone("upper_arm.R")
	_b_head = map.bone("head")
	_b_chest = map.bone("chest")
	if _b_chest >= 0:
		for b in skeleton.get_bone_count():
			if skeleton.get_bone_parent(b) == _b_chest:
				_chest_children.append(b)
	for k: String in MikuParams.APPEARANCE_DEFAULTS:
		var v: float = MikuParams.APPEARANCE_DEFAULTS[k]
		_app[k] = SecondOrder.new(APPEARANCE_SPRING.x, APPEARANCE_SPRING.y, 0.0, v)
		_app_goal[k] = v
	_collect_materials()
	_build_halo()
	_build_pick()


func _ready() -> void:
	set_meta(&"entity_id", ENTITY)


## Path of a global script class (`class_name`) or "" when the project has none by that name.
static func global_class_path(cls: StringName) -> String:
	for c in ProjectSettings.get_global_class_list():
		if StringName(c["class"]) == cls:
			return String(c["path"])
	return ""


## The procedural-modeler's MikuRig.build() when present, else the development stand-in.
static func build_rig() -> Node3D:
	var path := global_class_path(RIG_CLASS)
	if path != "":
		var script := load(path) as Script
		if script != null:
			var n: Variant = script.call(&"build")
			if n is Node3D:
				return n
	return MikuMannequin.build()


static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := find_skeleton(c)
		if s != null:
			return s
	return null


## World -> rig model space (the space of every motor goal).
func to_model(world: Vector3) -> Vector3:
	return skeleton.global_transform.affine_inverse() * world


func to_world(model: Vector3) -> Vector3:
	return skeleton.global_transform * model


## World direction -> model direction.
func dir_to_model(world_dir: Vector3) -> Vector3:
	return (skeleton.global_transform.basis.inverse() * world_dir).normalized()


## New appearance goals (already clamped by MikuParams); the body eases into them.
func set_appearance(values: Dictionary) -> void:
	for k: String in values:
		if _app_goal.has(k):
			_app_goal[k] = float(values[k])


## Current (eased) appearance value.
func appearance(key: String) -> float:
	return (_app[key] as SecondOrder).y if _app.has(key) else 0.0


## True while some appearance value is still moving towards its goal.
func appearance_moving() -> bool:
	for k: String in _app:
		var s := _app[k] as SecondOrder
		if absf(s.y - float(_app_goal[k])) > 0.004 or absf(s.v) > 0.004:
			return true
	return false


func step(dt: float) -> void:
	for k: String in _app:
		(_app[k] as SecondOrder).step(float(_app_goal[k]), dt)
	_apply_appearance()
	motor.step(dt)
	_place_halo()


func _apply_appearance() -> void:
	var h := appearance("height")
	scale = Vector3.ONE * h
	var sw := appearance("shoulder_width")
	for s in 2:
		if _b_ua[s] >= 0:
			motor.rig.pos_scale[_b_ua[s]] = sw
	if _b_head >= 0:
		motor.rig.pos_scale[_b_head] = appearance("neck_length")
	if _b_chest >= 0:
		var cv := appearance("chest_volume")
		motor.rig.bone_scale[_b_chest] = cv
		for c in _chest_children:
			motor.rig.bone_scale[c] = 1.0 / maxf(cv, 0.01)
	if halo != null:
		halo.scale = Vector3.ONE * appearance("halo_radius")
	var g := appearance("glow")
	for m in body_materials:
		LivingMaterials.set_param(m, &"glow", g)


func _place_halo() -> void:
	if halo == null or motor.b_head < 0:
		return
	var rig := motor.rig
	var head_rest := rig.rest_gpos[motor.b_head]
	var p := rig.point_of(motor.b_head, head_rest + HALO_OFFSET)
	var q := rig.acc[motor.b_head]
	var t := skeleton.global_transform * Transform3D(Basis(q), p)
	halo.global_transform = Transform3D(t.basis.orthonormalized() * Basis(Vector3.RIGHT, PI * 0.5)
		.scaled(Vector3.ONE * appearance("halo_radius") * scale.x), t.origin)


func _collect_materials() -> void:
	if using_fallback:
		body_materials.append(LivingMaterials.get_material(&"body"))
		return
	for mi in rig_root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override
		if m == null and (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (mi as MeshInstance3D).mesh.surface_get_material(0)
		if m != null and not body_materials.has(m):
			body_materials.append(m)


func _build_halo() -> void:
	halo = MeshInstance3D.new()
	halo.name = "Halo"
	var t := TorusMesh.new()
	t.inner_radius = HALO_RADIUS * 0.94
	t.outer_radius = HALO_RADIUS
	t.rings = 48
	t.ring_segments = 8
	halo.mesh = t
	halo.material_override = LivingMaterials.get_material(&"halo")
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	halo.top_level = true


func _build_pick() -> void:
	pick_body = StaticBody3D.new()
	pick_body.name = "Pick"
	pick_body.collision_layer = 2
	pick_body.collision_mask = 0
	pick_body.set_meta(&"entity_id", ENTITY)
	var shape := CollisionShape3D.new()
	var c := CapsuleShape3D.new()
	c.radius = PICK_RADIUS
	c.height = PICK_HEIGHT
	shape.shape = c
	shape.position = PICK_CENTER
	pick_body.add_child(shape)
	add_child(pick_body)
