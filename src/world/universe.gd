class_name Universe
extends Node3D
## The universe around the ORIGIN CHAMBER: a procedural sky (VOID background, sparse cold
## stars, a barely visible distant dust band) and the three dormant seeds of future constructs.
## Seeds are pickable (StaticBody3D on collision layer 2 with meta "entity_id") and drift
## slowly in real time — an ambient breath that carries no simulation state.

const SKY_SHADER := preload("res://src/world/universe_sky.gdshader")

## Collision layer bit used by everything the Picker can select.
const PICK_LAYER := 2

## Seeds: position in cylindrical coordinates around the chamber (radius in XZ, angle from +Z
## towards +X in degrees, height) and a sober geometric form.
##   form "orb":       faceted sphere + one tilted ring
##   form "spindle":   elongated icosahedron + two coaxial rings
##   form "armillary": icosahedron + two crossed rings
const SEEDS: Array[Dictionary] = [
	{"id": &"seed_aurel", "radius": 21.0, "angle": -100.0, "height": 3.5, "form": "orb", "size": 1.1, "phase": 0.0},
	{"id": &"seed_vesper", "radius": 25.0, "angle": 150.0, "height": -2.0, "form": "spindle", "size": 0.85, "phase": 2.1},
	{"id": &"seed_lattice", "radius": 22.0, "angle": 48.0, "height": 6.5, "form": "armillary", "size": 0.9, "phase": 4.2},
]

## Drift (real time): vertical bob amplitude/period and spin rate.
const DRIFT_AMPLITUDE := 0.35
const DRIFT_PERIOD := 46.0
const SPIN_RATE := 0.035
## Picking sphere radius relative to the seed size (generous: seeds are far away).
const PICK_RADIUS_SCALE := 2.1
## Halo ring strength (BONE, dormant: no energy, no EMBER).
const HALO_STRENGTH := 0.32

var sky_material: ShaderMaterial

var _seeds: Dictionary = {}  # id -> {"root": Node3D, "body": Node3D, "rings": Node3D, "base": Vector3, "phase": float}
var _elapsed := 0.0
var _halo: ShaderMaterial


func _init() -> void:
	name = "Universe"
	sky_material = make_sky_material()
	_halo = MaterialLibrary.halo().duplicate() as ShaderMaterial
	_halo.set_shader_parameter("strength", HALO_STRENGTH)
	for s in SEEDS:
		_build_seed(s)


func _process(delta: float) -> void:
	_elapsed += delta
	for id: StringName in _seeds:
		var s: Dictionary = _seeds[id]
		var ph: float = s["phase"]
		var root: Node3D = s["root"]
		root.position = (s["base"] as Vector3) + drift_offset(_elapsed, ph)
		(s["body"] as Node3D).rotation.y = _elapsed * SPIN_RATE + ph
		(s["rings"] as Node3D).rotation.y = -_elapsed * SPIN_RATE * 0.6 + ph


## Puts the universe sky behind the environment. The background stays VOID (drawn by the sky
## shader); ambient light keeps its own colour source, so only the backdrop changes.
func apply_sky(env: Environment) -> void:
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky
	env.background_mode = Environment.BG_SKY


## Seed ids in declaration order.
func seed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in SEEDS:
		out.append(s["id"])
	return out


## Root node of a seed (moves with the drift), or null.
func seed_node(id: StringName) -> Node3D:
	return _seeds[id]["root"] if _seeds.has(id) else null


## Rest position of a seed (without drift).
static func seed_base_position(s: Dictionary) -> Vector3:
	var a := deg_to_rad(float(s["angle"]))
	var r := float(s["radius"])
	return Vector3(r * sin(a), float(s["height"]), r * cos(a))


## Real-time drift offset: a slow vertical bob plus a smaller lateral sway.
static func drift_offset(t: float, phase: float) -> Vector3:
	var w := TAU / DRIFT_PERIOD
	return Vector3(
		sin(t * w * 0.63 + phase * 1.7) * DRIFT_AMPLITUDE * 0.4,
		sin(t * w + phase) * DRIFT_AMPLITUDE,
		cos(t * w * 0.51 + phase * 0.9) * DRIFT_AMPLITUDE * 0.4)


static func make_sky_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SKY_SHADER
	m.set_shader_parameter("void_color", Palette.VOID)
	m.set_shader_parameter("star_color", Palette.ASH)
	m.set_shader_parameter("star_bright_color", Palette.BONE)
	m.set_shader_parameter("band_color", Palette.ASH)
	return m


func _build_seed(s: Dictionary) -> void:
	var id: StringName = s["id"]
	var size := float(s["size"])
	var root := Node3D.new()
	root.name = String(id)
	root.position = seed_base_position(s)
	add_child(root)

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var rings := Node3D.new()
	rings.name = "Rings"
	root.add_child(rings)

	match String(s["form"]):
		"spindle":
			var m := _mesh(MeshBuilder.icosphere(size, 0, true), MaterialLibrary.dormant_seed())
			m.scale = Vector3(0.75, 1.6, 0.75)
			body.add_child(m)
			for k in 2:
				var ring := _mesh(MeshBuilder.ring(size * (1.7 + 0.45 * k), 0.04, 0.12, 96), _halo)
				ring.rotation = Vector3(deg_to_rad(8.0 + 6.0 * k), 0.0, deg_to_rad(-4.0))
				rings.add_child(ring)
		"armillary":
			body.add_child(_mesh(MeshBuilder.icosphere(size, 0, true), MaterialLibrary.dormant_seed()))
			var flat := _mesh(MeshBuilder.ring(size * 1.9, 0.04, 0.12, 96), _halo)
			flat.rotation = Vector3(deg_to_rad(12.0), 0.0, 0.0)
			rings.add_child(flat)
			var upright := _mesh(MeshBuilder.ring(size * 1.9, 0.04, 0.12, 96), _halo)
			upright.rotation = Vector3(deg_to_rad(90.0), deg_to_rad(35.0), 0.0)
			rings.add_child(upright)
		_:
			body.add_child(_mesh(MeshBuilder.icosphere(size, 1, true), MaterialLibrary.dormant_seed()))
			var ring := _mesh(MeshBuilder.ring(size * 1.85, 0.04, 0.12, 96), _halo)
			ring.rotation = Vector3(deg_to_rad(18.0), 0.0, deg_to_rad(7.0))
			rings.add_child(ring)

	var pick := StaticBody3D.new()
	pick.name = "Pick"
	pick.collision_layer = PICK_LAYER
	pick.collision_mask = 0
	pick.set_meta(&"entity_id", id)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = size * PICK_RADIUS_SCALE
	shape.shape = sphere
	pick.add_child(shape)
	root.add_child(pick)

	_seeds[id] = {"root": root, "body": body, "rings": rings, "base": root.position, "phase": float(s["phase"])}


static func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
