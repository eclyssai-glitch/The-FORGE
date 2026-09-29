class_name ChamberArchitecture
extends Node3D
## Architecture of the ORIGIN CHAMBER: dark floor disc at y = -3.2, a wide ring of pillars
## (MultiMesh), the oculus ring high above the core, and a faint BONE inlay ring on the floor
## under the structure. Owner: animator (materials from MaterialLibrary). The pillars stand
## beyond the FORGE camera limit (CameraShots.DISTANCE_LIMITS) so they never block the view;
## depth fog dissolves them. The floor inlay rises with the chamber light (lit stage).
## Selection: the floor is a StaticBody3D (layer 2), meta entity_id = &"origin_chamber".

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

var _inlay_mat: ShaderMaterial
var _highlight := 0.0
var _last := -1.0


func _ready() -> void:
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
		var a := TAU * (float(p) + 0.5) / float(PILLAR_COUNT)
		var pos := Vector3(sin(a) * PILLAR_RADIUS, FLOOR_Y + PILLAR_SIZE.y * 0.5, cos(a) * PILLAR_RADIUS)
		mm.set_instance_transform(p, Transform3D(Basis(Vector3.UP, a), pos))
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
	var shape := CollisionShape3D.new()
	var slab := CylinderShape3D.new()
	slab.radius = FLOOR_RADIUS
	slab.height = 0.2
	shape.shape = slab
	shape.position.y = FLOOR_Y - 0.1
	body.add_child(shape)
	add_child(body)
	_update(0.0)


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
