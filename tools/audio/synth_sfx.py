"""GENESIS one-shots (SFX + UI). Key: A lydian / A major pentatonic, same world as the ambience.

Each sound is a function returning a dry-then-reverberated stereo buffer; `finish()` trims the
natural tail, normalises the level (short-term max LUFS for SFX, true peak for UI) and keeps the
true peak at or below the ceiling. Every random choice uses a per-sound fixed seed.

Usage: synth_sfx.py OUT_DIR [name ...]
"""
from __future__ import annotations

import sys

import numpy as np

import dsp
from dsp import SR, note

CEILING_DBTP = -1.5
MAX_SFX_SECONDS = 8.0  # tails are trimmed where they fall ~54 dB under the peak, capped here


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(sum((i + 1) * ord(c) for i, c in enumerate(name)) + 4051)


def mono_to(x: np.ndarray, p: float = 0.0) -> np.ndarray:
    return dsp.pan(x, p)


def pad_to(x: np.ndarray, dur: float) -> np.ndarray:
    n = int(dur * SR)
    if x.shape[0] >= n:
        return x[:n]
    pad = np.zeros((n - x.shape[0],) + x.shape[1:])
    return np.concatenate([x, pad])


def swell_env(n: int, attack: float, hold: float, release: float) -> np.ndarray:
    return dsp.env_swell(n, attack, hold, release)


# ------------------------------------------------------------------ SFX

def miku_awaken(rng):
    """A chord that blooms: soft bells rising through A lydian over an opening 'oo'->'ah' choir."""
    dur = 8.0
    n = int(dur * SR)
    out = np.zeros((n, 2))
    arp = [("A3", 0.00), ("E4", 0.20), ("B4", 0.40), ("C#5", 0.58), ("G#5", 0.78),
           ("D#6", 0.96), ("E6", 1.16)]
    for i, (nm, t) in enumerate(arp):
        b = dsp.bell(note(nm), dur - t, decay=2.6 - 0.2 * i, rng=rng, brightness=0.55,
                     attack=0.012)
        dsp.add_at(out, dsp.pan(b * (0.9 - 0.06 * i), -0.5 + i / 6.0), t)
    morph = np.clip(dsp.seconds(n) / 2.2, 0, 1)
    ch = dsp.choir([note(x) for x in ["A3", "E4", "B4", "C#5"]], n, rng, "oo", "ah", morph,
                   voices=3, detune_cents=3.0)
    ch *= swell_env(n, 1.7, 1.4, 2.6)[:, None]
    warm = dsp.partial_bank([note("A2"), note("E3")], [1.0, 0.5], n, rng)
    warm = mono_to(warm * swell_env(n, 1.2, 1.5, 2.8))
    dry = 0.55 * out / np.max(np.abs(out)) + 0.9 * ch / np.max(np.abs(ch)) + 0.25 * warm
    ir = dsp.reverb_ir(5.0, 6.0, seed=11, predelay=0.03)
    return dsp.wet_dry(dry, ir, 0.45, 4.0)


