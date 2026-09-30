class_name GenesisChoreography
extends RefCounted
## GENESIS event -> visual value, as pure functions of (GenesisState, simulation time). Owner:
## animator. Every narrative value of the GENESIS scene comes from here, so pause, seek and
## reset always rebuild the exact frame of an instant (docs/ANIMATION.md, "GENESIS").
## Ambient motion (breathing, drift, orbits, halo turn) is not here: it runs on MotionClock.
## Nothing flashes or pops: every value eases in over seconds (formation = swell/accretion,
## Palette.T_SWELL) and is continuous in time (tests sample it every 0.02 s).

# --- MIKU ------------------------------------------------------------------------------------------
## Awakening: porcelain inner light, gown, key/rim lights (s from miku.awaken).
const AWAKEN_DUR := 5.0
## Hair spun out from the root (s from miku.awaken), from HAIR_ASLEEP of its length.
const HAIR_GROW_DUR := 8.0
const HAIR_ASLEEP := 0.14
## Hair / gown brightness asleep and awake.
const HAIR_INTENSITY := Vector2(0.28, 0.8)
const GOWN_PRESENCE := Vector2(0.2, 1.0)
## Halo appears after the seed lights (delay, swell in seconds from miku.awaken).
const HALO_DELAY := 1.2
const HALO_DUR := 6.0
## The seed on the brow: lights first (s), then surges gently on each act of creation.
const SEED_DUR := 2.2
const SEED_SURGE := 0.55
const SEED_SURGE_DUR := 3.0

# --- Hands -------------------------------------------------------------------------------------------
## Rise out of the mist (s from hands.summoned): slow and heavy, with a small settle at the end.
const HANDS_RISE := 7.0
## Share of the rise the settle takes, and its overshoot (share of the summon offset).
const HANDS_SETTLE := 0.3
const HANDS_OVERSHOOT := 0.035
## Fade out of the mist over the first share of the rise.
const HANDS_FADE := 0.45
## Work envelope: rises at dust.gathered, holds until planet.stable, then rests.
const WORK_RISE := 2.5
const WORK_FALL := 4.0
## The right hand presses on every act of formation (seeded, each layer): rise, fall (s).
const SCULPT_RISE := 1.1
const SCULPT_FALL := 2.6
## Kintsugi: resting glow once summoned, while working, surge per press, and after stable.
const VEINS_SUMMONED := 0.16
const VEINS_WORK := 0.42
const VEINS_PRESS := 0.34
const VEINS_STABLE := 0.3

# --- Dust and planet -----------------------------------------------------------------------------------
## Dust converges between the hands from dust.gathered into the seed (s).
const DUST_CONVERGE := 6.0
## Dust visible (share of the convergence already fed into the seed hides the rest).
const DUST_FEED := 2.0
## Planet swell of each step (seed, mantle, crust, sky): radius grows over T_SWELL.
const SWELL := Palette.T_SWELL
## Accretion patches of the seed (formation uniform 0->1).
const ACCRETE_DUR := 4.2
## Heat: the seed glows at SEED_HEAT, the mantle at 1; the crust cools it to COOL_HEAT (s).
const SEED_HEAT := 0.72
const COOL_DUR := 9.0
const COOL_HEAT := 0.14
## Crust plates settle, sky forms (s from their layer event).
const CRUST_DUR := 5.5
const SKY_DUR := 4.5
## Accretion disc around the forming planet: from seeded (rise) until stable (fall).
const DISC_RISE := 2.5
const DISC_FALL := 3.5
const STABLE_DUR := 3.0

# --- Orbital system -----------------------------------------------------------------------------------
const MOON_SWELL := Palette.T_SWELL
const RING_SWEEP := 3.6
const BELT_FORM := 4.5
## Each rock of the belt swells over this share of BELT_FORM, starting at a stable per-rock offset.
const BELT_ROCK_SWELL := 0.35
## Threads: woven one after the other (stagger), each spun over LINK_WEAVE seconds.
const LINK_WEAVE := 2.2
const LINK_STAGGER := 0.32

# --- Light ----------------------------------------------------------------------------------------------
## Light levels asleep (before miku.awaken) and awake. Keys: back (warm contraluz), rim (ICE),
## key (PEARL ¾ side), fill (NEBULA), ambient (environment ambient energy).
const LIGHT_ASLEEP := {"back": 1.1, "rim": 0.25, "key": 0.12, "fill": 0.04, "ambient": 0.16}
const LIGHT_AWAKE := {"back": 2.3, "rim": 1.25, "key": 1.05, "fill": 0.12, "ambient": 0.26}
## Planet glow (omni at the planet): energy at full heat and formation; a formed world keeps
## PLANET_LIGHT_REST of it (its sky and the last embers still light the palms).
const PLANET_LIGHT := 2.6
const PLANET_LIGHT_REST := 0.3


# --- MIKU ------------------------------------------------------------------------------------------

static func awaken(g: GenesisState, t: float) -> float:
	return Motion.smooth(g.awaken_at, t, AWAKEN_DUR)


