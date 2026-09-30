class_name OrbitalSystem
extends Node3D
## The bodies around the new world and around MIKU (docs/VISUAL_DIRECTION.md §1, §5). Owner:
## animator. Documentation moons (moon_doc(), born at moon.formed), the skill ring
## (ring_skill(), laid down at ring.formed), the memory belt around MIKU (AsteroidField +
## asteroid_memory(), rocks swell in at belt.formed), and two older worlds already formed
## (NAUVE-2, KESTRE-4: planet_forming() duplicates at rest, each with a small moon), with thin
## orbit lines (orbit_line(), tubes) brightest just behind each body.
## Narrative values come from GenesisChoreography (seek/pause exact). Orbital motion, the belt
## drift and the ring's slow turn are ambient (MotionClock): every orbit is a pivot rotated by its
## phase, so a body is a child at (0, 0, r) of its pivot (GenesisLayout.orbit_point convention).
## Entities: moon_0/1 (moon mesh), ring_skill (ring quad), belt_memory (belt root at MIKU's heart,
## label_anchor on the belt), planet_far_0/1 (world root). Each visual root is in its entity group,
## hidden until its body exists; pick bodies on layer 2 are enabled with it.

const RING_SEED := 2.3
const RING_TURN := 260.0
## The ring swells from this share of its size as it forms.
const RING_SWELL_FROM := 0.72
const MOON_SEEDS: Array[float] = [0.61, 0.83]
const FAR_SEEDS: Array[float] = [0.21, 0.47]
const FAR_MOON_SEEDS: Array[float] = [0.12, 0.93]
## Orbit line tube radii (moons, distant worlds) and brightness.
const MOON_ORBIT_TUBE := 0.016
const FAR_ORBIT_TUBE := 0.03
const FAR_MOON_ORBIT_TUBE := 0.014
const ORBIT_INTENSITY := 0.42
const FAR_ORBIT_INTENSITY := 0.16
## Distant worlds: at rest, a little heat left in the cracks.
const FAR_HEAT := 0.08
## Moon glow before / after the threads reach them.
const MOON_GLOW := Vector2(0.35, 0.7)
## Belt rock sizes (min, max, bias) and seed.
const BELT_SEED := 9107
const ROCK_SCALE := Vector3(0.04, 0.24, 3.2)
## Share of the belt rocks drawn per quality (floor), rocks are geometry, not particles.
const BELT_MIN_SHARE := 0.45
const SELECT_RATE := 6.0
const MOON_KEYS: Array[String] = ["moon0", "moon1"]
const GLOW_KEYS: Array[String] = ["moon0glow", "moon1glow"]

var moons: Array[MeshInstance3D] = []
var moon_pivots: Array[Node3D] = []
var moon_orbits: Array[MeshInstance3D] = []
var ring: MeshInstance3D
var belt: Node3D
var belt_rocks: MultiMeshInstance3D
var far_planets: Array[Node3D] = []
var far_pivots: Array[Node3D] = []
var far_moon_pivots: Array[Node3D] = []
var far_orbits: Array[MeshInstance3D] = []

var _moon_mats: Array[ShaderMaterial] = []
var _moon_orbit_mats: Array[ShaderMaterial] = []
var _moon_bodies: Array[StaticBody3D] = []
var _ring_mat: ShaderMaterial
var _ring_body: StaticBody3D
var _belt_mat: ShaderMaterial
var _belt_body: StaticBody3D
var _belt_xforms: Array[Transform3D] = []
var _belt_written := -1.0
var _far_mats: Array[ShaderMaterial] = []
var _far_orbit_mats: Array[ShaderMaterial] = []
var _far_moon_mats: Array[ShaderMaterial] = []
var _select := {}
var _written := {}


func _ready() -> void:
	_build_moons()
	_build_ring()
	_build_belt()
	_build_far()
	Quality.profile_changed.connect(_on_quality)
	_on_quality(Quality.profile)
	Simulation.world_rebuilt.connect(_on_rebuilt)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _on_rebuilt() -> void:
	_belt_written = -1.0
	_update(0.0)


# ------------------------------------------------------------------------------ build


