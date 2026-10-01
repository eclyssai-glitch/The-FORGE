class_name FormationGlow
extends Node3D
## Controlled light of creation (docs/VISUAL_DIRECTION.md §4, §6: glow only from true emission,
## never blown out, never a flash). Owner: animator.
##  - Seed flare: at planet.seeded a soft gold glow gathers at the heart of the dust and shrinks
##    into the seed as the core swells (a presence, not a flash).
##  - Formation sparks: at every act of formation (seeded, each layer, each moon, the ring) a
##    light burst of gold motes leaves the new surface, slows down and fades (FORMATION_BURST s).
##  - Arrival glints: when a thread finishes weaving, a soft glint blooms where it touches its body.
## Everything is a pure function of (Simulation.genesis, Simulation.time) — pause freezes it,
## seek rebuilds it — except the position of orbiting bodies (MotionClock, as they are drawn).
## Motes: MoteCloud (MaterialLibrary.mote); HDR only in the small cores. Counts scale with quality.

const SPARKS := 72
const SPARK_SIZE := 0.06
const BURST := 2.8
const SPARK_SPEED := Vector2(0.5, 1.6)
const SPARK_HDR := 1.8
## Seed flare: glow size range, duration, peak HDR.
const FLARE_DUR := 3.4
const FLARE_SIZE := Vector2(2.4, 0.7)
const FLARE_ALPHA := 0.32
const FLARE_CORE := 0.35
## Arrival glints: size, rise and fall (s), peak.
const GLINT_SIZE := 0.9
const GLINT_RISE := 0.35
const GLINT_FALL := 2.2
const GLINT_ALPHA := 0.4
## Climax (planet.stable): the formed world's sky lights up — a wide soft aura behind the planet
## (its disc hides the centre, so it reads as light around the limb) and a thin brighter rim
## (sizes as a share of the final radius; alphas at the peak of GenesisChoreography.climax).
const AURA_SIZE := 4.6
const AURA_ALPHA := 0.16
const AURA_RIM_SIZE := 2.5
const AURA_RIM_ALPHA := 0.42
const AURA_RIM_HDR := 1.25

var sparks: MoteCloud
var flare: MoteCloud
var glints: MoteCloud
var aura: MoteCloud
var _aura_written := -1.0

var _dirs := PackedVector3Array()
var _speeds := PackedFloat32Array()
var _written := Vector3(-9, -9, -9)


func _ready() -> void:
	sparks = MoteCloud.new()
	sparks.name = "Sparks"
	sparks.setup(SPARKS, Palette.GOLD, SPARK_SIZE, Vector2(1.0, 3.0))
	sparks.min_visible = 24
	sparks.visible = false
	add_child(sparks)
	for i in SPARKS:
		var z := Motion.hash01(i * 7 + 1) * 2.0 - 1.0
		var a := TAU * Motion.hash01(i * 11 + 2)
		var h := sqrt(maxf(1.0 - z * z, 0.0))
		_dirs.append(Vector3(h * sin(a), z, h * cos(a)))
		_speeds.append(lerpf(SPARK_SPEED.x, SPARK_SPEED.y, Motion.hash01(i * 13 + 3)))

	flare = MoteCloud.new()
	flare.name = "SeedFlare"
	flare.setup(2, Palette.GOLD.lerp(Palette.BLUSH, 0.3), 1.0, Vector2(1.0, 3.0), false)
	flare.position = GenesisLayout.PLANET_CENTER
	flare.visible = false
	add_child(flare)

	glints = MoteCloud.new()
	glints.name = "Glints"
	glints.setup(GenesisScript.LINKS.size(), Palette.GOLD.lerp(Palette.PEARL, 0.4), GLINT_SIZE, Vector2(1.0, 3.0), false)
	glints.visible = false
	add_child(glints)

	aura = MoteCloud.new()
	aura.name = "StableAura"
	aura.setup(2, Palette.ICE.lerp(Palette.PEARL, 0.55), 1.0, Vector2(1.0, 3.0), false)
	aura.position = GenesisLayout.PLANET_CENTER
	aura.visible = false
	add_child(aura)
	Simulation.world_rebuilt.connect(_on_rebuilt)
	_update()


func _process(_delta: float) -> void:
	_update()


func _on_rebuilt() -> void:
	_written = Vector3(-9, -9, -9)
	_aura_written = -1.0
	_update()


## Kind of burst: planet event (seeded / layer), moon `i` (MOON_KIND + i), ring.
const MOON_KIND := 10
const RING_KIND := 20


## Latest formation burst active at `t`: [at, kind] (kind -1 when none). Planet events burst from
## the planet surface, moons from their body, the ring from its circle. No allocation.
static func active_burst_kind(g: GenesisState, t: float) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	best = _later(best, g.seeded_at, 0, t)
	for i in g.planet_layer_times.size():
		best = _later(best, g.planet_layer_times[i], 1 + i, t)
	for i in g.moon_times.size():
		best = _later(best, g.moon_times[i], MOON_KIND + i, t)
	return _later(best, g.ring_at, RING_KIND, t)