static func hair_reveal(g: GenesisState, t: float) -> float:
	var p := Motion.eased(Motion.progress(g.awaken_at, t, HAIR_GROW_DUR), Tween.TRANS_CUBIC, Tween.EASE_OUT)
	return lerpf(HAIR_ASLEEP, 1.0, p)


static func hair_intensity(g: GenesisState, t: float) -> float:
	return lerpf(HAIR_INTENSITY.x, HAIR_INTENSITY.y, awaken(g, t))


static func gown_presence(g: GenesisState, t: float) -> float:
	return lerpf(GOWN_PRESENCE.x, GOWN_PRESENCE.y, awaken(g, t))


static func halo(g: GenesisState, t: float) -> float:
	if g.awaken_at < 0.0:
		return 0.0
	return Motion.smooth(g.awaken_at + HALO_DELAY, t, HALO_DUR)


## Brightness of the seed on MIKU's brow: 0 asleep, 1 awake, up to 1 + SEED_SURGE while she
## creates (seeded, each layer, each moon, ring, belt, links).
static func seed_light(g: GenesisState, t: float) -> float:
	var s := Motion.smooth(g.awaken_at, t, SEED_DUR)
	var surge := 0.0
	for at in creation_times(g):
		surge = maxf(surge, _bump(at, t, 0.8, SEED_SURGE_DUR))
	return s * (1.0 + SEED_SURGE * surge)


## Times of every act of creation that has happened (seeded, layers, moons, ring, belt, links).
static func creation_times(g: GenesisState) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for at in [g.seeded_at, g.ring_at, g.belt_at, g.links_at]:
		if at >= 0.0:
			out.append(at)
	for at in g.planet_layer_times:
		if at >= 0.0:
			out.append(at)
	for at in g.moon_times:
		if at >= 0.0:
			out.append(at)
	return out


# --- Hands -------------------------------------------------------------------------------------------

## Rise of the hands 0..1 (0 = in the mist, 1 = rest pose). Eases in and out, overshoots the rest
## pose by HANDS_OVERSHOOT near the end and settles back (anticipation and settling).
static func hands_rise(g: GenesisState, t: float) -> float:
	var x := Motion.progress(g.hands_at, t, HANDS_RISE)
	var body := Motion.eased(x / (1.0 - HANDS_SETTLE * 0.5))
	var settle_x := clampf((x - (1.0 - HANDS_SETTLE)) / HANDS_SETTLE, 0.0, 1.0)
	return body + HANDS_OVERSHOOT * sin(PI * settle_x) * (1.0 - settle_x * 0.5) * (1.0 if x < 1.0 else 0.0)


## Visibility of the hands 0..1 (they fade in from the mist over the first HANDS_FADE of the rise).
static func hands_visible(g: GenesisState, t: float) -> float:
	return Motion.smooth(g.hands_at, t, HANDS_RISE * HANDS_FADE)


## Work envelope 0..1: from dust.gathered until planet.stable.
static func hands_work(g: GenesisState, t: float) -> float:
	if g.dust_at < 0.0:
		return 0.0
	var until := g.stable_at if g.stable_at >= 0.0 else INF
	return Motion.window(g.dust_at, t, WORK_RISE, until, WORK_FALL)


## Press of the right hand 0..1: a bump on every act of formation (seeded and each layer).
static func sculpt_press(g: GenesisState, t: float) -> float:
	var p := _bump(g.seeded_at, t, SCULPT_RISE, SCULPT_FALL)
	for at in g.planet_layer_times:
		p = maxf(p, _bump(at, t, SCULPT_RISE, SCULPT_FALL))
	return p


## Kintsugi of a hand 0..1. `right` presses on each act of formation; the left glows with the work.
static func veins(g: GenesisState, t: float, right: bool) -> float:
	if g.hands_at < 0.0:
		return 0.0
	var v := VEINS_SUMMONED * hands_visible(g, t)
	var work := hands_work(g, t)
	var press := sculpt_press(g, t) * (1.0 if right else 0.6)
	var working := VEINS_WORK * work + VEINS_PRESS * press
	var rest := VEINS_STABLE * Motion.smooth(g.stable_at, t, STABLE_DUR)
	return clampf(maxf(v + working, rest), 0.0, 1.0)


# --- Dust and planet -----------------------------------------------------------------------------------

## Convergence of the gathered dust 0..1 (0 = wide disc, 1 = in the seed).
static func dust_converge(g: GenesisState, t: float) -> float:
	var end := g.seeded_at if g.seeded_at >= 0.0 else g.dust_at + DUST_CONVERGE
	if g.dust_at < 0.0:
		return 0.0
	var dur := maxf(end - g.dust_at, 0.5) + DUST_FEED * 0.5
	return Motion.progress(g.dust_at, t, dur)


## Visibility of the dust cloud 0..1: fades in at dust.gathered, fades out as it feeds the seed.
static func dust_visible(g: GenesisState, t: float) -> float:
	if g.dust_at < 0.0:
		return 0.0
	var fade_in := Motion.smooth(g.dust_at, t, 1.8)
	var fade_out := Motion.smooth(g.seeded_at, t, DUST_FEED) if g.seeded_at >= 0.0 else 0.0
	return fade_in * (1.0 - fade_out)


