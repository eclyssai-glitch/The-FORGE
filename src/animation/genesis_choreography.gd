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
## Opening: in the dark only the gold seed on her brow glows (a dormant ember, SEED_DORMANT of the
## awake seed). At miku.awaken the seed blooms first and its light reveals the porcelain: the body
## comes out of the dark after REVEAL_DELAY over REVEAL_DUR (never a dark humanoid silhouette).
const SEED_DORMANT := 0.45
const REVEAL_DELAY := 1.3
const REVEAL_DUR := 2.6
## While the seed's light reveals her the porcelain glows from within (REVEAL_GLOW of inner light
## at the start of the reveal, fading out over REVEAL_GLOW_FALL s after it): she materialises as
## pale light, never as a dark translucent figure.
const REVEAL_GLOW := 1.0
const REVEAL_GLOW_FALL := 3.0
## The inner light leads the presence (it is full once REVEAL_GLOW_LEAD⁻¹ of her is there).
const REVEAL_GLOW_LEAD := 3.0
## The seed's own light blooms out of it while it reveals her (rise, fall in seconds).
const SEED_BLOOM_RISE := 1.5
const SEED_BLOOM_FALL := 5.5
## Front lights lead (the revealed body is lit, never cut out); the warm backlight follows later.
const FRONT_LIGHT_DUR := 1.6
const BACK_LIGHT_DELAY := 1.6
## Hair spun out from the root (s from miku.awaken + HAIR_DELAY: once the seed's light has begun to
## reveal her, never a comet of hair in the dark), from HAIR_ASLEEP of its length.
const HAIR_DELAY := 1.4
const HAIR_GROW_DUR := 8.0
const HAIR_ASLEEP := 0.14
## Hair / gown brightness asleep and awake (asleep: dark, only the seed).
const HAIR_INTENSITY := Vector2(0.0, 0.8)
const GOWN_PRESENCE := Vector2(0.2, 1.0)
const GOWN_REVEAL := Vector2(0.4, 0.95)
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
## After planet.stable the kintsugi cools down to VEINS_STABLE over VEINS_COOL_DUR.
const VEINS_STABLE := 0.07
const VEINS_COOL_DUR := 3.0
## Release after planet.stable: the hands let the world go, slowly (delay, duration in seconds).
const RELEASE_DELAY := 0.2
const RELEASE_DUR := 2.8

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
const LINK_WEAVE := 1.8
const LINK_STAGGER := 0.2

# --- Climax (planet.stable) -------------------------------------------------------------------------
## The peak of light is reserved to planet.stable: it rises after CLIMAX_DELAY over CLIMAX_RISE,
## holds CLIMAX_HOLD, and settles over CLIMAX_FALL to CLIMAX_REST. The session completes 3 s after
## planet.stable and its last instant is held, so every climax beat resolves by then and the light
## stays at its peak (REST 1): the held final frame is the formed world at its brightest.
const CLIMAX_DELAY := 0.2
const CLIMAX_RISE := 2.6
const CLIMAX_HOLD := 0.0
const CLIMAX_FALL := 0.0
const CLIMAX_REST := 1.0
## MIKU raises her head (delay, duration) and her halo closes into a full circle (delay, duration).
const HEAD_LIFT_DELAY := 0.3
const HEAD_LIFT_DUR := 2.7
const HALO_CLOSE_DELAY := 0.2
const HALO_CLOSE_DUR := 2.8
## One pulse runs through every thread: after WAVE_DELAY it first runs out along the link strands
## of her hair (WAVE_HAIR s, miku_hair `link_pulse`), then crosses one hop of the graph
## (GenesisScript.LINKS, breadth-first from MIKU) every WAVE_HOP seconds.
const WAVE_DELAY := 0.3
const WAVE_HAIR := 0.7
const WAVE_HOP := 1.0