static func _later(best: Vector2, at: float, kind: int, t: float) -> Vector2:
	if at < 0.0 or t < at or t > at + BURST or at < best.x:
		return best
	return Vector2(at, kind)


func _update() -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var m := MotionClock.now()
	_update_sparks(g, t, m)
	_update_flare(g, t)
	_update_glints(g, t, m)
	_update_aura(g, t)


## The world's sky lights up at the climax (pure function of the simulation time).
func _update_aura(g: GenesisState, t: float) -> void:
	var c := GenesisChoreography.climax(g, t)
	aura.visible = c > 0.002
	if not aura.visible or is_equal_approx(c, _aura_written):
		return
	_aura_written = c
	var r := GenesisLayout.PLANET_RADIUS
	aura.set_mote(0, Vector3.ZERO, r * AURA_SIZE * (0.85 + 0.15 * c), Color(1, 1, 1, AURA_ALPHA * c))
	aura.set_mote(1, Vector3.ZERO, r * AURA_RIM_SIZE, Color(AURA_RIM_HDR, AURA_RIM_HDR, AURA_RIM_HDR, AURA_RIM_ALPHA * c))
	aura.commit()


## Climax aura level last written (tests/debug).
func aura_level() -> float:
	return maxf(_aura_written, 0.0)


func _update_sparks(g: GenesisState, t: float, m: float) -> void:
	var b := active_burst_kind(g, t)
	var kind := int(b.y)
	sparks.visible = kind >= 0
	if kind < 0:
		return
	var p := clampf((t - b.x) / BURST, 0.0, 1.0)
	var centre := GenesisLayout.PLANET_CENTER
	var radius := GenesisChoreography.planet_radius(g, b.x + 0.8)
	var ring := kind == RING_KIND
	if kind >= MOON_KIND and kind < RING_KIND:
		centre = GenesisLayout.moon_position(kind - MOON_KIND, m)
		radius = GenesisLayout.MOON_RADII[kind - MOON_KIND]
	elif ring:
		radius = (GenesisLayout.RING_INNER + GenesisLayout.RING_OUTER) * 0.5
	var ring_basis := Basis.from_euler(GenesisLayout.PLANET_TILT)
	var travel := Motion.eased(p, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	var col := Color(SPARK_HDR, SPARK_HDR, SPARK_HDR, 0.0)
	var fade := (1.0 - p) * (1.0 - p) * smoothstep(0.0, 0.08, p)
	for i in sparks.visible_count:
		var d := _dirs[i]
		var pos: Vector3
		if ring:
			var flat := Vector3(d.x, 0.0, d.z).normalized() if Vector2(d.x, d.z).length() > 1e-3 else Vector3.BACK
			pos = centre + ring_basis * (flat * (radius + d.y * 0.35 * travel) + Vector3.UP * d.y * 0.2 * travel)
		else:
			pos = centre + d * (radius * 1.02 + _speeds[i] * travel)
		col.a = fade * (0.5 + 0.5 * Motion.hash01(i * 5 + 9))
		sparks.set_mote(i, pos, 1.0 - 0.6 * p, col)
	sparks.commit()


func _update_flare(g: GenesisState, t: float) -> void:
	var p := Motion.progress(g.seeded_at, t, FLARE_DUR)
	var on := g.seeded_at >= 0.0 and t >= g.seeded_at and p < 1.0
	flare.visible = on
	if not on:
		return
	var env := sin(PI * Motion.eased(p))
	var size := lerpf(FLARE_SIZE.x, FLARE_SIZE.y, Motion.eased(p))
	if is_equal_approx(p, _written.x):
		return
	_written.x = p
	flare.set_mote(0, Vector3.ZERO, size, Color(1, 1, 1, FLARE_ALPHA * env))
	flare.set_mote(1, Vector3.ZERO, size * 0.3, Color(1.6, 1.6, 1.6, FLARE_CORE * env))
	flare.commit()


func _update_glints(g: GenesisState, t: float, m: float) -> void:
	var any := false
	for i in GenesisScript.LINKS.size():
		var done := GenesisChoreography.link_done_at(g, i)
		var a := 0.0
		if done >= 0.0 and t >= done - GLINT_RISE:
			var x := t - (done - GLINT_RISE)
			a = Motion.eased(x / GLINT_RISE) if x < GLINT_RISE else 1.0 - Motion.eased((x - GLINT_RISE) / GLINT_FALL)
		if a > 0.002:
			any = true
			glints.set_mote(i, RelationThreads.endpoint(i, false, m), 1.0, Color(1, 1, 1, GLINT_ALPHA * a))
		else:
			glints.hide_mote(i)
	glints.visible = any
	if any:
		glints.commit()