func _build_moons() -> void:
	var sphere := PlanetSphere.build(1.0, 48, 24)
	for i in GenesisScript.MOON_COUNT:
		var frame := Node3D.new()
		frame.name = "MoonOrbit%d" % i
		frame.position = GenesisLayout.PLANET_CENTER
		frame.rotation = GenesisLayout.MOON_TILTS[i]
		add_child(frame)
		var r := GenesisLayout.MOON_ORBITS[i]
		var line := _orbit_line(frame, r, MOON_ORBIT_TUBE, ORBIT_INTENSITY)
		moon_orbits.append(line)
		_moon_orbit_mats.append(line.material_override as ShaderMaterial)
		var pivot := Node3D.new()
		pivot.name = "Pivot"
		frame.add_child(pivot)
		moon_pivots.append(pivot)
		var moon := MeshInstance3D.new()
		moon.name = "Moon%d" % i
		moon.mesh = sphere
		moon.position = Vector3(0.0, 0.0, r)
		var mat := MaterialLibrary.moon_doc().duplicate() as ShaderMaterial
		mat.set_shader_parameter("seed", MOON_SEEDS[i])
		mat.set_shader_parameter("formation", 0.0)
		moon.material_override = mat
		var id := GenesisScript.moon_entity(i)
		moon.add_to_group(SessionState.entity_group(id))
		moon.set_meta(&"label_radius", GenesisLayout.MOON_RADII[i])
		moon.visible = false
		pivot.add_child(moon)
		moons.append(moon)
		_moon_mats.append(mat)
		var sb := _sphere_body(id, 1.0)
		moon.add_child(sb)
		_moon_bodies.append(sb)


func _build_ring() -> void:
	var frame := Node3D.new()
	frame.name = "RingFrame"
	frame.position = GenesisLayout.PLANET_CENTER
	frame.rotation = GenesisLayout.PLANET_TILT
	add_child(frame)
	ring = MeshInstance3D.new()
	ring.name = "Ring"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GenesisLayout.RING_OUTER * 2.0
	ring.mesh = plane
	_ring_mat = MaterialLibrary.ring_skill().duplicate() as ShaderMaterial
	_ring_mat.set_shader_parameter("inner", GenesisLayout.RING_INNER / GenesisLayout.RING_OUTER)
	_ring_mat.set_shader_parameter("outer", 1.0)
	_ring_mat.set_shader_parameter("seed", RING_SEED)
	_ring_mat.set_shader_parameter("formation", 1.0)
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_to_group(SessionState.entity_group(&"ring_skill"))
	var ro := GenesisLayout.RING_OUTER
	ring.set_meta(CameraDirector.FOCUS_BOUNDS_META, AABB(Vector3(-ro, -0.4, -ro), Vector3(ro * 2.0, 0.8, ro * 2.0)))
	ring.set_meta(&"label_anchor", Vector3(ro * 0.9, 0.0, ro * 0.4))
	ring.set_meta(&"label_radius", 0.3)
	ring.visible = false
	frame.add_child(ring)
	var mid := (GenesisLayout.RING_INNER + GenesisLayout.RING_OUTER) * 0.5
	_ring_body = _band_body(&"ring_skill", mid, GenesisLayout.RING_OUTER - GenesisLayout.RING_INNER)
	frame.add_child(_ring_body)


func _build_belt() -> void:
	belt = Node3D.new()
	belt.name = "Belt"
	belt.position = GenesisLayout.BELT_CENTER
	belt.rotation = GenesisLayout.BELT_TILT
	belt.add_to_group(SessionState.entity_group(&"belt_memory"))
	var mid := (GenesisLayout.BELT_INNER + GenesisLayout.BELT_OUTER) * 0.5
	# Named on its near right side (in front of the hero camera, off MIKU).
	belt.set_meta(&"label_anchor", OrbitLine.point(mid, mid, 0.09))
	belt.set_meta(&"label_radius", 0.8)
	var bo := GenesisLayout.BELT_OUTER
	belt.set_meta(CameraDirector.FOCUS_BOUNDS_META, AABB(Vector3(-bo, -1.0, -bo), Vector3(bo * 2.0, 2.0, bo * 2.0)))
	belt.visible = false
	add_child(belt)
	_belt_xforms = AsteroidField.transforms(GenesisLayout.BELT_ROCKS, GenesisLayout.BELT_INNER,
		GenesisLayout.BELT_OUTER, GenesisLayout.BELT_THICKNESS, BELT_SEED, ROCK_SCALE.x, ROCK_SCALE.y, ROCK_SCALE.z)
	var mm := AsteroidField.build_multimesh(AsteroidField.rock_mesh(BELT_SEED, 1.0, 1, 0.3), _belt_xforms)
	belt_rocks = MultiMeshInstance3D.new()
	belt_rocks.name = "Rocks"
	belt_rocks.multimesh = mm
	_belt_mat = MaterialLibrary.asteroid_memory().duplicate() as ShaderMaterial
	_belt_mat.set_shader_parameter("memory", 0.0)
	belt_rocks.material_override = _belt_mat
	belt_rocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	belt_rocks.custom_aabb = AABB(Vector3(-bo - 1, -2, -bo - 1), Vector3(bo * 2 + 2, 4, bo * 2 + 2))
	belt.add_child(belt_rocks)
	_belt_body = _band_body(&"belt_memory", mid, GenesisLayout.BELT_OUTER - GenesisLayout.BELT_INNER)
	belt.add_child(_belt_body)


