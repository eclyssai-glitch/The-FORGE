class_name ActivationPulse
extends Node3D
## EMBER energy waves in the core plane: one on CORE_ACTIVATION, a smaller one on CORE_ONLINE
## and a wide one on STRUCTURE_FINALIZED; plus the steady EMBER halo of the final form around
## the equator. Owner: animator. Pure function of (world, sim time) via Choreography.wave /
## final_halo, so a seek shows exactly the wave of that instant. Halo material is a duplicate
## of MaterialLibrary.halo() set to EMBER (energy only: activation and final form).

const WAVE_SECTION := 0.05
const HALO_RADIUS := 3.3

var wave_ring: MeshInstance3D
var halo_ring: MeshInstance3D

var _wave_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _wave := {}
var _last := Vector3(-1, -1, -1)


func _ready() -> void:
	_wave_mat = _ember_halo(1.4)
	wave_ring = MeshInstance3D.new()
	wave_ring.name = "Wave"
	# Unit radius, scaled in XZ: thin radially (grows with the radius but stays a line), a
	# vertical wall of WAVE_SECTION so the wave also reads from a low camera.
	wave_ring.mesh = MeshBuilder.ring(1.0, 0.03, WAVE_SECTION, 160)
	wave_ring.material_override = _wave_mat
	wave_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wave_ring.visible = false
	add_child(wave_ring)

	_halo_mat = _ember_halo(0.9)
	halo_ring = MeshInstance3D.new()
	halo_ring.name = "FinalHalo"
	halo_ring.mesh = MeshBuilder.ring(HALO_RADIUS, 0.03, 0.05, 192)
	halo_ring.material_override = _halo_mat
	halo_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_ring.visible = false
	add_child(halo_ring)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var w := Simulation.world
	var t := Simulation.time
	Choreography.wave(w, t, _wave)
	var r := float(_wave["radius"])
	var s := float(_wave["strength"])
	var h := Choreography.final_halo(w, t)
	var now := Vector3(r, s, h)
	if now.is_equal_approx(_last):
		return
	_last = now
	wave_ring.visible = s > 0.002
	if wave_ring.visible:
		wave_ring.scale = Vector3(r, 1.0, r)
		_wave_mat.set_shader_parameter("strength", s)
	halo_ring.visible = h > 0.002
	_halo_mat.set_shader_parameter("strength", h)


static func _ember_halo(intensity: float) -> ShaderMaterial:
	var m := MaterialLibrary.halo().duplicate() as ShaderMaterial
	m.set_shader_parameter("color", Palette.EMBER)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("strength", 0.0)
	return m
