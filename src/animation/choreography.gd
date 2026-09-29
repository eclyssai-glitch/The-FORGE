class_name Choreography
extends RefCounted
## Event -> visual mapping of the ORIGIN CHAMBER, as pure functions of (WorldState, sim time).
## Owner: animator. Entities only read these values and push them into nodes/materials, so every
## rule of timing lives here and is unit-tested (tests/unit/test_animation_choreography.gd).
## Event times are never duplicated: everything is anchored on the world's `*_at` timestamps.
## Durations are this file's constants; the table lives in docs/ANIMATION.md.

# --- Core ------------------------------------------------------------------------------------
## Energy reached during activation, before CORE_ONLINE (the rest arrives with the online event).
const CORE_WAKE_LEVEL := 0.6
const CORE_WAKE := 2.4
const CORE_ONLINE_SETTLE := 0.8
## Heartbeat while activating (Hz) and breath period once online (s).
const CORE_FLICKER_HZ := 1.3
const CORE_BREATH := 3.2
## Surge on every step the core drives (fragments, each layer, final lock).
const CORE_SURGE := 1.1
const CORE_PEAK_BASE := 2.2
const CORE_PEAK_BOOST := 1.2
const CORE_PEAK_DECAY := 2.2

# --- Fragments / structure -------------------------------------------------------------------
## Flight from the core to the scatter shell; per-fragment start offset up to EMIT_SPREAD.
const EMIT_DUR := 1.7
const EMIT_SPREAD := 0.6
## Assembly flight of one segment; segments of a layer start staggered around the ring.
const ASSEMBLE_DUR := 1.5
const ASSEMBLE_SPREAD := 1.1
const BUILD_RISE := 0.25
const BUILD_FADE := 1.6
## Construction guides (seeded axis): fade in, and fade out as each layer is built.
const GUIDE_IN := 1.2
const GUIDE_OUT := 1.4
const GUIDE_LEVEL := 0.55
const FINISH_DUR := 2.4
## Final lock: twist -> 0, ribs grow, EMBER arcs.
const LOCK_DUR := 2.6
const RIB_DELAY := 0.4
const RIB_DUR := 2.4
const RIB_FADE := 1.2
const ARC_DELAY := 0.9
const ARC_DUR := 2.2
## Level of the final EMBER arcs: discreet lines, not an EMBER outline of every edge.
const FINAL_LOCK_LEVEL := 0.7

# --- Verification ----------------------------------------------------------------------------
## Rest height of the verification ring (below the lowest layer, above the floor at -3.2).
const SCAN_PARK_Y := -2.6
const SCAN_AMPLITUDE := 2.25
## Half period of the sweep (bottom -> top) in seconds.
const SCAN_HALF_PERIOD := 2.4
const SCAN_ENTER := 0.9
const SCAN_EXIT := 1.6
## Check flash: wave that spreads from the ring's height at the check, fading in FLASH_DUR.
const FLASH_SPEED := 5.0
const FLASH_DUR := 1.1

# --- Waves (ActivationPulse) and sparks ------------------------------------------------------
const WAVE_ACTIVATION := {"dur": 2.2, "r0": 0.7, "r1": 6.0, "strength": 0.8}
const WAVE_ONLINE := {"dur": 2.0, "r0": 0.7, "r1": 3.2, "strength": 0.45}
const WAVE_FINAL := {"dur": 3.4, "r0": 3.2, "r1": 13.0, "strength": 1.0}
const FINAL_HALO_DELAY := 1.2
const FINAL_HALO_DUR := 2.6
const FINAL_HALO_LEVEL := 0.4
const SPARK_DUR := 1.2


# =============================================================================================
# Core
# =============================================================================================

