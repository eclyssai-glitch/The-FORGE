extends Node3D
## Composes the 3D world. (Loop 1 skeleton: environment + camera + dormant core.)

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.VOID
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 7)
	add_child(cam)
	cam.look_at(Vector3.ZERO)

	var light := OmniLight3D.new()
	light.light_color = Palette.EMBER
	light.omni_range = 12.0
	light.light_energy = 2.0
	light.position = Vector3(2.0, 2.0, 3.0)
	add_child(light)

	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	core.mesh = sphere
	add_child(core)
