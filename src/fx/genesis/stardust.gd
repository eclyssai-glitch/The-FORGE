class_name Stardust
extends Node3D
## The star dust of the GENESIS scene (light, soft motes; never a pattern). Owner: animator.
##  - River: MIKU's gown dissolves into a slow river of pearl dust that pours from the hem. Asleep
##    it only drifts down into the mist; while the world forms (dust.gathered -> planet.stable) the
##    river bends and feeds the new world between the hands; afterwards it relaxes into a gentle
##    fall again. Ambient flow (MotionClock); the bend and the brightness are narrative.
##  - Gathering dust: at dust.gathered a wide, thin disc of gold/pearl dust appears around the
##    place of the new world and spirals in until planet.seeded feeds it into the seed. Pure
##    function of the simulation time (pause freezes it, seek rebuilds it).
##  - Accretion disc: from planet.seeded until planet.stable, three bands of dust circle the forming
##    world in its equatorial plane at different speeds (ambient rotation, narrative presence).
##  - Motes: a very sparse field of soft pearl motes in the air around MIKU (ambient scale and depth).
## Deterministic MoteClouds (MaterialLibrary.mote), counts scaled by Quality.profile["particles"];
## whole-cloud fades use GeometryInstance3D.transparency (one property, no buffer rewrite).

## River: motes, life (s), fall length, spread, sizes; how far it bends to the planet.
const RIVER_MOTES := 300
const RIVER_LIFE := 11.0
const RIVER_FALL := 5.5
const RIVER_SIZE := 0.075
const RIVER_ALPHA := 0.42
## River presence asleep / awake (share of RIVER_ALPHA).
const RIVER_PRESENCE := Vector2(0.25, 1.0)
## Feeding the planet: rises at dust.gathered, holds until stable, then relaxes to FEED_REST.
const FEED_RISE := 4.0
const FEED_FALL := 6.0
const FEED_REST := 0.0
## Gathering dust: motes, disc radii, thickness, turns while converging, sizes.
const DUST_MOTES := 420
const DUST_RADII := Vector2(2.2, 7.0)
const DUST_THICKNESS := 0.5
const DUST_TURNS := 0.85
const DUST_SIZE := 0.07
const DUST_ALPHA := 0.55
## Accretion disc: motes per band, band radii (share: inner edge follows the planet radius), band
## periods (s), sizes, peak alpha.
const DISC_MOTES := 120
const DISC_BANDS: Array[Vector2] = [Vector2(1.15, 1.55), Vector2(1.5, 2.1), Vector2(2.0, 2.75)]
const DISC_PERIODS: Array[float] = [16.0, 26.0, 40.0]
const DISC_SIZE := 0.055
const DISC_ALPHA := 0.5
const DISC_THICKNESS := 0.08
## Air motes: count, box, size, alpha, drift period.
const AIR_MOTES := 160
const AIR_EXTENTS := Vector3(16.0, 9.0, 12.0)
const AIR_CENTER := Vector3(0.0, 4.5, 0.0)
const AIR_SIZE := 0.08
const AIR_ALPHA := 0.16

var river: MoteCloud
var dust: MoteCloud
var disc_bands: Array[MoteCloud] = []
var air: MoteCloud

var _hem := Vector3.ZERO
var _hem_radius := 1.1
var _river_seed := PackedVector3Array()
var _dust_seed := PackedVector3Array()
var _air_seed := PackedVector3Array()
var _dust_written := -1.0
var _disc_written := -1.0
var _disc_radius := -1.0