# --- Light ----------------------------------------------------------------------------------------------
## Light levels asleep (before miku.awaken) and awake. Keys: back (warm contraluz), rim (ICE),
## key (PEARL ¾ side), fill (NEBULA), ambient (environment ambient energy). Asleep the scene is
## dark: only the seed glows (a dim backlight would cut her out as a dark silhouette).
const LIGHT_ASLEEP := {"back": 0.3, "rim": 0.05, "key": 0.03, "fill": 0.015, "ambient": 0.1}
const LIGHT_AWAKE := {"back": 2.3, "rim": 1.25, "key": 1.05, "fill": 0.12, "ambient": 0.26}
## Added at the climax peak (the brightest moment of the session).
const LIGHT_CLIMAX := {"back": 1.2, "rim": 0.75, "key": 0.5, "fill": 0.06, "ambient": 0.08}
## Planet glow (omni at the planet): energy at full heat and formation; a formed world keeps
## PLANET_LIGHT_REST of it (its sky and the last embers still light the palms).
const PLANET_LIGHT := 2.6
const PLANET_LIGHT_REST := 0.3
## At the climax the formed world shines with its own sky (PEARL/ICE light, rig) — above the mantle.
const PLANET_LIGHT_CLIMAX := 3.4
## Planet key (rig light on the worlds only): the formed world gets a key of its own as its crust
## and sky form (PLANET_KEY at full atmosphere, PLANET_KEY_CRUST share with the crust alone), and
## PLANET_KEY_CLIMAX more at the climax — the world is the most beautiful body of the final frame.
const PLANET_KEY := 0.85
const PLANET_KEY_CRUST := 0.5
const PLANET_KEY_CLIMAX := 0.9
## Planet rim (ICE, from behind; worlds only): with the sky, and more at the climax.
const PLANET_RIM := 0.6
const PLANET_RIM_CLIMAX := 1.1
## Weights of the "total light" proxy used to check that the climax is the peak (tests/debug).
const LIGHT_WEIGHTS := {"back": 1.0, "rim": 1.0, "key": 1.0, "fill": 1.0, "ambient": 2.0, "planet": 0.6, "planet_key": 0.5, "planet_rim": 0.3}


# --- MIKU ------------------------------------------------------------------------------------------

static func awaken(g: GenesisState, t: float) -> float:
	return Motion.smooth(g.awaken_at, t, AWAKEN_DUR)


static func hair_reveal(g: GenesisState, t: float) -> float:
	if g.awaken_at < 0.0:
		return HAIR_ASLEEP
	var p := Motion.eased(Motion.progress(g.awaken_at + HAIR_DELAY, t, HAIR_GROW_DUR), Tween.TRANS_CUBIC, Tween.EASE_OUT)
	return lerpf(HAIR_ASLEEP, 1.0, p)


static func hair_intensity(g: GenesisState, t: float) -> float:
	if g.awaken_at < 0.0:
		return HAIR_INTENSITY.x
	return lerpf(HAIR_INTENSITY.x, HAIR_INTENSITY.y, Motion.smooth(g.awaken_at + HAIR_DELAY, t, AWAKEN_DUR))


## Presence of the veil of light over the skirt: it comes once the porcelain's reveal (radial from
## the brow) has reached the skirt (GOWN_REVEAL shares of body_presence) — before that a faint veil
## over the dark reads as a dark skirt; in the dark the gown is only dust (the Stardust river).
static func gown_presence(g: GenesisState, t: float) -> float:
	var r := smoothstep(GOWN_REVEAL.x, GOWN_REVEAL.y, body_presence(g, t))
	return lerpf(GOWN_PRESENCE.x, GOWN_PRESENCE.y, awaken(g, t)) * r


static func halo(g: GenesisState, t: float) -> float:
	if g.awaken_at < 0.0:
		return 0.0
	return Motion.smooth(g.awaken_at + HALO_DELAY, t, HALO_DUR)


## Brightness of the seed on MIKU's brow: a dormant ember (SEED_DORMANT) in the dark, 1 awake, up to
## 1 + SEED_SURGE while she creates (seeded, each layer, each moon, ring, belt, links).
static func seed_light(g: GenesisState, t: float) -> float:
	var s := lerpf(SEED_DORMANT, 1.0, Motion.smooth(g.awaken_at, t, SEED_DUR))
	# No allocation per frame: every creation time is visited in place.
	var surge := maxf(maxf(_bump(g.seeded_at, t, 0.8, SEED_SURGE_DUR), _bump(g.ring_at, t, 0.8, SEED_SURGE_DUR)),
		maxf(_bump(g.belt_at, t, 0.8, SEED_SURGE_DUR), _bump(g.links_at, t, 0.8, SEED_SURGE_DUR)))
	surge = maxf(surge, _bump(g.stable_at, t, CLIMAX_DELAY + CLIMAX_RISE, SEED_SURGE_DUR * 2.0))
	for at in g.planet_layer_times:
		surge = maxf(surge, _bump(at, t, 0.8, SEED_SURGE_DUR))
	for at in g.moon_times:
		surge = maxf(surge, _bump(at, t, 0.8, SEED_SURGE_DUR))
	return s * (1.0 + SEED_SURGE * surge)


