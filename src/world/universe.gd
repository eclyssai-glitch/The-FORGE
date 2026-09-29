class_name Universe
extends Node3D
## The universe around the ORIGIN CHAMBER: a procedural sky (VOID background, sparse cold
## stars, a barely visible distant dust band) and the three dormant seeds of future constructs,
## placed beyond the chamber (60–70 units from the centre; the floor ends at 34).
## Each seed root joins the group Session.entity_group(id) ("entity_<id>", focus target). Seeds
## are pickable (StaticBody3D with meta "entity_id") only in UNIVERSE: elsewhere they sit beyond
## the end of the depth fog (invisible), so their bodies leave collision layer 2 (see
## apply_mode / seeds_pickable_in). They drift slowly in real time — an ambient breath that
## carries no simulation state.
## Selection/hover highlight (only where seeds are pickable, i.e. UNIVERSE): each seed owns a
## duplicate of MaterialLibrary.dormant_seed() and of its halo. Selected = 1, hovered =
## HOVER_LEVEL; the level eases in real time (Palette.T_FAST) and raises the fresnel
## (cold_color ASH -> BONE, cold_energy) and the halo strength (BONE). `energy` stays 0: never
## EMBER, never PALE.

const SKY_SHADER := preload("res://src/world/universe_sky.gdshader")

## Collision layer bit used by everything the Picker can select.
const PICK_LAYER := 2

## Seeds: position in cylindrical coordinates around the chamber (radius in XZ, angle from +Z
## towards +X in degrees, height) and a sober geometric form.
##   form "orb":       faceted sphere + one tilted ring
##   form "spindle":   elongated icosahedron + two coaxial rings
##   form "armillary": icosahedron + two crossed rings, both tilted (never upright)
const SEEDS: Array[Dictionary] = [
	{"id": &"seed_aurel", "radius": 62.0, "angle": -100.0, "height": 8.0, "form": "orb", "size": 2.2, "phase": 0.0},
	{"id": &"seed_vesper", "radius": 70.0, "angle": 150.0, "height": -1.0, "form": "spindle", "size": 1.7, "phase": 2.1},
	{"id": &"seed_lattice", "radius": 66.0, "angle": 205.0, "height": 14.0, "form": "armillary", "size": 1.8, "phase": 4.2},
]

## Drift (real time): vertical bob amplitude/period and spin rate.
const DRIFT_AMPLITUDE := 0.35
const DRIFT_PERIOD := 46.0
const SPIN_RATE := 0.035
## Picking sphere radius relative to the seed size (generous: seeds are far away).
const PICK_RADIUS_SCALE := 2.1
## Halo ring cross-section per unit of seed size (radial thickness, height).
const RING_THICKNESS := 0.04
const RING_WIDTH := 0.12
## Halo ring strength (BONE, dormant: no energy, no EMBER).
const HALO_STRENGTH := 0.18
## Highlight: level when hovered (selected = 1); fresnel and halo at rest and at full highlight.
const HOVER_LEVEL := 0.5
const COLD_ENERGY_BASE := 0.55
const COLD_ENERGY_SELECTED := 1.5
const HALO_STRENGTH_SELECTED := 0.6
## Star brightness of the sky per mode: full in UNIVERSE, quiet behind the chamber.
const STAR_INTENSITY := {
	SessionState.Mode.UNIVERSE: 0.55,
	SessionState.Mode.FORGE: 0.22,
	SessionState.Mode.OBSERVATORY: 0.3,
}

var sky_material: ShaderMaterial

var _seeds: Dictionary = {}  # id -> {"root", "body", "rings": Node3D, "pick": StaticBody3D, "base": Vector3, "phase": float,
#                            "body_mat", "halo_mat": ShaderMaterial, "highlight", "applied": float}
var _elapsed := 0.0
## Seeds start unpickable until apply_mode() says otherwise (the default mode is FORGE).
var _pickable := false


func _init() -> void:
	name = "Universe"
	sky_material = make_sky_material()
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
	update_highlight(delta)


## Eases every seed's highlight towards its target (Session.selected/hovered, UNIVERSE only)
## and pushes it to the seed's own materials. delta <= 0 snaps to the target.
func update_highlight(delta: float) -> void:
	for id: StringName in _seeds:
		var s: Dictionary = _seeds[id]
		var target := highlight_target(id, Session.selected, Session.hovered, _pickable)
		var h: float = s["highlight"]
		h = move_toward(h, target, delta / Palette.T_FAST) if delta > 0.0 else target
		s["highlight"] = h
		if is_equal_approx(h, float(s["applied"])):
			continue
		s["applied"] = h
		_apply_highlight(s["body_mat"], s["halo_mat"], h)


## 1 when the seed is selected, HOVER_LEVEL when hovered, 0 otherwise or when not pickable.
static func highlight_target(id: StringName, selected: StringName, hovered: StringName, pickable: bool) -> float:
	if not pickable:
		return 0.0
	if selected == id:
		return 1.0
	if hovered == id:
		return HOVER_LEVEL
	return 0.0


## Current highlight level (0..1) of a seed.
func seed_highlight(id: StringName) -> float:
	return float(_seeds[id]["highlight"]) if _seeds.has(id) else 0.0


