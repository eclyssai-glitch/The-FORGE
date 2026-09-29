class_name DustField
extends GPUParticles3D
## Sparse cold dust suspended in the chamber air: gives scale and depth to the dark volume.
## Owner: animator. Ambient (real time, not tied to events); very slow drift, ASH, low alpha.
## Count scales with Quality.profile["particles"] through amount_ratio (no restart).

const MAX_AMOUNT := 600
const EXTENTS := Vector3(9.0, 5.5, 9.0)
## Motes closer than NEAR_FADE to the camera vanish (a quad that close reads as a square).
const NEAR_FADE := Vector2(2.0, 5.0)
const CENTRE_Y := 1.2


func _ready() -> void:
	amount = MAX_AMOUNT
	lifetime = 22.0
	preprocess = 22.0
	explosiveness = 0.0
	randomness = 1.0
	fixed_fps = 20
	local_coords = false
	position.y = CENTRE_Y
	visibility_aabb = AABB(-EXTENTS - Vector3.ONE * 2.0, (EXTENTS + Vector3.ONE * 2.0) * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = EXTENTS
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.09
	pm.gravity = Vector3(0.0, 0.004, 0.0)
	pm.damping_min = 0.0
	pm.damping_max = 0.01
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	# Fade in and out over the lifetime so no mote pops.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.024, 0.024)
	var mat := MaterialLibrary.particle(Palette.ASH).duplicate() as StandardMaterial3D
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = NEAR_FADE.x
	mat.distance_fade_max_distance = NEAR_FADE.y
	quad.material = mat
	draw_pass_1 = quad

	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)


func _on_quality(profile: Dictionary) -> void:
	amount_ratio = clampf(float(profile.get("particles", 1.0)), 0.0, 1.0)