## Presence of the porcelain body 0..1: hidden in the dark before miku.awaken (only the seed), then
## revealed by the seed's light (REVEAL_DELAY, REVEAL_DUR).
static func body_presence(g: GenesisState, t: float) -> float:
	if g.awaken_at < 0.0:
		return 0.0
	return Motion.smooth(g.awaken_at + REVEAL_DELAY, t, REVEAL_DUR)


## Inner light 0..1 of the porcelain while it is revealed (1 while it fades in, then eases out).
static func reveal_glow(g: GenesisState, t: float) -> float:
	if g.awaken_at < 0.0:
		return 0.0
	var end := g.awaken_at + REVEAL_DELAY + REVEAL_DUR
	return minf(body_presence(g, t) * REVEAL_GLOW_LEAD, 1.0) * REVEAL_GLOW * (1.0 - Motion.smooth(end, t, REVEAL_GLOW_FALL))


## Bloom 0..1 of the seed's own light at the awakening (the light that reveals her), then it settles.
static func seed_bloom(g: GenesisState, t: float) -> float:
	return _bump(g.awaken_at, t, SEED_BLOOM_RISE, SEED_BLOOM_FALL)


## MIKU raises her head at planet.stable 0..1.
static func head_lift(g: GenesisState, t: float) -> float:
	if g.stable_at < 0.0:
		return 0.0
	return Motion.smooth(g.stable_at + HEAD_LIFT_DELAY, t, HEAD_LIFT_DUR)


## The halo's arc closes into a full circle at planet.stable 0..1.
static func halo_close(g: GenesisState, t: float) -> float:
	if g.stable_at < 0.0:
		return 0.0
	return Motion.smooth(g.stable_at + HALO_CLOSE_DELAY, t, HALO_CLOSE_DUR)


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
	var cool := Motion.smooth(g.stable_at, t, VEINS_COOL_DUR) if g.stable_at >= 0.0 else 0.0
	return clampf(lerpf(v + working, VEINS_STABLE, cool), 0.0, 1.0)


## Release of the hands after planet.stable 0..1: they withdraw slowly, palms opening (letting go).
static func hands_release(g: GenesisState, t: float) -> float:
	if g.stable_at < 0.0:
		return 0.0
	return Motion.smooth(g.stable_at + RELEASE_DELAY, t, RELEASE_DUR)


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


# --- Climax -------------------------------------------------------------------------------------------

## Climax envelope 0..1 after planet.stable: rises to 1 (the peak of light of the session), holds,
## settles to CLIMAX_REST. 0 before the event.
static func climax(g: GenesisState, t: float) -> float:
	if g.stable_at < 0.0:
		return 0.0
	var s := g.stable_at + CLIMAX_DELAY
	var up := Motion.smooth(s, t, CLIMAX_RISE)
	var down := Motion.smooth(s + CLIMAX_RISE + CLIMAX_HOLD, t, CLIMAX_FALL)
	return up * (1.0 - (1.0 - CLIMAX_REST) * down)


## Hop of link `i` in the graph: breadth-first depth of its source from MIKU (0 for MIKU's own
## threads). The stable wave crosses hop h during [h, h + 1] of stable_wave(). Called at build time.
static func link_hop(i: int) -> int:
	var depth := {&"miku": 0}
	var changed := true
	while changed:
		changed = false
		for l: Array in GenesisScript.LINKS:
			var a: StringName = l[0]
			var b: StringName = l[1]
			if depth.has(a) and (not depth.has(b) or int(depth[b]) > int(depth[a]) + 1):
				depth[b] = int(depth[a]) + 1
				changed = true
	var src: StringName = GenesisScript.LINKS[i][0]
	return int(depth.get(src, 0))