## The seed's own dormant_seed material (body), or null.
func seed_body_material(id: StringName) -> ShaderMaterial:
	return _seeds[id]["body_mat"] if _seeds.has(id) else null


## The seed's own halo material (shared by that seed's rings only), or null.
func seed_halo_material(id: StringName) -> ShaderMaterial:
	return _seeds[id]["halo_mat"] if _seeds.has(id) else null


static func _apply_highlight(body_mat: ShaderMaterial, halo_mat: ShaderMaterial, h: float) -> void:
	body_mat.set_shader_parameter("cold_color", Palette.ASH.lerp(Palette.BONE, h))
	body_mat.set_shader_parameter("cold_energy", lerpf(COLD_ENERGY_BASE, COLD_ENERGY_SELECTED, h))
	halo_mat.set_shader_parameter("strength", lerpf(HALO_STRENGTH, HALO_STRENGTH_SELECTED, h))


## Puts the universe sky behind the environment. The background stays VOID (drawn by the sky
## shader); ambient light keeps its own colour source, so only the backdrop changes.
func apply_sky(env: Environment) -> void:
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky
	env.background_mode = Environment.BG_SKY


## Per-mode settings (called by the world on Session.mode_changed and at start): sky star
## brightness and whether the seeds can be picked.
func apply_mode(mode: SessionState.Mode) -> void:
	sky_material.set_shader_parameter("star_intensity", star_intensity_for(mode))
	set_seeds_pickable(seeds_pickable_in(mode))


## Seeds are only selectable where they are visible: UNIVERSE (fog ends at 220). In FORGE and
## OBSERVATORY the depth fog ends at 34/30 units and the seeds (60–70) are fully hidden.
static func seeds_pickable_in(mode: SessionState.Mode) -> bool:
	return mode == SessionState.Mode.UNIVERSE


## Puts every seed pick body on (or off) the pick layer. Off = collision_layer 0: rays of the
## Picker (mask 2) pass through.
func set_seeds_pickable(enabled: bool) -> void:
	_pickable = enabled
	for id: StringName in _seeds:
		(_seeds[id]["pick"] as StaticBody3D).collision_layer = PICK_LAYER if enabled else 0


func seeds_pickable() -> bool:
	return _pickable


static func star_intensity_for(mode: SessionState.Mode) -> float:
	return float(STAR_INTENSITY.get(mode, STAR_INTENSITY[SessionState.Mode.UNIVERSE]))


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
	root.add_to_group(SessionState.entity_group(id))
	add_child(root)

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var rings := Node3D.new()
	rings.name = "Rings"
	root.add_child(rings)
	# Per-seed copies: each seed lights up alone when selected/hovered.
	var body_mat := MaterialLibrary.dormant_seed().duplicate() as ShaderMaterial
	var halo_mat := MaterialLibrary.halo().duplicate() as ShaderMaterial
	halo_mat.set_shader_parameter("color", Palette.BONE)
	_apply_highlight(body_mat, halo_mat, 0.0)

	match String(s["form"]):
		"spindle":
			var m := _mesh(MeshBuilder.icosphere(size, 0, true), body_mat)
			m.scale = Vector3(0.75, 1.6, 0.75)
			body.add_child(m)
			for k in 2:
				var ring := _halo_ring(halo_mat, size, 1.7 + 0.45 * k)
				ring.rotation = Vector3(deg_to_rad(8.0 + 6.0 * k), 0.0, deg_to_rad(-4.0))
				rings.add_child(ring)
		"armillary":
			body.add_child(_mesh(MeshBuilder.icosphere(size, 0, true), body_mat))
			var flat := _halo_ring(halo_mat, size, 1.9)
			flat.rotation = Vector3(deg_to_rad(12.0), 0.0, 0.0)
			rings.add_child(flat)
			var crossed := _halo_ring(halo_mat, size, 1.9)
			crossed.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(60.0), 0.0)
			rings.add_child(crossed)
		_:
			body.add_child(_mesh(MeshBuilder.icosphere(size, 1, true), body_mat))
			var ring := _halo_ring(halo_mat, size, 1.85)
			ring.rotation = Vector3(deg_to_rad(18.0), 0.0, deg_to_rad(7.0))
			rings.add_child(ring)

	var pick := StaticBody3D.new()
	pick.name = "Pick"
	pick.collision_layer = PICK_LAYER if _pickable else 0
	pick.collision_mask = 0
	pick.set_meta(&"entity_id", id)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = size * PICK_RADIUS_SCALE
	shape.shape = sphere
	pick.add_child(shape)
	root.add_child(pick)

	_seeds[id] = {"root": root, "body": body, "rings": rings, "pick": pick, "base": root.position, "phase": float(s["phase"]),
		"body_mat": body_mat, "halo_mat": halo_mat, "highlight": 0.0, "applied": 0.0}


## Thin halo ring of `radius_factor`·size; cross-section scales with the seed so the rings keep
## their proportions (and stay above a pixel) at the seeds' distance.
static func _halo_ring(halo_mat: ShaderMaterial, size: float, radius_factor: float) -> MeshInstance3D:
	return _mesh(MeshBuilder.ring(size * radius_factor, RING_THICKNESS * size, RING_WIDTH * size, 96), halo_mat)


static func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