def hands_summon(rng):
    """Deep, heavy, reverent: sub swell on A1/E1, stone-grain rumble, low 'oo' breath. No hit."""
    dur = 6.5
    n = int(dur * SR)
    t = dsp.seconds(n)
    env = swell_env(n, 1.9, 1.3, 3.0)
    sub = np.sin(2 * np.pi * note("A1") * t) + 0.6 * np.sin(2 * np.pi * note("E1") * t + 1.0)
    sub = dsp.soft_saturate(0.8 * sub, 1.8) * env  # a little harmonic weight for small speakers
    rumble = dsp.butter(rng.standard_normal((n, 2)), "lowpass", 150.0, 4)
    rumble = dsp.butter(rumble, "highpass", 28.0, 2)
    slow = dsp.butter(rng.standard_normal(n), "lowpass", 1.2, 2)
    slow = 0.6 + 0.4 * slow / (np.max(np.abs(slow)) + 1e-9)
    rumble *= (swell_env(n, 2.3, 1.0, 2.8) * slow)[:, None]
    # stone: sparse soft grinding grains (low band-passed noise, 20-70 ms)
    stone = np.zeros((n, 2))
    tt = 0.5
    while tt < 4.6:
        g_len = rng.uniform(0.02, 0.07)
        m = int(g_len * SR)
        g = rng.standard_normal(m) * dsp.env_attack_decay(m, 0.004, g_len / 3)
        dsp.add_at(stone, dsp.pan(g * rng.uniform(0.3, 1.0), rng.uniform(-0.6, 0.6)), tt)
        tt += rng.exponential(0.09)
    stone = dsp.butter(stone, "bandpass", [140.0, 700.0], 2)
    stone *= swell_env(n, 2.0, 1.0, 2.2)[:, None]
    breath = dsp.choir([note("A2"), note("E3")], n, rng, "oo", "oo", None, voices=3)
    breath *= swell_env(n, 2.4, 1.2, 2.6)[:, None]

    def nrm(x):
        return x / (np.max(np.abs(x)) + 1e-12)

    dry = (0.8 * mono_to(nrm(sub)) + 0.55 * nrm(rumble) + 0.22 * nrm(stone)
           + 0.28 * nrm(breath))
    ir = dsp.reverb_ir(4.5, 5.0, seed=12, predelay=0.04, rt_high=1.4)
    return dsp.wet_dry(dry, ir, 0.3, 3.0)


def dust_gather(rng):
    """Bright particles converging: a granular swell that rises in pitch and density and
    narrows to the centre, resolving on a soft glint."""
    dur = 5.0
    n = int(dur * SR)
    pool = ["A5", "B5", "C#6", "E6", "F#6", "A6", "B6", "C#7", "E7"]
    grains = np.zeros((n, 2))
    span = 3.6
    for i in range(170):
        u = rng.uniform(0.0, 1.0) ** 0.6          # denser towards the end
        t0 = u * span
        idx = int(np.clip(u * (len(pool) - 1) + rng.normal(0, 1.0), 0, len(pool) - 1))
        g = dsp.bell(note(pool[idx]), 0.5, decay=rng.uniform(0.07, 0.18), rng=rng,
                     brightness=0.35, attack=0.004)
        width = 0.95 * (1.0 - u) + 0.08
        dsp.add_at(grains, dsp.pan(g * rng.uniform(0.2, 0.7) * (0.35 + 0.65 * u),
                                   rng.uniform(-width, width)), t0)
    t = dsp.seconds(n)
    shimmer = np.zeros((n, 2))
    for center, t_peak in [(1800.0, 2.2), (3500.0, 3.0), (6500.0, 3.6)]:
        band = dsp.spectral_shape(n, dsp.band_shape(center, 0.35), rng)
        e = np.exp(-0.5 * ((t - t_peak) / 0.7) ** 2)
        shimmer += band * e[:, None]
    shimmer *= np.clip(t / span, 0, 1)[:, None] ** 1.5
    glint = np.zeros((n, 2))
    for nm, dt, p in [("A6", 0.0, -0.1), ("E7", 0.09, 0.12)]:
        b = dsp.bell(note(nm), 1.4, decay=0.6, rng=rng, brightness=0.5, attack=0.006)
        dsp.add_at(glint, dsp.pan(b, p), span + dt)
    dry = (0.8 * grains / np.max(np.abs(grains)) + 0.18 * shimmer / np.max(np.abs(shimmer))
           + 0.45 * glint / np.max(np.abs(glint)))
    ir = dsp.reverb_ir(3.8, 4.5, seed=13, predelay=0.02)
    return dsp.wet_dry(dry, ir, 0.4, 3.0)


