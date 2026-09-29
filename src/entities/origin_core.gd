class_name OriginCore
extends Node3D
## The suspended origin core at (0, 0, 0). Owner: animator.
## A faceted shell of separated plates (MaterialLibrary.core_shell) around an emissive heart
## (core_heart) that shows through the seams. Dormant: energy 0 — no EMBER at all, only the rim
## light and the shell fresnel draw a silhouette. CORE_ACTIVATION raises the energy with a
## heartbeat, CORE_ONLINE settles it; every construction step sends a surge (Choreography).
## Ambient motion (slow shell rotation, float) uses real time and keeps going while paused.
## Selection: StaticBody3D (layer 2) with meta entity_id = &"origin_core"; highlight raises the
## BONE fresnel of the shell.

const ENTITY_ID := &"origin_core"
const SHELL_RADIUS := StructureBlueprint.CORE_RADIUS
const HEART_RADIUS := 0.4
## Each shell facet is shrunk towards its centroid by this factor, opening EMBER seams.
const PLATE_SCALE := 0.86
const RIM_BASE := 0.16
const RIM_SELECTED := 0.55
const FLOAT_AMPLITUDE := 0.035

var shell: MeshInstance3D
var heart: MeshInstance3D
var body: StaticBody3D

var _shell_mat: ShaderMaterial
var _heart_mat: ShaderMaterial
var _highlight := 0.0
var _last := Vector4(-1, -1, -1, -1)


func _ready() -> void:
	_shell_mat = MaterialLibrary.core_shell()
	_heart_mat = MaterialLibrary.core_heart()
	heart = MeshInstance3D.new()
	heart.name = "Heart"
	heart.mesh = MeshBuilder.icosphere(HEART_RADIUS, 2, false)
	heart.material_override = _heart_mat
	heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(heart)
	shell = MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = _plated_shell(MeshBuilder.icosphere(SHELL_RADIUS, 1, true), PLATE_SCALE)
	shell.material_override = _shell_mat
	add_child(shell)

	body = StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("entity_id", ENTITY_ID)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SHELL_RADIUS + 0.08
	shape.shape = sphere
	body.add_child(shape)
	add_child(body)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var w := Simulation.world
	var t := Simulation.time
	var rt := Time.get_ticks_msec() * 0.001
	var energy := Choreography.core_energy(w, t)
	var pulse := Choreography.core_pulse(w, t)
	var peak := Choreography.core_peak(w, t)
	var target := 0.0
	if Session.selected == ENTITY_ID:
		target = 1.0
	elif Session.hovered == ENTITY_ID:
		target = 0.5
	_highlight = move_toward(_highlight, target, delta * 4.0) if delta > 0.0 else target
	var rim := lerpf(RIM_BASE, RIM_SELECTED, _highlight)
	var now := Vector4(energy, pulse, peak, rim)
	if not now.is_equal_approx(_last):
		_last = now
		_shell_mat.set_shader_parameter("energy", energy)
		_shell_mat.set_shader_parameter("rim_energy", rim)
		_heart_mat.set_shader_parameter("energy", energy)
		_heart_mat.set_shader_parameter("pulse", pulse)
		_heart_mat.set_shader_parameter("peak", peak)
	# Ambient: the shell turns slowly on a tilted axis; the whole core floats a little.
	shell.transform.basis = Basis(Vector3(0.25, 1.0, 0.1).normalized(), rt * 0.07)
	heart.transform.basis = Basis(Vector3.UP, -rt * 0.05)
	var bob := Vector3(0.0, sin(rt * 0.6) * FLOAT_AMPLITUDE, 0.0)
	shell.position = bob
	heart.position = bob


## Splits a flat-shaded icosphere into separate plates (each facet shrunk towards its centroid)
## so the heart shows through the seams. Works on MeshBuilder's flat layout (3 unique vertices
## per triangle). Built once in _ready.
static func _plated_shell(src: ArrayMesh, plate_scale: float) -> ArrayMesh:
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for f in range(0, idx.size(), 3):
		var a := idx[f]
		var b := idx[f + 1]
		var c := idx[f + 2]
		var centre := (verts[a] + verts[b] + verts[c]) / 3.0
		verts[a] = centre + (verts[a] - centre) * plate_scale
		verts[b] = centre + (verts[b] - centre) * plate_scale
		verts[c] = centre + (verts[c] - centre) * plate_scale
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