## Number of hops of the stable wave (deepest link hop + 1).
static func wave_hops() -> int:
	var n := 0
	for i in GenesisScript.LINKS.size():
		n = maxi(n, link_hop(i) + 1)
	return n


## Position of the single stable pulse in hops (0 = leaving MIKU, `hops` = arrived everywhere);
## -1 before planet.stable + WAVE_DELAY and after the wave ended.
static func stable_wave(g: GenesisState, t: float, hops: int) -> float:
	if g.stable_at < 0.0:
		return -1.0
	var x := t - (g.stable_at + WAVE_DELAY + WAVE_HAIR)
	if x < 0.0 or x > WAVE_HOP * hops:
		return -1.0
	return x / WAVE_HOP


## Position 0..1 of the stable pulse along the link strands of MIKU's hair (root -> where the
## threads begin), just before it runs along her threads; -1 outside.
static func hair_wave(g: GenesisState, t: float) -> float:
	if g.stable_at < 0.0:
		return -1.0
	var x := t - (g.stable_at + WAVE_DELAY)
	if x < 0.0 or x > WAVE_HAIR + 1e-4:
		return -1.0
	return Motion.eased(minf(x / WAVE_HAIR, 1.0), Tween.TRANS_SINE, Tween.EASE_IN)


## Pulse position 0..1 of the stable wave `wave` on a link of hop `hop`; -1 when not on it.
static func wave_on_link(wave: float, hop: int) -> float:
	if wave < 0.0:
		return -1.0
	var p := wave - float(hop)
	if p < 0.0 or p > 1.0:
		return -1.0
	return Motion.eased(p, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


# --- Light ----------------------------------------------------------------------------------------------

## Light levels of the rig at (g, t) into `out` (keys of LIGHT_AWAKE + "planet" + "planet_key" +
## "climax").
## The front lights (key, rim, fill, ambient) lead the awakening so the revealed body is lit; the
## warm backlight follows BACK_LIGHT_DELAY later. The climax adds LIGHT_CLIMAX and the world's own
## sky light (`planet` = molten glow + PLANET_LIGHT_CLIMAX × climax; `climax` = the envelope).
static func light_levels(g: GenesisState, t: float, out: Dictionary) -> Dictionary:
	var front := Motion.smooth(g.awaken_at, t, FRONT_LIGHT_DUR)
	var back := Motion.smooth(g.awaken_at + BACK_LIGHT_DELAY, t, AWAKEN_DUR) if g.awaken_at >= 0.0 else 0.0
	var c := climax(g, t)
	for k: String in LIGHT_AWAKE:
		var a := back if k == "back" else front
		out[k] = lerpf(float(LIGHT_ASLEEP[k]), float(LIGHT_AWAKE[k]), a) + float(LIGHT_CLIMAX[k]) * c
	var molten := PLANET_LIGHT * maxf(planet_heat(g, t), PLANET_LIGHT_REST * planet_crust(g, t)) * planet_formation(g, t)
	out["planet"] = molten + PLANET_LIGHT_CLIMAX * c
	out["planet_key"] = PLANET_KEY * maxf(PLANET_KEY_CRUST * planet_crust(g, t), planet_atmosphere(g, t)) + PLANET_KEY_CLIMAX * c
	out["planet_rim"] = PLANET_RIM * planet_atmosphere(g, t) + PLANET_RIM_CLIMAX * c
	out["climax"] = c
	return out


## Weighted sum of a light_levels() dictionary (tests: the climax is the peak of the session).
static func light_total(levels: Dictionary) -> float:
	var s := 0.0
	for k: String in LIGHT_WEIGHTS:
		s += float(LIGHT_WEIGHTS[k]) * float(levels.get(k, 0.0))
	return s


# --- helpers --------------------------------------------------------------------------------------------

## 0 before `at`, eases up to 1 over `rise`, then down to 0 over `fall` (smooth bump).
static func _bump(at: float, t: float, rise: float, fall: float) -> float:
	if at < 0.0 or t < at:
		return 0.0
	if t < at + rise:
		return Motion.eased((t - at) / rise)
	return 1.0 - Motion.eased((t - at - rise) / fall)