## Core energy 0..1: 0 while dormant (no EMBER), rises on activation, 1 once online.
static func core_energy(w: WorldState, t: float) -> float:
	var e := CORE_WAKE_LEVEL * Motion.eased(Motion.progress(w.core_activation_at, t, CORE_WAKE),
		Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	if w.core_online_at >= 0.0:
		e = lerpf(e, 1.0, Motion.smooth(w.core_online_at, t, CORE_ONLINE_SETTLE))
	return e


## Heart pulse 0..1 from simulation time: flicker while activating, slow breath once online,
## surges on every construction step the core drives.
static func core_pulse(w: WorldState, t: float) -> float:
	if w.core_activation_at < 0.0:
		return 0.0
	var base: float
	if w.core_online_at < 0.0:
		base = 0.5 + 0.5 * sin(TAU * CORE_FLICKER_HZ * (t - w.core_activation_at))
	else:
		base = 0.35 + 0.35 * sin(TAU * (t - w.core_online_at) / CORE_BREATH)
	var surge := maxf(Motion.decay(w.core_online_at, t, CORE_SURGE), Motion.decay(w.fragments_at, t, CORE_SURGE))
	for at in w.layer_times:
		surge = maxf(surge, Motion.decay(at, t, CORE_SURGE))
	surge = maxf(surge, Motion.decay(w.finalized_at, t, CORE_SURGE * 1.6))
	return clampf(maxf(base, surge), 0.0, 1.0)


## `peak` of the heart shader: base, with a boost when the structure locks.
static func core_peak(w: WorldState, t: float) -> float:
	return CORE_PEAK_BASE + CORE_PEAK_BOOST * Motion.decay(w.finalized_at, t, CORE_PEAK_DECAY)


# =============================================================================================
# Light stages (EnvironmentProfile.LIGHT), mapping in docs/VISUAL_DIRECTION.md
# =============================================================================================

## Name of the last stage reached at the current world.
static func light_stage(w: WorldState) -> String:
	if w.finalized_at >= 0.0:
		return "final"
	if w.verification_at >= 0.0:
		return "verify"
	if w.lighting_at >= 0.0:
		return "lit"
	if w.core_activation_at >= 0.0:
		return "active"
	return "dormant"


## Writes the blended light levels (keys of EnvironmentProfile.LIGHT entries) into `out` and
## returns it. Each stage blends from the previous level over Palette.T_CINEMATIC, so the
## result is continuous in time and identical after a seek.
static func light_levels(w: WorldState, t: float, out: Dictionary) -> Dictionary:
	var levels: Dictionary = EnvironmentProfile.LIGHT
	var base: Dictionary = levels["dormant"]
	for k: String in base:
		out[k] = float(base[k])
	_blend_stage(out, levels["active"], Motion.smooth(w.core_activation_at, t, Palette.T_CINEMATIC))
	_blend_stage(out, levels["lit"], Motion.smooth(w.lighting_at, t, Palette.T_CINEMATIC))
	_blend_stage(out, levels["verify"], Motion.smooth(w.verification_at, t, Palette.T_CINEMATIC))
	_blend_stage(out, levels["final"], Motion.smooth(w.finalized_at, t, Palette.T_CINEMATIC))
	return out


static func _blend_stage(out: Dictionary, stage: Dictionary, p: float) -> void:
	if p <= 0.0:
		return
	for k: String in stage:
		out[k] = lerpf(float(out[k]), float(stage[k]), p)


# =============================================================================================
# Fragments and structure
# =============================================================================================

## Flight progress 0..1 of fragment i from the core to its scatter pose (0 before emission).
static func emission(i: int, w: WorldState, t: float) -> float:
	if w.fragments_at < 0.0:
		return 0.0
	return Motion.out(w.fragments_at + EMIT_SPREAD * Motion.hash01(i), t, EMIT_DUR)


## Start time of segment k (of n) of a layer added at `layer_at` (staggered around the ring).
static func assembly_start(k: int, n: int, layer_at: float) -> float:
	return layer_at + ASSEMBLE_SPREAD * float(k) / float(maxi(n, 1))


## Assembly progress 0..1 of segment k of n in a layer added at `layer_at` (-1 = not yet).
static func assembly(k: int, n: int, layer_at: float, t: float) -> float:
	if layer_at < 0.0:
		return 0.0
	return Motion.smooth(assembly_start(k, n, layer_at), t, ASSEMBLE_DUR)


## Time at which the whole layer is seated (every segment at assembly 1), or -1.
static func layer_seated_at(layer_at: float) -> float:
	return -1.0 if layer_at < 0.0 else layer_at + ASSEMBLE_SPREAD + ASSEMBLE_DUR


## EMBER build energy 0..1 on a segment: rises when its flight starts, holds while it flies,
## fades after it seats.
static func build_energy(k: int, n: int, layer_at: float, t: float) -> float:
	if layer_at < 0.0:
		return 0.0
	var start := assembly_start(k, n, layer_at)
	return Motion.window(start, t, BUILD_RISE, start + ASSEMBLE_DUR, BUILD_FADE)


## Strength of the construction guide of a layer (BONE hairline at the layer's radius):
## appears when the axis is seeded, fades once the layer is being built.
static func guide_strength(w: WorldState, layer: int, t: float) -> float:
	if w.seeded_at < 0.0:
		return 0.0
	var s := GUIDE_LEVEL * Motion.smooth(w.seeded_at, t, GUIDE_IN)
	if layer < w.layer_times.size():
		s *= 1.0 - Motion.smooth(w.layer_times[layer], t, GUIDE_OUT)
	return s


## Surface finish 0 (raw) -> 1 (finished metal) after MATERIALS_APPLIED.
static func finish(w: WorldState, t: float) -> float:
	return Motion.smooth(w.materials_at, t, FINISH_DUR)


## Assembly twist amount: 1 (twisted assembly pose) until the final lock turns it to 0.
static func twist_amount(w: WorldState, t: float) -> float:
	return 1.0 - Motion.eased(Motion.progress(w.finalized_at, t, LOCK_DUR), Tween.TRANS_QUART, Tween.EASE_IN_OUT)


## Final-form EMBER arcs (structure `final_lock`), after the rings lock.
static func final_lock(w: WorldState, t: float) -> float:
	if w.finalized_at < 0.0:
		return 0.0
	return FINAL_LOCK_LEVEL * Motion.smooth(w.finalized_at + ARC_DELAY, t, ARC_DUR)


## Vertical growth 0..1 of the ribs from the equator, after the lock starts.
static func rib_growth(w: WorldState, t: float) -> float:
	if w.finalized_at < 0.0:
		return 0.0
	return Motion.out(w.finalized_at + RIB_DELAY, t, RIB_DUR)


## EMBER build energy on the ribs while they grow (fades once grown).
static func rib_energy(w: WorldState, t: float) -> float:
	if w.finalized_at < 0.0:
		return 0.0
	var start := w.finalized_at + RIB_DELAY
	return Motion.window(start, t, BUILD_RISE, start + RIB_DUR * 0.6, RIB_FADE)


# =============================================================================================
# Verification
# =============================================================================================

## Strength 0..1 of the PALE sweep (ring + band on the structure).
static func scan_strength(w: WorldState, t: float) -> float:
	if w.verification_at < 0.0:
		return 0.0
	var s := Motion.smooth(w.verification_at, t, SCAN_ENTER)
	return s * (1.0 - Motion.smooth(w.verified_at, t, SCAN_EXIT))


## World Y of the verification ring: parked below the structure, sweeping bottom <-> top while
## verifying (starting at the bottom), back to park after VERIFICATION_PASSED.
static func scan_y(w: WorldState, t: float) -> float:
	if w.verification_at < 0.0:
		return SCAN_PARK_Y
	var sweep := -SCAN_AMPLITUDE * cos(PI * (t - w.verification_at) / SCAN_HALF_PERIOD)
	var y := lerpf(SCAN_PARK_Y, sweep, Motion.smooth(w.verification_at, t, SCAN_ENTER))
	return lerpf(y, SCAN_PARK_Y, Motion.smooth(w.verified_at, t, SCAN_EXIT))


## PALE flash 0..1 at height `y`: every passed check sends a wave from the ring's height at
## that moment; it reaches `y` after |dy| / FLASH_SPEED and fades over FLASH_DUR.
static func check_flash(w: WorldState, t: float, y: float) -> float:
	var f := 0.0
	for c in w.checks:
		var at := float(c["at"])
		var delay := absf(y - scan_y(w, at)) / FLASH_SPEED
		f = maxf(f, Motion.decay(at + delay, t, FLASH_DUR))
	return f


# =============================================================================================
# Waves and sparks
# =============================================================================================

## Current energy wave: {"radius", "strength"} of the most recent wave still running
## (activation, core online, final lock). strength 0 when none is running.
static func wave(w: WorldState, t: float, out: Dictionary) -> Dictionary:
	out["radius"] = 0.0
	out["strength"] = 0.0
	_wave(out, w.core_activation_at, t, WAVE_ACTIVATION)
	_wave(out, w.core_online_at, t, WAVE_ONLINE)
	_wave(out, w.finalized_at, t, WAVE_FINAL)
	return out


static func _wave(out: Dictionary, at: float, t: float, spec: Dictionary) -> void:
	if at < 0.0 or t < at:
		return
	var p := Motion.progress(at, t, float(spec["dur"]))
	if p >= 1.0:
		return
	var grow := Motion.eased(p, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	out["radius"] = lerpf(float(spec["r0"]), float(spec["r1"]), grow)
	out["strength"] = float(spec["strength"]) * pow(1.0 - p, 1.5) * Motion.eased(minf(p * 8.0, 1.0))


## Steady EMBER halo of the final form (0 before the lock).
static func final_halo(w: WorldState, t: float) -> float:
	if w.finalized_at < 0.0:
		return 0.0
	return FINAL_HALO_LEVEL * Motion.smooth(w.finalized_at + FINAL_HALO_DELAY, t, FINAL_HALO_DUR)


## Progress 0..1 of the emission spark burst; 0 before FRAGMENTS_EMITTED, 1 when finished.
static func sparks(w: WorldState, t: float) -> float:
	return Motion.progress(w.fragments_at, t, SPARK_DUR)
