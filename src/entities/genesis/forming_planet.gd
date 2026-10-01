class_name FormingPlanet
extends Node3D
## ILVARA-7, the world being born (a fictional subagent). Owner: animator.
## PlanetSphere (unit sphere, detail by quality) + a duplicate of MaterialLibrary.planet_forming()
## whose four uniforms tell the genesis (GenesisChoreography):
##   planet.seeded  — a molten seed accretes into being (`formation` patches with a gold lip) and
##                    swells to the core radius;
##   planet.layer 0 — the incandescent mantle: the sphere swells, `heat` rises to full;
##   planet.layer 1 — the crust: plates settle one by one (`crust`), the magma cools (`heat`);
##   planet.layer 2 — the sky: `atmosphere` haze and rim, a last small swell;
##   planet.stable  — it holds (the work of the hands and the accretion disc end elsewhere).
## Every step is a swell over Palette.T_SWELL (never a pop); seek/pause are exact.
## Ambient (MotionClock): slow axial rotation. Hover/selection: the shader's `select` rim.
## Entity `planet_forming`: the Body node is the visual root (group, invisible until seeded,
## focus bounds = final radius), picked through a sphere StaticBody3D (layer 2) that follows the
## radius. Audio anchor `planet` at the planet centre (always present: the dust gathers there).

const ENTITY := &"planet_forming"
## Axial rotation period (s, MotionClock).
const SPIN_PERIOD := 140.0
const SEED := 0.37
const SELECT_RATE := 6.0

var pivot: Node3D
var body: MeshInstance3D
var pick_body: StaticBody3D
var anchor_node: Node3D

var _mat: ShaderMaterial
var _shape: SphereShape3D
var _select := 0.0
## Last values written: radius, formation, heat, crust, atmosphere.
var _written := PackedFloat32Array([-1, -1, -1, -1, -1])
var _level := -1


func _ready() -> void:
	pivot = Node3D.new()
	pivot.name = "Pivot"
	pivot.position = GenesisLayout.PLANET_CENTER
	pivot.rotation = GenesisLayout.PLANET_TILT
	add_child(pivot)

	body = MeshInstance3D.new()
	body.name = "Body"
	_mat = MaterialLibrary.planet_forming().duplicate() as ShaderMaterial
	_mat.set_shader_parameter("seed", SEED)
	body.material_override = _mat
	body.add_to_group(SessionState.entity_group(ENTITY))
	body.set_meta(CameraDirector.FOCUS_BOUNDS_META, AABB(-Vector3.ONE, Vector3.ONE * 2.0))
	body.set_meta(&"label_radius", GenesisLayout.PLANET_RADIUS)
	body.visible = false
	# Lit by the rig's planet key too (a key of its own: the formed world is the most beautiful body).
	body.layers = 1 | GenesisLayout.PLANET_KEY_LAYER
	pivot.add_child(body)

	pick_body = StaticBody3D.new()
	pick_body.name = "PickBody"
	pick_body.collision_layer = 0
	pick_body.collision_mask = 0
	pick_body.set_meta(&"entity_id", ENTITY)
	var cs := CollisionShape3D.new()
	_shape = SphereShape3D.new()
	_shape.radius = GenesisLayout.PLANET_RADIUS
	cs.shape = _shape
	pick_body.add_child(cs)
	pick_body.position = GenesisLayout.PLANET_CENTER
	add_child(pick_body)

	anchor_node = Node3D.new()
	anchor_node.name = "PlanetAnchor"
	anchor_node.position = GenesisLayout.PLANET_CENTER
	anchor_node.set_meta(&"audio_anchor", &"planet")
	add_child(anchor_node)

	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)
	Simulation.world_rebuilt.connect(_update.bind(0.0))
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _on_quality(profile: Dictionary) -> void:
	var level := int(profile.get("level", QualityProfiles.Level.HIGH))
	if level == _level:
		return
	_level = level
	body.mesh = PlanetSphere.build_for_level(1.0, level)
	_mat.set_shader_parameter("detail", MaterialLibrary.PLANET_DETAIL[clampi(level, 0, 3)])


func _update(delta: float) -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var r := GenesisChoreography.planet_radius(g, t)
	var f := GenesisChoreography.planet_formation(g, t)
	var heat := GenesisChoreography.planet_heat(g, t)
	var crust := GenesisChoreography.planet_crust(g, t)
	var atmo := GenesisChoreography.planet_atmosphere(g, t)
	if not is_equal_approx(r, _written[0]):
		_written[0] = r
		var exists := r > 0.001
		body.visible = exists
		body.scale = Vector3.ONE * maxf(r, 0.001)
		_shape.radius = maxf(r, 0.05)
		pick_body.collision_layer = 2 if exists else 0
	_write(1, "formation", f)
	_write(2, "heat", heat)
	_write(3, "crust", crust)
	_write(4, "atmosphere", atmo)
	var m := MotionClock.now()
	_mat.set_shader_parameter("motion_time", m)
	body.rotation.y = TAU * fposmod(m / SPIN_PERIOD, 1.0)
	var want := 1.0 if Session.selected == ENTITY else (0.5 if Session.hovered == ENTITY else 0.0)
	if not is_equal_approx(_select, want):
		_select = move_toward(_select, want, SELECT_RATE * delta) if delta > 0.0 else want
		_mat.set_shader_parameter("select", _select)


func _write(slot: int, uniform: String, v: float) -> void:
	if is_equal_approx(v, _written[slot]):
		return
	_written[slot] = v
	_mat.set_shader_parameter(uniform, v)


## Current radius (tests/debug).
func radius() -> float:
	return maxf(_written[0], 0.0)


## Material of the planet (tests/debug).
func material() -> ShaderMaterial:
	return _mat
