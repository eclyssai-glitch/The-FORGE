class_name MikuBody
extends Node3D
## Thin adapter between MIKU's runtime and her rig (Loop 5). Owner: animator.
## PROTOTYPE BOUNDARY (Owner decision, Loop 5 r1): the runtime (Miku: mind, actions, hands,
## threads, world) talks to the body ONLY through the "Body goals" and "Body queries" sections
## below, in WORLD space. Everything behind them — MikuMotor, PoseRig, LimbIK, FingerSet, ArmChannel
## (manual bone math) — is a spike to be replaced by Godot's native stack (AnimationTree,
## LookAtModifier3D, TwoBoneIK3D, SpringBoneSimulator3D...) without touching the runtime.
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
## Movement backends (Loop 5 r2, native migration; docs/ANIMATION.md "LIVING — migração nativa").
## Per layer: `legacy` = the round-1 manual bone code (MikuMotor/PoseRig/LimbIK/ArmChannel/
## FingerSet, kept until every comparison is done), `native` = Godot's stack. Layers migrate one
## step at a time; a layer without a native implementation yet always runs legacy.
##   torso      mood states, composure grade, posture, weight, breath, emotional timing
##              (AnimationTree, MikuDirector) — STEP 1
##   gaze       eyes -> head -> chest (LookAtModifier3D) — STEP 2 (not yet: legacy)
##   arms       TwoBoneIK3D / Aim / twist — STEP 3 (not yet: legacy)
##   secondary  SpringBoneSimulator3D (skirt, fingers) — STEP 4 (not yet: legacy)
## Selection: command line (user args, after `--`) `--body=legacy|native` (every layer that has a
## native implementation) and `--body-<layer>=legacy|native`; tests set `override_backend`.
const LAYERS: Array[StringName] = [&"torso", &"gaze", &"arms", &"secondary"]
const NATIVE_LAYERS: Array[StringName] = [&"torso"]
const LEGACY := &"legacy"
const NATIVE := &"native"
## Backend when nothing is asked (the result of the STEP 1 comparison, docs/ANIMATION.md).
const DEFAULT_BACKEND := &"legacy"

## Tests / tools: when not empty, the backend of every layer (before any command-line choice).
static var override_backend: StringName = &""
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
## Native torso (layer `torso` = native), else null.
var director: MikuDirector
## Backend per layer (LAYERS -> LEGACY | NATIVE).
var layers: Dictionary = {}
var using_fallback := false
## CPU of the last step (µs): AnimationTree (director) and the manual motor.
var tree_us := 0
var motor_us := 0
var halo: MeshInstance3D
var pick_body: StaticBody3D
var body_materials: Array[Material] = []

var _app: Dictionary = {}
var _app_goal: Dictionary = {}
var _b_ua := PackedInt32Array([-1, -1])
var _b_head := -1
var _b_chest := -1
var _chest_children := PackedInt32Array()
var _rig_script: Script
var _applied_rig := {}


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
	motor.rig.manage_scale = using_fallback
	layers = choose_layers(OS.get_cmdline_user_args())
	if layers[&"torso"] == NATIVE:
		director = MikuDirector.new(skeleton, map)
		motor.torso_native = true
	if not using_fallback:
		_rig_script = load(global_class_path(RIG_CLASS)) as Script
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
			# MikuRig.build(material): the body material (placeholder until the art lands).
			var n: Variant = script.call(&"build", LivingMaterials.get_material(&"body"))
			if n is Node3D:
				return n
	return MikuMannequin.build()


## Backend of each layer from the command-line user args (and override_backend).
static func choose_layers(args: PackedStringArray) -> Dictionary:
	var all: StringName = override_backend if override_backend != &"" else DEFAULT_BACKEND
	var per := {}
	for a in args:
		if a.begins_with("--body="):
			all = StringName(a.get_slice("=", 1))
		elif a.begins_with("--body-"):
			per[StringName(a.trim_prefix("--body-").get_slice("=", 0))] = StringName(a.get_slice("=", 1))
	var out := {}
	for l in LAYERS:
		var b: StringName = per.get(l, all)
		if b != NATIVE and b != LEGACY:
			push_warning("MikuBody: unknown backend '%s' for layer %s (legacy)" % [b, l])
			b = LEGACY
		out[l] = b if NATIVE_LAYERS.has(l) else LEGACY
	return out


## LEGACY when every layer runs the round-1 code, NATIVE when every migrated layer is native,
## else "mixed".
func backend() -> StringName:
	var n := 0
	for l in NATIVE_LAYERS:
		if layers[l] == NATIVE:
			n += 1
	return LEGACY if n == 0 else (NATIVE if n == NATIVE_LAYERS.size() else &"mixed")


static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := find_skeleton(c)
		if s != null:
			return s
	return null


# ---------------------------------------------------------------- Body goals (world space)


## Where she looks (the eyes lead, the head, neck and chest follow with delays).
func set_gaze(world_point: Vector3) -> void:
	motor.gaze_point = to_model(world_point)


## Yaw (rad, towards her left) the whole floating figure turns to.
func set_turn(angle: float) -> void:
	motor.body_turn = angle


