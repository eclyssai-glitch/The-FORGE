class_name ChamberArchitecture
extends Node3D
## Architecture of the ORIGIN CHAMBER: dark floor disc at y = -3.2, a wide ring of pillars
## (MultiMesh), the oculus ring high above the core, and a faint BONE inlay ring on the floor
## under the structure. Owner: animator (materials from MaterialLibrary). The pillars stand
## beyond the FORGE camera limit (CameraShots.DISTANCE_LIMITS) so they never block the view;
## depth fog dissolves them. The floor inlay rises with the chamber light (lit stage).
## Selection: the built architecture — pillars and oculus — is one StaticBody3D (layer 2), meta
## entity_id = &"origin_chamber". The floor is deliberately NOT pickable: it lies under every
## FORGE view, so a click on empty space must reach nothing and clear the selection.
## Focus: the node joins SessionState.entity_group(ENTITY_ID); bounds = the pillar ring.
## The oculus only ever enters the frame in UNIVERSE, where it read as a loose ring floating
## above the chamber: it is hidden there (mesh and its pick shape).

const ENTITY_ID := &"origin_chamber"
const FLOOR_Y := CameraShots.FLOOR_Y
const FLOOR_RADIUS := 34.0
const PILLAR_COUNT := 24
const PILLAR_RADIUS := 24.0
const PILLAR_SIZE := Vector3(0.8, 12.0, 0.8)
## Oculus: a dark ring hanging high above the core, out of the FORGE frame, framing the void.
const OCULUS_RADIUS := 5.2
const OCULUS_Y := 10.5
const INLAY_RADIUS := 3.7
const INLAY_BASE := 0.08
const INLAY_LIT := 0.22
const INLAY_SELECTED := 0.5

var floor_mesh: MeshInstance3D
var pillars: MultiMeshInstance3D
var oculus: MeshInstance3D
var inlay: MeshInstance3D
var body: StaticBody3D

var _oculus_shape: CollisionShape3D

var _inlay_mat: ShaderMaterial
var _highlight := 0.0
var _last := -1.0


func _ready() -> void:
	add_to_group(SessionState.entity_group(ENTITY_ID))
	set_meta(CameraDirector.FOCUS_BOUNDS_META, focus_bounds())
	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var disc := CylinderMesh.new()
	disc.top_radius = FLOOR_RADIUS
	disc.bottom_radius = FLOOR_RADIUS
	disc.height = 0.2
	disc.radial_segments = 128
	disc.rings = 1
	floor_mesh.mesh = disc
	floor_mesh.material_override = MaterialLibrary.floor()
	floor_mesh.position.y = FLOOR_Y - 0.1
	add_child(floor_mesh)

	var box := BoxMesh.new()
	box.size = PILLAR_SIZE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = PILLAR_COUNT
	for p in PILLAR_COUNT:
		mm.set_instance_transform(p, pillar_transform(p))
	pillars = MultiMeshInstance3D.new()
	pillars.name = "Pillars"
	pillars.multimesh = mm
	pillars.material_override = MaterialLibrary.architecture()
	add_child(pillars)

	# Oculus: the opening above the core, a dark ring out of the FORGE frame.
	oculus = MeshInstance3D.new()
	oculus.name = "Oculus"
	oculus.mesh = MeshBuilder.ring(OCULUS_RADIUS, 0.7, 0.28, 128)
	oculus.material_override = MaterialLibrary.architecture()
	oculus.position.y = OCULUS_Y
	add_child(oculus)

	inlay = MeshInstance3D.new()
	inlay.name = "Inlay"
	inlay.mesh = MeshBuilder.ring(INLAY_RADIUS, 0.05, 0.004, 128)
	inlay.position.y = FLOOR_Y + 0.004
	inlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inlay_mat = MaterialLibrary.halo().duplicate() as ShaderMaterial
	_inlay_mat.set_shader_parameter("color", Palette.BONE)
	inlay.material_override = _inlay_mat
	add_child(inlay)

	body = StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("entity_id", ENTITY_ID)
	var pillar_shape := BoxShape3D.new()
	pillar_shape.size = PILLAR_SIZE
	for p in PILLAR_COUNT:
		var shape := CollisionShape3D.new()
		shape.shape = pillar_shape
		shape.transform = pillar_transform(p)
		body.add_child(shape)
	var ring_shape := CollisionShape3D.new()
	ring_shape.shape = oculus.mesh.create_trimesh_shape()
	ring_shape.position = oculus.position
	body.add_child(ring_shape)
	_oculus_shape = ring_shape
	add_child(body)
	Session.mode_changed.connect(apply_mode)
	apply_mode(Session.mode)
	_update(0.0)


## Per-mode visibility: the oculus is hidden (and not pickable) in UNIVERSE.
func apply_mode(mode: SessionState.Mode) -> void:
	var on := oculus_visible_in(mode)
	oculus.visible = on
	_oculus_shape.set_deferred("disabled", not on)


static func oculus_visible_in(mode: SessionState.Mode) -> bool:
	return mode != SessionState.Mode.UNIVERSE


## Local focus bounds of the chamber: the pillar ring from the floor to the pillar tops.
static func focus_bounds() -> AABB:
	var r := PILLAR_RADIUS + PILLAR_SIZE.x
	return AABB(Vector3(-r, FLOOR_Y, -r), Vector3(2.0 * r, PILLAR_SIZE.y, 2.0 * r))


## Pose of pillar p: on the ring of PILLAR_RADIUS at TAU·(p + 0.5)/PILLAR_COUNT, standing on the floor.
static func pillar_transform(p: int) -> Transform3D:
	var a := pillar_angle(p)
	var pos := Vector3(sin(a) * PILLAR_RADIUS, FLOOR_Y + PILLAR_SIZE.y * 0.5, cos(a) * PILLAR_RADIUS)
	return Transform3D(Basis(Vector3.UP, a), pos)


## Yaw of pillar p around +Y from +Z (the CameraShots convention).
static func pillar_angle(p: int) -> float:
	return TAU * (float(p) + 0.5) / float(PILLAR_COUNT)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var w := Simulation.world
	var t := Simulation.time
	var target := 1.0 if Session.selected == ENTITY_ID else (0.5 if Session.hovered == ENTITY_ID else 0.0)
	_highlight = move_toward(_highlight, target, delta * 4.0) if delta > 0.0 else target
	var lit := Motion.smooth(w.lighting_at, t, Palette.T_CINEMATIC)
	var s := lerpf(lerpf(INLAY_BASE, INLAY_LIT, lit), INLAY_SELECTED, _highlight)
	if is_equal_approx(s, _last):
		return
	_last = s
	_inlay_mat.set_shader_parameter("strength", s)