func _build_far() -> void:
	for i in GenesisScript.FAR_PLANET_NAMES.size():
		var frame := Node3D.new()
		frame.name = "FarOrbit%d" % i
		frame.position = GenesisLayout.FAR_CENTER
		frame.rotation = GenesisLayout.FAR_TILTS[i]
		add_child(frame)
		var line := _orbit_line(frame, GenesisLayout.FAR_ORBITS[i], FAR_ORBIT_TUBE, FAR_ORBIT_INTENSITY)
		far_orbits.append(line)
		_far_orbit_mats.append(line.material_override as ShaderMaterial)
		var pivot := Node3D.new()
		pivot.name = "Pivot"
		frame.add_child(pivot)
		far_pivots.append(pivot)
		var world := Node3D.new()
		world.name = "World%d" % i
		world.position = Vector3(0.0, 0.0, GenesisLayout.FAR_ORBITS[i])
		var id := GenesisScript.far_planet_entity(i)
		world.add_to_group(SessionState.entity_group(id))
		var fr := GenesisLayout.FAR_RADII[i]
		var mr := GenesisLayout.FAR_MOON_ORBITS[i]
		world.set_meta(CameraDirector.FOCUS_BOUNDS_META, AABB(Vector3(-mr, -fr, -mr), Vector3(mr * 2.0, fr * 2.0, mr * 2.0)))
		world.set_meta(&"label_radius", fr)
		pivot.add_child(world)
		far_planets.append(world)
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = PlanetSphere.build(1.0, 64, 32)
		body.scale = Vector3.ONE * fr
		var mat := MaterialLibrary.planet_forming().duplicate() as ShaderMaterial
		mat.set_shader_parameter("seed", FAR_SEEDS[i])
		mat.set_shader_parameter("formation", 1.0)
		mat.set_shader_parameter("heat", FAR_HEAT)
		mat.set_shader_parameter("crust", 1.0)
		mat.set_shader_parameter("atmosphere", 1.0)
		body.material_override = mat
		body.rotation = Vector3(0.3 * (i + 1), 0.0, -0.2)
		world.add_child(body)
		_far_mats.append(mat)
		world.add_child(_sphere_body(id, fr))
		# Its own small moon.
		var mframe := Node3D.new()
		mframe.name = "MoonOrbit"
		mframe.rotation = Vector3(0.25 - 0.4 * i, 0.0, 0.15)
		world.add_child(mframe)
		var mline := _orbit_line(mframe, mr, FAR_MOON_ORBIT_TUBE, FAR_ORBIT_INTENSITY * 0.8)
		_far_orbit_mats.append(mline.material_override as ShaderMaterial)
		var mpivot := Node3D.new()
		mpivot.name = "Pivot"
		mframe.add_child(mpivot)
		far_moon_pivots.append(mpivot)
		var moon := MeshInstance3D.new()
		moon.name = "Moon"
		moon.mesh = PlanetSphere.build(1.0, 32, 16)
		moon.scale = Vector3.ONE * GenesisLayout.FAR_MOON_RADII[i]
		moon.position = Vector3(0.0, 0.0, mr)
		var mmat := MaterialLibrary.moon_doc().duplicate() as ShaderMaterial
		mmat.set_shader_parameter("seed", FAR_MOON_SEEDS[i])
		mmat.set_shader_parameter("formation", 1.0)
		mmat.set_shader_parameter("glow", 0.3)
		moon.material_override = mmat
		mpivot.add_child(moon)
		_far_moon_mats.append(mmat)