## Posture layer: lean forward (rad), side lean, chest lift, shoulder raise (0..1), shoulders
## forward (0..1, negative = back), head tilt (roll, rad) and nod (rad, positive = down).
func set_posture(lean: float, lean_side: float, chest_lift: float, raise: float, fwd: float, tilt: float,
		nod: float) -> void:
	motor.lean = lean
	motor.lean_side = lean_side
	motor.chest_lift = chest_lift
	motor.shoulder_raise = raise
	motor.shoulder_fwd = fwd
	motor.head_tilt = tilt
	motor.head_nod = nod
	if director != null:
		var p := director.posture
		p[0] = lean
		p[1] = lean_side
		p[2] = chest_lift
		p[3] = raise
		p[4] = fwd
		p[5] = tilt
		p[6] = nod


## Weight on one side (-1 right .. 1 left).
func set_weight(side: float) -> void:
	motor.weight_side = side
	if director != null:
		director.weight_side = side


## Breath rate (cycles/s) and depth (1 = normal).
func set_breath(rate: float, depth: float) -> void:
	motor.breath_rate = rate
	motor.breath_depth = depth
	if director != null:
		director.breath_rate = rate
		director.breath_depth = depth


## Composure of the motion (0 fluid .. 1 rigid) and its speed.
func set_character(stiff: float, tempo: float) -> void:
	motor.stiff = stiff
	motor.tempo = tempo
	if director != null:
		director.stiff = stiff
		director.tempo = tempo


## Her mood (MikuMind.Mood): the native torso's state machine (legacy: the posture carries it).
func set_mood(mood: int) -> void:
	if director != null:
		director.mood = mood


## Arm goal of side s (0 left, 1 right): hand position, palm normal, finger direction, elbow
## hint (directions in world space), finger pose (HandPoses) and speed.
func set_arm(s: int, pos: Vector3, palm: Vector3, point: Vector3, pole: Vector3, pose: StringName,
		speed := 1.0) -> void:
	var b := skeleton.global_transform.basis.inverse()
	motor.arms[s].set_goal(to_model(pos), b * palm, b * point, b * pole, pose, speed)


## Extra curl per finger on top of the pose (tapping, beckoning ripples).
func set_finger_wave(s: int, wave: PackedFloat32Array) -> void:
	var w := motor.arms[s].finger_wave
	for i in mini(wave.size(), w.size()):
		w[i] = wave[i]


## State for the dev inspector (Miku.inspect_state().body).
func inspect_state() -> Dictionary:
	var ls := {}
	for l: StringName in layers:
		ls[String(l)] = String(layers[l])
	var d := {"backend": String(backend()), "layers": ls, "tree_us": tree_us, "motor_us": motor_us}
	if director != null:
		d["tree"] = director.inspect_state()
	return d


## Places every channel on its goal (composition / reset).
func snap() -> void:
	motor.snap_next()
	if director != null:
		director.snap()


# ---------------------------------------------------------------- Body queries (world space)


func fingertip(s: int, finger := 1) -> Vector3:
	return to_world(motor.fingertip(s, finger))


func hand_position(s: int) -> Vector3:
	return to_world(motor.hand_pos(s))


func shoulder(s: int) -> Vector3:
	var b := motor.b_ua[s]
	return to_world(motor.rig.pos[b]) if b >= 0 else to_world(motor.shoulder_rest(s))


## Length of the arm in world units.
func arm_reach(s: int) -> float:
	return motor.arm_length(s) * skeleton.global_transform.basis.get_scale().x


func eye_position() -> Vector3:
	return to_world(motor.eye_pos)


func head_position() -> Vector3:
	return to_world(motor.head_pos())


func chest_position() -> Vector3:
	return to_world(motor.chest_pos())


## Current turn of the figure (rad).
func turn() -> float:
	return motor.turn()


## World basis of her body now: x = her left, y = up, z = forward (turn included).
func body_basis() -> Basis:
	return (skeleton.global_transform.basis * Basis(Vector3.UP, motor.turn())).orthonormalized()


# ---------------------------------------------------------------- spaces


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
	if director != null:
		director.step(dt)
		tree_us = director.last_us
	var t0 := Time.get_ticks_usec()
	motor.step(dt)
	motor_us = Time.get_ticks_usec() - t0
	_place_halo()


func _apply_appearance() -> void:
	if halo != null:
		halo.scale = Vector3.ONE * appearance("halo_radius")
	var g := appearance("glow")
	for m in body_materials:
		LivingMaterials.set_param(m, &"glow", g)
	if _rig_script != null:
		_apply_rig_appearance()
		return
	var h := appearance("height")
	scale = Vector3.ONE * h
	var sw := appearance("shoulder_width")
	for s in 2:
		if _b_ua[s] >= 0:
			motor.rig.pos_scale[_b_ua[s]] = sw
	if _b_head >= 0:
		motor.rig.pos_scale[_b_head] = appearance("neck_length")
	if _b_chest >= 0:
		var cv := MikuParams.chest_factor(appearance("chest_volume"))
		motor.rig.bone_scale[_b_chest] = cv
		for c in _chest_children:
			motor.rig.bone_scale[c] = 1.0 / maxf(cv, 0.01)


## Real rig: MikuRig.apply_appearance sets the bone rests (only when a value moved), then the
## motor re-reads them.
func _apply_rig_appearance() -> void:
	var v := {"height": appearance("height"), "shoulder_width": appearance("shoulder_width"),
		"neck_length": appearance("neck_length"),
		"chest_volume": MikuParams.chest_factor(appearance("chest_volume"))}
	var moved := _applied_rig.is_empty()
	for k: String in v:
		if not moved and absf(float(v[k]) - float(_applied_rig.get(k, -1.0))) > 0.0005:
			moved = true
	if not moved:
		return
	_applied_rig = v
	_rig_script.call(&"apply_appearance", rig_root, v)
	motor.refresh_rest()


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
