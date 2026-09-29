class_name VerificationArray
extends Node3D
## The verification array: a thin physical ring parked below the structure (STANDBY) that, from
## VERIFICATION_STARTED, sweeps the structure bottom <-> top carrying a vertical PALE band
## (MaterialLibrary.scan_ring) and feeds `scan_y` / `scan_strength` of the structure material.
## After VERIFICATION_PASSED the band fades and the ring returns to its park. Owner: animator.
## Each passed check sends a PALE flash through the structure (FragmentStructure, Choreography).
## Selection: StaticBody3D (layer 2) on the ring, meta entity_id = &"verification_array";
## highlight = BONE emission on the ring body.
## The band rides on top of the physical ring (BAND_LIFT): the band's centre is the scan height
## (`scan_y`), the ring hangs just below it. Coplanar, the opaque ring hid the middle of the band
## on its near side and left two sub-pixel slivers that read as a dotted thread.
## The band is a single cylindrical wall of zero radial thickness (BAND_THICKNESS): a ring with
## thickness has top/bottom caps, and a 0.012 cap is a sub-pixel strip whose own across-falloff
## peaks mid-cap — rasterized (worst without MSAA, LOW) it drew a dotted thread along the band's
## edges, separated from the band by its soft falloff. With zero thickness the caps are
## degenerate (no area, never rasterized); the inner and outer walls coincide and add up exactly
## as the two walls of the thin ring did (additive, cull disabled), so the band keeps its level.
## Focus: the ring node joins SessionState.entity_group(ENTITY_ID) (bounds = ring + band, so
## the framing follows the ring's height at the moment of the request).

const ENTITY_ID := &"verification_array"
## Radius clears the widest ring (3.05) with room for the band.
const RADIUS := 3.42
const BAND_WIDTH := 0.16
## Radial thickness of the band mesh: zero, a wall without caps (see above).
const BAND_THICKNESS := 0.0
## Physical ring cross-section (radial thickness, height).
const RING_THICKNESS := 0.06
const RING_HEIGHT := 0.1
## Band centre above the ring centre: the band sits on the ring's top edge, never behind it.
const BAND_LIFT := (RING_HEIGHT + BAND_WIDTH) * 0.5
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
	ring.mesh = MeshBuilder.ring(RADIUS + 0.05, RING_THICKNESS, RING_HEIGHT, 160)
	ring.material_override = _ring_mat
	ring.add_to_group(SessionState.entity_group(ENTITY_ID))
	var r := RADIUS + 0.05 + RING_THICKNESS
	ring.set_meta(CameraDirector.FOCUS_BOUNDS_META,
		AABB(Vector3(-r, -RING_HEIGHT * 0.5, -r), Vector3(2.0 * r, BAND_LIFT + (RING_HEIGHT + BAND_WIDTH) * 0.5, 2.0 * r)))
	add_child(ring)

	# Vertical ribbon (width along Y > radial thickness): reads as a band from the side.
	band = MeshInstance3D.new()
	band.name = "Band"
	band.mesh = MeshBuilder.ring(RADIUS, BAND_THICKNESS, BAND_WIDTH, 160)
	band.material_override = _band_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.visible = false
	band.position.y = BAND_LIFT
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
	ring.position.y = y - BAND_LIFT
	band.visible = s > 0.001
	_band_mat.set_shader_parameter("strength", s * BAND_LEVEL)
	_structure_mat.set_shader_parameter("scan_y", y)
	_structure_mat.set_shader_parameter("scan_strength", s)
	_ring_mat.emission_energy_multiplier = HIGHLIGHT_ENERGY * _highlight