func _orbit_line(parent: Node3D, r: float, tube: float, intensity: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "OrbitLine"
	mi.mesh = OrbitLine.build_tube(r, r, tube, clampi(int(r * 48.0), 160, 720), 4)
	var mat := MaterialLibrary.orbit_line().duplicate() as ShaderMaterial
	mat.set_shader_parameter("intensity", intensity)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _sphere_body(id: StringName, radius: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "PickBody"
	sb.collision_layer = 2
	sb.collision_mask = 0
	sb.set_meta(&"entity_id", id)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	sb.add_child(cs)
	return sb


## Flat annulus pick body (ring, belt): trimesh of an OrbitLine band.
func _band_body(id: StringName, mid: float, width: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "PickBody"
	sb.collision_layer = 0
	sb.collision_mask = 0
	sb.set_meta(&"entity_id", id)
	var cs := CollisionShape3D.new()
	cs.shape = OrbitLine.build(mid, mid, width, 96).create_trimesh_shape()
	sb.add_child(cs)
	return sb


func _on_quality(profile: Dictionary) -> void:
	var ratio := clampf(float(profile.get("particles", 1.0)), BELT_MIN_SHARE, 1.0)
	belt_rocks.multimesh.visible_instance_count = int(round(GenesisLayout.BELT_ROCKS * ratio))


# ------------------------------------------------------------------------------ update


func _update(delta: float) -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var m := MotionClock.now()
	# Moons.
	for i in moons.size():
		var f := GenesisChoreography.moon(g, t, i)
		var ph := GenesisLayout.orbit_phase(GenesisLayout.MOON_PHASES[i], GenesisLayout.MOON_PERIODS[i], m)
		moon_pivots[i].rotation.y = TAU * ph
		moons[i].rotation.y = TAU * fposmod(m / 50.0, 1.0)
		var key: String = MOON_KEYS[i]
		if _changed(key, f):
			var exists := f > 0.001
			moons[i].visible = exists
			moons[i].scale = Vector3.ONE * GenesisLayout.MOON_RADII[i] * lerpf(0.55, 1.0, f)
			_moon_mats[i].set_shader_parameter("formation", f)
			_moon_bodies[i].collision_layer = 2 if exists else 0
			moon_orbits[i].visible = exists
			_moon_orbit_mats[i].set_shader_parameter("formation", f)
		var glow := lerpf(MOON_GLOW.x, MOON_GLOW.y, GenesisChoreography.link(g, t, 1 + i))
		if _changed(GLOW_KEYS[i], glow):
			_moon_mats[i].set_shader_parameter("glow", glow)
		_moon_orbit_mats[i].set_shader_parameter("head", ph)
		_highlight(GenesisScript.moon_entity(i), _moon_mats[i], delta)
	# Ring.
	var rf := GenesisChoreography.ring(g, t)
	if _changed("ring", rf):
		# The ring condenses outward from the world (swell + fade). The shader's angular sweep
		# (`formation` < 1) is not used yet: its leading edge raises a negative base to a power
		# (NaN on llvmpipe and several drivers) — reported to the art-director.
		ring.visible = rf > 0.001
		ring.scale = Vector3.ONE * lerpf(RING_SWELL_FROM, 1.0, rf)
		ring.transparency = 1.0 - rf if rf < 0.999 else 0.0
		_ring_mat.set_shader_parameter("formation", 1.0)
		_ring_body.collision_layer = 2 if rf > 0.5 else 0
	ring.rotation.y = TAU * fposmod(m / RING_TURN, 1.0)
	# Belt.
	var bf := GenesisChoreography.belt(g, t)
	if not is_equal_approx(bf, _belt_written):
		_write_belt(g, t, bf)
	belt_rocks.rotation.y = TAU * fposmod(m / GenesisLayout.BELT_PERIOD, 1.0)
	# Distant worlds.
	for i in far_planets.size():
		var ph := GenesisLayout.orbit_phase(GenesisLayout.FAR_PHASES[i], GenesisLayout.FAR_PERIODS[i], m)
		far_pivots[i].rotation.y = TAU * ph
		_far_orbit_mats[i * 2].set_shader_parameter("head", ph)
		var mph := fposmod(m / GenesisLayout.FAR_MOON_PERIODS[i] + 0.3 * i, 1.0)
		far_moon_pivots[i].rotation.y = TAU * mph
		_far_orbit_mats[i * 2 + 1].set_shader_parameter("head", mph)
		_far_mats[i].set_shader_parameter("motion_time", m)
		_highlight(GenesisScript.far_planet_entity(i), _far_mats[i], delta)


func _write_belt(g: GenesisState, t: float, bf: float) -> void:
	var was := _belt_written
	_belt_written = bf
	var exists := bf > 0.0
	belt.visible = exists
	_belt_body.collision_layer = 2 if bf > 0.5 else 0
	_belt_mat.set_shader_parameter("memory", Motion.eased(clampf((bf - 0.4) / 0.6, 0.0, 1.0)))
	# Rocks swell in one by one; once fully formed (and already written so) nothing is rewritten.
	if bf >= 1.0 and was >= 1.0:
		return
	var mm := belt_rocks.multimesh
	for i in _belt_xforms.size():
		var s := GenesisChoreography.belt_rock(g, t, i) if bf < 1.0 else 1.0
		var x := _belt_xforms[i]
		mm.set_instance_transform(i, Transform3D(x.basis * maxf(s, 0.0001), x.origin))


func _changed(key: String, v: float) -> bool:
	if _written.has(key) and is_equal_approx(float(_written[key]), v):
		return false
	_written[key] = v
	return true


func _highlight(id: StringName, mat: ShaderMaterial, delta: float) -> void:
	var want := 1.0 if Session.selected == id else (0.5 if Session.hovered == id else 0.0)
	var cur := float(_select.get(id, 0.0))
	if is_equal_approx(cur, want) and _select.has(id):
		return
	cur = move_toward(cur, want, SELECT_RATE * delta) if delta > 0.0 else want
	_select[id] = cur
	mat.set_shader_parameter("select", cur)