def planet_seed(rng):
    """A low crystalline bell (A2) with a warm A1/A2 body: the seed of the planet."""
    dur = 7.5
    n = int(dur * SR)
    b = dsp.bell(note("A2"), dur, decay=2.4, rng=rng, brightness=0.8, attack=0.008)
    b2 = dsp.bell(note("E4"), dur, decay=1.6, rng=rng, brightness=0.55, attack=0.01)
    b3 = dsp.bell(note("A4"), dur, decay=1.3, rng=rng, brightness=0.5, attack=0.01)
    t = dsp.seconds(n)
    body = np.sin(2 * np.pi * note("A1") * t) + 0.7 * np.sin(2 * np.pi * note("A2") * t + 0.4)
    body = dsp.soft_saturate(0.7 * body, 1.5) * swell_env(n, 0.5, 0.8, 3.2)
    dry = (mono_to(0.7 * b / np.max(np.abs(b))) + dsp.pan(0.22 * b2 / np.max(np.abs(b2)), -0.3)
           + dsp.pan(0.16 * b3 / np.max(np.abs(b3)), 0.3) + mono_to(0.45 * body))
    ir = dsp.reverb_ir(5.0, 6.0, seed=14, predelay=0.035)
    return dsp.wet_dry(dry, ir, 0.35, 3.5)


def accretion_0(rng):
    """Magma layer: warm, low, glowing — a filtered A1 harmonic stack blooming open and closing,
    over a slow molten murmur."""
    dur = 6.0
    n = int(dur * SR)
    t = dsp.seconds(n)
    fc = 160.0 + 650.0 * np.exp(-0.5 * ((t - 2.2) / 1.0) ** 2)
    out = np.zeros(n)
    for f0, a0 in [(note("A1"), 1.0), (note("E2"), 0.5)]:
        for k in range(1, 40):
            fk = k * f0
            if fk > 4000:
                break
            amp = a0 / k / np.sqrt(1 + (fk / fc) ** 4)
            out += amp * np.sin(2 * np.pi * fk * t * (1 + 0.0007 * np.sin(2 * np.pi * 0.3 * t))
                                + rng.uniform(0, 2 * np.pi))
    out *= swell_env(n, 1.2, 1.6, 2.6)
    stereo = dsp.pan(out, -0.12) + dsp.pan(np.roll(out, int(0.011 * SR)), 0.12)
    murmur = dsp.butter(rng.standard_normal((n, 2)), "bandpass", [60.0, 260.0], 2)
    wob = dsp.butter(rng.standard_normal(n), "lowpass", 3.0, 2)
    wob = np.clip(0.5 + 0.5 * wob / (np.max(np.abs(wob)) + 1e-9), 0, 1)
    murmur *= (wob * swell_env(n, 1.4, 1.4, 2.4))[:, None]
    dry = stereo / np.max(np.abs(stereo)) + 0.3 * murmur / np.max(np.abs(murmur))
    ir = dsp.reverb_ir(4.0, 5.0, seed=15, predelay=0.03, rt_high=1.2)
    return dsp.wet_dry(dry, ir, 0.3, 2.5)


def accretion_1(rng):
    """Crust layer: a soft rocky texture — gravel-like grains settling over an 'oh' fifth."""
    dur = 5.0
    n = int(dur * SR)
    grains = np.zeros((n, 2))
    density_env = swell_env(n, 1.1, 0.9, 2.2)
    tt = 0.05
    while tt < 4.2:
        m = int(rng.uniform(0.012, 0.05) * SR)
        g = rng.standard_normal(m) * dsp.env_attack_decay(m, 0.007, m / SR / 4)
        center = rng.uniform(500.0, 2200.0)
        lo, hi = center / 1.5, min(center * 1.5, 20000.0)
        g = dsp.butter(np.stack([g, g], -1), "bandpass", [lo, hi], 1)[:, 0]
        amp = density_env[min(int(tt * SR), n - 1)]
        dsp.add_at(grains, dsp.pan(g * amp * rng.uniform(0.2, 1.0), rng.uniform(-0.55, 0.55)), tt)
        tt += rng.exponential(0.012 + 0.08 * (1.0 - amp))
    grains = dsp.butter(grains, "lowpass", 3000.0, 4)
    tone = dsp.choir([note("E3"), note("B3")], n, rng, "oh", "oh", None, voices=3)
    tone *= swell_env(n, 1.3, 1.2, 2.4)[:, None]
    dry = 0.8 * grains / np.max(np.abs(grains)) + 0.5 * tone / np.max(np.abs(tone))
    ir = dsp.reverb_ir(2.8, 3.5, seed=16, predelay=0.02)
    return dsp.wet_dry(dry, ir, 0.3, 2.2)