func _ready() -> void:
	var miku := GenesisLayout.miku_transform()
	_hem = miku * GenesisLayout.anchor("miku_body", "gown_hem_center", Vector3(-0.18, -4.1, -0.34))
	var hr: Variant = GenesisLayout.anchors("miku_body").get("gown_hem_radius", 1.16)
	_hem_radius = float(hr) * GenesisLayout.MIKU_SCALE

	river = _cloud("River", RIVER_MOTES, Palette.PEARL.lerp(Palette.BLUSH, 0.5), RIVER_SIZE, Vector2(1.0, 3.0))
	for i in RIVER_MOTES:
		# x: azimuth share, y: life offset, z: personal variation.
		_river_seed.append(Vector3(Motion.hash01(i * 3 + 1), Motion.hash01(i * 5 + 2), Motion.hash01(i * 7 + 3)))

	dust = _cloud("GatheringDust", DUST_MOTES, Palette.GOLD.lerp(Palette.PEARL, 0.35), DUST_SIZE, Vector2(1.0, 3.0))
	dust.position = GenesisLayout.PLANET_CENTER
	dust.rotation = GenesisLayout.PLANET_TILT
	dust.visible = false
	for i in DUST_MOTES:
		_dust_seed.append(Vector3(Motion.hash01(i * 11 + 4), Motion.hash01(i * 13 + 5), Motion.hash01(i * 17 + 6)))

	for b in DISC_BANDS.size():
		var c := _cloud("DiscBand%d" % b, DISC_MOTES, Palette.GOLD.lerp(Palette.MAGMA, 0.25 * float(2 - b)).lerp(Palette.PEARL, 0.15 * b),
			DISC_SIZE, Vector2(1.0, 3.0))
		c.position = GenesisLayout.PLANET_CENTER
		c.rotation = GenesisLayout.PLANET_TILT
		c.visible = false
		disc_bands.append(c)

	air = _cloud("Air", AIR_MOTES, Palette.PEARL, AIR_SIZE, Vector2(3.0, 8.0))
	air.position = AIR_CENTER
	for i in AIR_MOTES:
		_air_seed.append(Vector3(Motion.hash01(i * 19 + 7) * 2.0 - 1.0, Motion.hash01(i * 23 + 8) * 2.0 - 1.0,
			Motion.hash01(i * 29 + 9) * 2.0 - 1.0))

	Simulation.world_rebuilt.connect(_on_rebuilt)
	_update()


func _cloud(n: String, count: int, color: Color, size: float, near: Vector2) -> MoteCloud:
	var c := MoteCloud.new()
	c.name = n
	c.setup(count, color, size, near, true, AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80)))
	add_child(c)
	return c


func _process(_delta: float) -> void:
	_update()


func _on_rebuilt() -> void:
	_dust_written = -1.0
	_disc_written = -1.0
	_disc_radius = -1.0
	_update()


func _update() -> void:
	var g := Simulation.genesis
	var t := Simulation.time
	var m := MotionClock.now()
	_update_river(g, t, m)
	_update_dust(g, t)
	_update_disc(g, t, m)
	_update_air(m)


## Feeding factor 0..1 of the river (bends towards the forming world).
static func feed(g: GenesisState, t: float) -> float:
	if g.dust_at < 0.0:
		return 0.0
	var until := g.stable_at if g.stable_at >= 0.0 else INF
	return maxf(Motion.window(g.dust_at, t, FEED_RISE, until, FEED_FALL), FEED_REST * Motion.smooth(g.stable_at, t, FEED_FALL))


func _update_river(g: GenesisState, t: float, m: float) -> void:
	var presence := lerpf(RIVER_PRESENCE.x, RIVER_PRESENCE.y, GenesisChoreography.awaken(g, t))
	var k := feed(g, t)
	var planet := GenesisLayout.PLANET_CENTER
	var pr := maxf(GenesisChoreography.planet_radius(g, t), 0.35)
	var col := Color(1, 1, 1, 0)
	for i in river.visible_count:
		var s := _river_seed[i]
		var u := fposmod(m / (RIVER_LIFE * (0.8 + 0.4 * s.z)) + s.y, 1.0)
		var az := TAU * s.x + 0.6 * sin(TAU * (m / 40.0 + s.z))
		var start := _hem + Vector3(sin(az), 0.0, cos(az)) * _hem_radius * (0.55 + 0.45 * s.z)
		# Free fall: down, slowly widening, a lazy swirl.
		var sw := 0.35 * u * sin(TAU * (u * 0.8 + s.z) + m * 0.15)
		var free := start + Vector3(sw + (start.x - _hem.x) * 0.35 * u, -RIVER_FALL * u * (0.7 + 0.3 * s.z),
			(start.z - _hem.z) * 0.35 * u + 0.8 * u * u)
		var p := free
		if k > 0.0:
			# Feeding: a curve from the hem down and forward into the planet's upper hemisphere.
			# Into the planet's back (the side facing MIKU), spread around its equator.
			var target := planet + Vector3(sin(az) * 0.55, 0.3 * cos(az * 1.3 + s.z), -1.0).normalized() * pr
			var ctrl := (start + target) * 0.5 + Vector3(0.0, -0.7, 0.0)
			var e := u
			var q := start.lerp(ctrl, e).lerp(ctrl.lerp(target, e), e)
			q += Vector3(sw * (1.0 - e), 0.0, 0.0)
			p = free.lerp(q, k)
		var fade := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.62, 1.0, u))
		col.a = RIVER_ALPHA * presence * fade * (0.6 + 0.4 * s.z)
		river.set_mote(i, p, 0.6 + 0.8 * s.z * (1.0 - 0.5 * u), col)
	river.commit()


