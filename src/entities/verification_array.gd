class_name VerificationArray
extends Node3D
## The verification array: a thin physical ring parked below the structure (STANDBY) that, from
## VERIFICATION_STARTED, sweeps the structure bottom <-> top carrying a vertical PALE band
## (MaterialLibrary.scan_ring) and feeds `scan_y` / `scan_strength` of the structure material.
## After VERIFICATION_PASSED the band fades and the ring returns to its park. Owner: animator.
## Each passed check sends a PALE flash through the structure (FragmentStructure, Choreography).
## Selection: StaticBody3D (layer 2) on the ring, meta entity_id = &"verification_array";
## highlight = BONE emission on the ring body.

const ENTITY_ID := &"verification_array"
## Radius clears the widest ring (3.05) with room for the band.
const RADIUS := 3.42
const BAND_WIDTH := 0.16
const HIGHLIGHT_ENERGY := 0.5
## The band is the brightest PALE element: capped so it reads as a calm scan line, not a bloom.
const BAND_LEVEL := 0.5

var ring: MeshInstance3D
var band: MeshInstance3D
var body: StaticBody3D

var _band_mat: ShaderMaterial
var _ring_mat: StandardMaterial3D
var _structure_mat: ShaderMaterial
var _highlight := 0.0
var _last := Vector3(-100, -100, -100)


func _ready() -> void:
	_structure_mat = MaterialLibrary.structure()
	_band_mat = MaterialLibrary.scan_ring()
	_ring_mat = MaterialLibrary.architecture().duplicate() as StandardMaterial3D
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Palette.BONE
	_ring_mat.emission_energy_multiplier = 0.0

	ring = MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = MeshBuilder.ring(RADIUS + 0.05, 0.06, 0.1, 160)
	ring.material_override = _ring_mat
	add_child(ring)

	# Vertical ribbon (width along Y > radial thickness): reads as a band from the side.
	band = MeshInstance3D.new()
	band.name = "Band"
	band.mesh = MeshBuilder.ring(RADIUS, 0.012, BAND_WIDTH, 160)
	band.material_override = _band_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.visible = false
	ring.add_child(band)

	body = StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("entity_id", ENTITY_ID)
	var shape := CollisionShape3D.new()
	shape.shape = MeshBuilder.ring(RADIUS, 0.3, 0.36, 64).create_trimesh_shape()
	body.add_child(shape)
	ring.add_child(body)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var w := Simulation.world
	var t := Simulation.time
	var y := Choreography.scan_y(w, t)
	var s := Choreography.scan_strength(w, t)
	var target := 1.0 if Session.selected == ENTITY_ID else (0.5 if Session.hovered == ENTITY_ID else 0.0)
	_highlight = move_toward(_highlight, target, delta * 4.0) if delta > 0.0 else target
	var now := Vector3(y, s, _highlight)
	if now.is_equal_approx(_last):
		return
	_last = now
	ring.position.y = y
	band.visible = s > 0.001
	_band_mat.set_shader_parameter("strength", s * BAND_LEVEL)
	_structure_mat.set_shader_parameter("scan_y", y)
	_structure_mat.set_shader_parameter("scan_strength", s)
	_ring_mat.emission_energy_multiplier = HIGHLIGHT_ENERGY * _highlight