def accretion_2(rng):
    """Atmosphere layer: an airy formant pad (C#4 E4 A4 + D#5 halo) with a breath of high air."""
    dur = 6.5
    n = int(dur * SR)
    morph = np.clip(dsp.seconds(n) / 3.5, 0, 1)
    pad = dsp.choir([note(x) for x in ["C#4", "E4", "A4"]], n, rng, "oh", "ah", morph, voices=3,
                    spread=0.85)
    halo = dsp.choir([note("D#5")], n, rng, "oo", "oo", None, voices=3, spread=0.9)
    env = swell_env(n, 2.0, 1.6, 2.7)
    pad *= env[:, None]
    halo *= swell_env(n, 2.6, 1.0, 2.6)[:, None]
    air = dsp.spectral_shape(n, dsp.band_shape(6500.0, 0.5), rng)
    air *= (env ** 1.5)[:, None]
    dry = (pad / np.max(np.abs(pad)) + 0.25 * halo / np.max(np.abs(halo))
           + 0.08 * air / np.max(np.abs(air)))
    ir = dsp.reverb_ir(6.0, 7.0, seed=17, predelay=0.04)
    return dsp.wet_dry(dry, ir, 0.5, 3.0)


def moon_form(rng):
    """Documentation moon: a small tuned celesta figure, E6 -> B6, high and clear."""
    dur = 3.2
    n = int(dur * SR)
    out = np.zeros((n, 2))
    for nm, t, p, a in [("E6", 0.0, -0.15, 1.0), ("B6", 0.16, 0.18, 0.7), ("E5", 0.0, 0.0, 0.35)]:
        c = dsp.celesta(note(nm), dur - t, decay=1.3, rng=rng)
        dsp.add_at(out, dsp.pan(c * a, p), t)
    ir = dsp.reverb_ir(4.0, 4.5, seed=18, predelay=0.03)
    return dsp.wet_dry(out, ir, 0.45, 3.0)


def ring_form(rng):
    """Skill ring: a harmonic glissando — a resonance climbs the overtones of A2 while each
    overtone circles around the listener."""
    dur = 6.0
    n = int(dur * SR)
    t = dsp.seconds(n)
    f0 = note("A2")
    u = np.clip((t - 0.3) / 3.6, 0, 1)
    u = 0.5 - 0.5 * np.cos(np.pi * u)
    center = np.log2(3.0) + u * (np.log2(20.0) - np.log2(3.0))
    out = np.zeros((n, 2))
    for k in range(1, 25):
        g = np.exp(-0.5 * ((np.log2(k) - center) / 0.16) ** 2) + (0.12 if k == 1 else 0.0)
        s = np.sin(2 * np.pi * k * f0 * t + rng.uniform(0, 2 * np.pi)) * g / np.sqrt(k) * 1.6
        ang = 2 * np.pi * t / 2.4 + k * 0.7
        out += dsp.pan(s, 0.75 * np.sin(ang))
    out *= swell_env(n, 0.8, 3.0, 2.0)[:, None]
    ir = dsp.reverb_ir(5.0, 6.0, seed=19, predelay=0.03)
    return dsp.wet_dry(out, ir, 0.45, 3.0)