func _update_dust(g: GenesisState, t: float) -> void:
	var vis := GenesisChoreography.dust_visible(g, t)
	var c := GenesisChoreography.dust_converge(g, t)
	dust.visible = vis > 0.002
	if not dust.visible:
		return
	dust.transparency = 1.0 - clampf(vis, 0.0, 1.0)
	if is_equal_approx(c, _dust_written):
		return
	_dust_written = c
	var col := Color(1, 1, 1, 0)
	for i in dust.visible_count:
		var s := _dust_seed[i]
		# Each grain converges on its own schedule (outer grains later), spiralling in.
		var ci := clampf((c - s.y * 0.35) / 0.65, 0.0, 1.0)
		var e := Motion.eased(ci, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
		var r0 := lerpf(DUST_RADII.x, DUST_RADII.y, sqrt(s.x))
		var r := lerpf(r0, 0.22 + 0.2 * s.z, e)
		var ang := TAU * s.z + DUST_TURNS * TAU * e * (1.6 - s.x * 0.6) + c * 0.6
		var h := (s.y - 0.5) * DUST_THICKNESS * (1.0 - e) * (r0 / DUST_RADII.y + 0.3)
		col.a = DUST_ALPHA * (0.45 + 0.55 * s.z) * smoothstep(0.0, 0.25, 1.0 - ci * 0.7)
		col.r = 1.0 + 0.6 * e
		col.g = 1.0 + 0.6 * e
		col.b = 1.0 + 0.6 * e
		dust.set_mote(i, Vector3(sin(ang) * r, h, cos(ang) * r), 0.7 + 0.7 * s.z * (1.0 - 0.4 * e), col)
	dust.commit()


func _update_disc(g: GenesisState, t: float, m: float) -> void:
	var d := GenesisChoreography.accretion_disc(g, t)
	var pr := GenesisChoreography.planet_radius(g, t)
	var shown := d > 0.002
	for b in disc_bands.size():
		var c := disc_bands[b]
		c.visible = shown
		if shown:
			c.rotation.y = TAU * fposmod(m / DISC_PERIODS[b], 1.0)
			c.transparency = 1.0 - clampf(d, 0.0, 1.0)
	if not shown:
		return
	# Band radii follow the planet (the disc hugs the growing world); rewrite only when it changes.
	var base := maxf(pr, 0.45)
	if is_equal_approx(base, _disc_radius) and _disc_written >= 0.0:
		return
	_disc_radius = base
	_disc_written = d
	var col := Color(1, 1, 1, 0)
	for b in disc_bands.size():
		var c := disc_bands[b]
		var band := DISC_BANDS[b]
		for i in c.visible_count:
			var hx := Motion.hash01(i * 41 + b * 997 + 1)
			var hy := Motion.hash01(i * 43 + b * 991 + 2)
			var hz := Motion.hash01(i * 47 + b * 983 + 3)
			var r := base * lerpf(band.x, band.y, hx)
			var ang := TAU * hy
			col.a = DISC_ALPHA * (0.35 + 0.65 * hz) * (1.0 - 0.25 * b)
			c.set_mote(i, Vector3(sin(ang) * r, (hz - 0.5) * DISC_THICKNESS * r, cos(ang) * r), 0.6 + 0.8 * hz, col)
		c.commit()


func _update_air(m: float) -> void:
	var col := Color(1, 1, 1, 0)
	for i in air.visible_count:
		var s := _air_seed[i]
		var ph := TAU * (m / (60.0 + 30.0 * absf(s.z)) + s.x)
		var p := Vector3(s.x * AIR_EXTENTS.x + 0.6 * sin(ph), s.y * AIR_EXTENTS.y + 0.4 * sin(ph * 0.7 + s.z),
			s.z * AIR_EXTENTS.z + 0.5 * cos(ph * 0.8))
		col.a = AIR_ALPHA * (0.4 + 0.6 * (0.5 + 0.5 * sin(ph * 1.3 + s.y * 4.0)))
		air.set_mote(i, p, 0.5 + 0.8 * absf(s.y), col)
	air.commit()