## Swell 0..1 of formation step `i` (0 seed, 1 mantle, 2 crust, 3 sky).
static func planet_step(g: GenesisState, t: float, i: int) -> float:
	var at := g.seeded_at if i == 0 else g.layer_at(i - 1)
	return Motion.smooth(at, t, SWELL)


## Radius of the forming planet (0 before seeded; grows step by step to PLANET_RADIUS).
static func planet_radius(g: GenesisState, t: float) -> float:
	var radii := GenesisLayout.PLANET_STEP_RADII
	var r := radii[0] * planet_step(g, t, 0)
	for i in range(1, radii.size()):
		r += (radii[i] - radii[i - 1]) * planet_step(g, t, i)
	return r


## `formation` uniform of the planet (accretion of the seed).
static func planet_formation(g: GenesisState, t: float) -> float:
	return Motion.eased(Motion.progress(g.seeded_at, t, ACCRETE_DUR), Tween.TRANS_SINE, Tween.EASE_OUT)


## `heat` uniform: the seed glows, the mantle burns, the crust cools it.
static func planet_heat(g: GenesisState, t: float) -> float:
	if g.seeded_at < 0.0:
		return 0.0
	var h := lerpf(SEED_HEAT, 1.0, planet_step(g, t, 1))
	var cool := Motion.eased(Motion.progress(g.layer_at(1), t, COOL_DUR), Tween.TRANS_SINE, Tween.EASE_OUT)
	return lerpf(h, COOL_HEAT, cool)


static func planet_crust(g: GenesisState, t: float) -> float:
	return Motion.smooth(g.layer_at(1), t, CRUST_DUR)


static func planet_atmosphere(g: GenesisState, t: float) -> float:
	return Motion.smooth(g.layer_at(2), t, SKY_DUR)


## Accretion disc around the planet 0..1: from seeded until stable.
static func accretion_disc(g: GenesisState, t: float) -> float:
	if g.seeded_at < 0.0:
		return 0.0
	var until := g.stable_at if g.stable_at >= 0.0 else INF
	return Motion.window(g.seeded_at, t, DISC_RISE, until, DISC_FALL)


static func stable(g: GenesisState, t: float) -> float:
	return Motion.smooth(g.stable_at, t, STABLE_DUR)


# --- Orbital system -----------------------------------------------------------------------------------

static func moon(g: GenesisState, t: float, i: int) -> float:
	return g.moon_progress(i, t, MOON_SWELL)


static func ring(g: GenesisState, t: float) -> float:
	return Motion.eased(Motion.progress(g.ring_at, t, RING_SWEEP), Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## Overall belt formation 0..1.
static func belt(g: GenesisState, t: float) -> float:
	return Motion.progress(g.belt_at, t, BELT_FORM)


## Swell 0..1 of belt rock `index` of `count`: each rock starts at a stable pseudo-random offset.
static func belt_rock(g: GenesisState, t: float, index: int) -> float:
	var p := belt(g, t)
	var start := Motion.hash01(index * 7 + 3) * (1.0 - BELT_ROCK_SWELL)
	return Motion.eased(clampf((p - start) / BELT_ROCK_SWELL, 0.0, 1.0))


## Weave 0..1 of relational thread `i` (GenesisScript.LINKS order).
static func link(g: GenesisState, t: float, i: int) -> float:
	if g.links_at < 0.0:
		return 0.0
	return Motion.eased(Motion.progress(g.links_at + i * LINK_STAGGER, t, LINK_WEAVE), Tween.TRANS_SINE, Tween.EASE_OUT)


## Time thread `i` finished weaving (-1 before links.woven).
static func link_done_at(g: GenesisState, i: int) -> float:
	return g.links_at + i * LINK_STAGGER + LINK_WEAVE if g.links_at >= 0.0 else -1.0


# --- Light ----------------------------------------------------------------------------------------------

## Light levels of the rig at (g, t) into `out` (keys of LIGHT_AWAKE + "planet"): asleep -> awake
## with the awakening, the planet glow with heat and formation.
static func light_levels(g: GenesisState, t: float, out: Dictionary) -> Dictionary:
	var a := awaken(g, t)
	for k: String in LIGHT_AWAKE:
		out[k] = lerpf(float(LIGHT_ASLEEP[k]), float(LIGHT_AWAKE[k]), a)
	out["planet"] = PLANET_LIGHT * maxf(planet_heat(g, t), PLANET_LIGHT_REST * planet_crust(g, t)) * planet_formation(g, t)
	return out


# --- helpers --------------------------------------------------------------------------------------------

## 0 before `at`, eases up to 1 over `rise`, then down to 0 over `fall` (smooth bump).
static func _bump(at: float, t: float, rise: float, fall: float) -> float:
	if at < 0.0 or t < at:
		return 0.0
	if t < at + rise:
		return Motion.eased((t - at) / rise)
	return 1.0 - Motion.eased((t - at - rise) / fall)