def belt_form(rng):
    """Memory belt: scattered, distant tinkling — many tiny grains spread across the image."""
    dur = 6.0
    n = int(dur * SR)
    pool = ["E6", "F#6", "A6", "B6", "C#7", "E7", "F#7", "A7"]
    out = np.zeros((n, 2))
    for i in range(110):
        t0 = np.clip(rng.normal(2.2, 1.1), 0.05, 4.8)
        g = dsp.bell(note(pool[rng.integers(len(pool))]), 0.6, decay=rng.uniform(0.05, 0.22),
                     rng=rng, brightness=0.3, attack=0.003)
        far = rng.uniform(0.0, 1.0)
        if far > 0.5:  # distant grains: softer and duller
            g = dsp.butter(np.stack([g, g], -1), "lowpass", 5000.0, 1)[:, 0] * 0.5
        dsp.add_at(out, dsp.pan(g * rng.uniform(0.2, 0.8), rng.uniform(-1.0, 1.0)), t0)
    out = dsp.fade_in(out, 0.4)
    ir = dsp.reverb_ir(4.2, 5.0, seed=20, predelay=0.03)
    return dsp.wet_dry(out, ir, 0.5, 3.0)


def links_woven(rng):
    """Relational threads: a pentatonic harp arpeggio weaving from left to right."""
    dur = 5.5
    n = int(dur * SR)
    seq = ["A3", "C#4", "E4", "F#4", "A4", "B4", "C#5", "E5", "F#5", "A5"]
    out = np.zeros((n, 2))
    for i, nm in enumerate(seq):
        t0 = i * 0.115 + rng.uniform(-0.012, 0.012)
        pl = dsp.pluck(note(nm), dur - t0, rng, damping=0.9975, brightness=0.42)
        pl *= 0.85 + 0.15 * np.cos(i)
        dsp.add_at(out, dsp.pan(pl, -0.7 + 1.4 * i / (len(seq) - 1)), max(t0, 0.0))
    out = dsp.butter(out, "highpass", 90.0, 2)
    ir = dsp.reverb_ir(4.5, 5.0, seed=21, predelay=0.03)
    return dsp.wet_dry(out, ir, 0.4, 2.5)


def planet_stable(rng):
    """Resolution: a wide Aadd9 chord — choir, bells and a warm root — breathing out slowly."""
    dur = 9.5
    n = int(dur * SR)
    ch = dsp.choir([note(x) for x in ["A2", "E3", "A3", "C#4", "E4", "B4"]], n, rng, "oh", "ah",
                   np.clip(dsp.seconds(n) / 3.0, 0, 1), voices=3, detune_cents=3.0, spread=0.9)
    ch *= swell_env(n, 1.6, 2.8, 3.4)[:, None]
    bells = np.zeros((n, 2))
    for i, (nm, t0) in enumerate([("A3", 0.0), ("E4", 0.14), ("C#5", 0.3), ("A5", 0.48),
                                  ("B5", 0.7)]):
        b = dsp.bell(note(nm), dur - t0, decay=3.0 - 0.3 * i, rng=rng, brightness=0.5,
                     attack=0.015)
        dsp.add_at(bells, dsp.pan(b, -0.4 + 0.2 * i), t0)
    t = dsp.seconds(n)
    root = np.sin(2 * np.pi * note("A1") * t) + 0.5 * np.sin(2 * np.pi * note("E2") * t)
    root *= swell_env(n, 1.4, 2.8, 3.4)
    dry = (ch / np.max(np.abs(ch)) + 0.45 * bells / np.max(np.abs(bells))
           + mono_to(0.35 * root / np.max(np.abs(root))))
    ir = dsp.reverb_ir(6.0, 7.0, seed=22, predelay=0.04)
    return dsp.wet_dry(dry, ir, 0.45, 4.0)


# ------------------------------------------------------------------ UI (nearly inaudible)

def ui_tick(rng):
    """A tiny glass tap on wood: E7 glass partials over a soft 1.1 kHz wooden body."""
    n = int(0.35 * SR)
    glass = dsp.partial_bank([note("E7"), note("E7") * 2.76], [1.0, 0.25], n, rng,
                             decays=[0.035, 0.015], attack=0.0015)
    wood = rng.standard_normal(n) * dsp.env_attack_decay(n, 0.001, 0.006)
    wood = dsp.butter(np.stack([wood, wood], -1), "bandpass", [700.0, 1700.0], 2)[:, 0]
    x = mono_to(0.6 * glass + 0.4 * wood / (np.max(np.abs(wood)) + 1e-9))
    ir = dsp.reverb_ir(0.8, 1.0, seed=23, predelay=0.005)
    return dsp.wet_dry(x, ir, 0.2, 0.3)


def ui_select(rng):
    """Two soft glass taps, A6 then E7 (a rising fifth)."""
    n = int(0.8 * SR)
    out = np.zeros((n, 2))
    for nm, t0, p in [("A6", 0.0, -0.08), ("E7", 0.07, 0.08)]:
        g = dsp.partial_bank([note(nm), note(nm) * 2.76], [1.0, 0.2], n, rng,
                             decays=[0.12, 0.03], attack=0.002)
        dsp.add_at(out, dsp.pan(g, p), t0)
    ir = dsp.reverb_ir(1.2, 1.4, seed=24, predelay=0.008)
    return dsp.wet_dry(out, ir, 0.25, 0.5)


# name -> (builder, level mode, target)
#   ("st", L): max short-term loudness L LUFS   ("tp", P): true peak P dBTP (UI)
SOUNDS = {
    "sfx_miku_awaken": (miku_awaken, "st", -16.5),
    "sfx_hands_summon": (hands_summon, "st", -16.5),
    "sfx_dust_gather": (dust_gather, "st", -17.5),
    "sfx_planet_seed": (planet_seed, "st", -17.0),
    "sfx_accretion_0": (accretion_0, "st", -17.0),
    "sfx_accretion_1": (accretion_1, "st", -18.0),
    "sfx_accretion_2": (accretion_2, "st", -17.5),
    "sfx_moon_form": (moon_form, "st", -18.0),
    "sfx_ring_form": (ring_form, "st", -17.5),
    "sfx_belt_form": (belt_form, "st", -18.0),
    "sfx_links_woven": (links_woven, "st", -17.5),
    "sfx_planet_stable": (planet_stable, "st", -16.0),
    "ui_tick": (ui_tick, "tp", -24.0),
    "ui_select": (ui_select, "tp", -21.0),
}


def render(name: str) -> np.ndarray:
    fn, mode, target = SOUNDS[name]
    x = fn(rng_for(name))
    x = dsp.butter(x, "highpass", 25.0, 2)  # DC / infrasonic guard
    x = x / (np.max(np.abs(x)) + 1e-12)       # trim floor is relative to the peak
    if mode == "st":
        x = dsp.trim_tail(x, floor_db=-54.0, fade=0.8)
        x = dsp.fade_out(x[: int(MAX_SFX_SECONDS * SR)], 0.8)
    else:
        x = dsp.trim_tail(x, floor_db=-50.0, fade=0.05)
    if mode == "st":
        return dsp.normalize_short_term(x, target, CEILING_DBTP)
    return dsp.normalize_peak(x, target)


def main(out_dir: str, names: list[str]) -> None:
    for name in names or list(SOUNDS):
        x = render(name)
        dsp.write_wav(f"{out_dir}/{name}.wav", x)
        print(f"{name}: {x.shape[0] / SR:.2f}s  S_max={dsp.short_term_max_lufs(x):.1f} LUFS  "
              f"M_max={dsp.momentary_max_lufs(x):.1f}  TP={dsp.true_peak_db(x):.1f} dBTP")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
