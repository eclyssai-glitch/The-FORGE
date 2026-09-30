"""amb_cosmos_loop — the cosmic bed of GENESIS (A lydian / A pentatonic, drone on A1 = 55 Hz).

Seamless by construction, not by crossfade: every component is exactly periodic over the loop
length T. Oscillator frequencies, beat offsets and LFO rates are quantised to multiples of 1/T;
the wind is noise synthesised in the frequency domain over T samples; sparkle grains wrap around
the end; the reverb is a circular convolution over T. The last sample flows into the first.

Layers: drone (A1 + E2 with slow beating partners), formant pad ("ah" <-> "oh", Aadd9 <-> Amaj7#11),
cosmic wind (three moving noise bands), sparse crystalline sparkle (pentatonic bell grains),
long diffuse reverb (synthetic IR, RT60 ~7 s).

The loop is written as two complementary stems split by a linear-phase circular crossover
(FLOOR below ~230 Hz, AIR above; floor + air == the full loop, both still exactly periodic).
The game plays them locked together (AudioStreamSynchronized) and recesses only the floor under
the big low-register moments (docs/AUDIO.md, "recuo do grave").
"""
from __future__ import annotations

import sys

import numpy as np

import dsp
from dsp import SR, note

T = 72.0            # loop length (s)
N = int(T * SR)
SEED = 0x6E3515     # fixed: same command -> same WAV


def q(f: float) -> float:
    """Quantise a frequency to the loop grid (integer cycles per loop)."""
    return round(f * T) / T


def lfo(rate_cycles: int, phase: float = 0.0) -> np.ndarray:
    """Sine LFO with an integer number of cycles per loop, in [0, 1]."""
    t = dsp.seconds(N)
    return 0.5 + 0.5 * np.sin(2 * np.pi * rate_cycles * t / T + phase)


def drone(rng: np.random.Generator) -> np.ndarray:
    t = dsp.seconds(N)
    out = np.zeros((N, 2))
    # (freq, amp, beat offset Hz as k/T, pan)
    for f, a, beat_k, p in [(note("A1"), 1.0, 9, -0.15), (note("E2"), 0.55, 6, 0.2),
                            (note("A2"), 0.32, 5, 0.05)]:
        f = q(f)
        for fb, pp in [(f, p), (f + beat_k / T, -p)]:
            y = np.zeros(N)
            # harmonic weight in 110-220 Hz (A2 E3 A3): the floor still reads on small speakers
            for k, ak in [(1, 0.8), (2, 0.62), (3, 0.36), (4, 0.2)]:
                y += ak * np.sin(2 * np.pi * k * fb * t + rng.uniform(0, 2 * np.pi))
            out += dsp.pan(a * y, pp)
    breath = 0.72 + 0.28 * lfo(3, 1.3)   # 24 s breathing
    return out * breath[:, None]


def pad(rng: np.random.Generator) -> np.ndarray:
    t_rel = dsp.seconds(N)
    # chord weights: Aadd9 at 0 s, Amaj7#11 (lydian colour) at 18 s, back at 36 s, again at 54 s
    w2 = 0.5 - 0.5 * np.cos(2 * np.pi * 2 * t_rel / T)
    w1 = 1.0 - w2
    morph = 0.65 * lfo(1, -np.pi / 2)     # "oh", opening towards "ah" mid-loop, closing again
    chord1 = ["A2", "E3", "B3", "C#4"]
    chord2 = ["A2", "E3", "G#3", "D#4"]
    out = np.zeros((N, 2))
    for names, w in [(chord1, w1), (chord2, w2)]:
        layer = np.zeros((N, 2))
        for i, nm in enumerate(names):
            for v in range(3):
                cents = (v - 1) * 2.5
                f = q(note(nm) * 2 ** (cents / 1200.0))
                vib_rate = (9 + 4 * v + i) / T   # integer cycles per loop
                y = dsp.choir_voice(f, N, rng, "oh", "ah", morph, vib_rate=vib_rate,
                                    vib_depth=0.0015, fmax=4200.0)
                layer += dsp.pan(y * (1.0 - 0.2 * v), (v - 1) * 0.6 + (i - 1.5) * 0.08)
        out += layer * w[:, None]
    # gentle top-end roll-off (airy, never bright) — circular via FFT keeps it periodic
    spec = np.fft.rfft(out, axis=0)
    f = np.fft.rfftfreq(N, 1 / SR)
    spec *= (1.0 / np.sqrt(1 + (f / 2600.0) ** 4))[:, None]
    out = np.fft.irfft(spec, N, axis=0)
    swell = 0.6 + 0.4 * lfo(2, 0.4)
    return out * swell[:, None]


def wind(rng: np.random.Generator) -> np.ndarray:
    out = np.zeros((N, 2))
    for center, width, cycles, ph, g in [(260.0, 0.6, 2, 0.0, 1.0), (620.0, 0.5, 3, 2.1, 0.7),
                                         (1500.0, 0.45, 5, 4.0, 0.35), (4200.0, 0.4, 4, 1.0, 0.22),
                                         (8500.0, 0.35, 3, 5.2, 0.07)]:
        band = dsp.spectral_shape(N, dsp.band_shape(center, width), rng)
        mov = lfo(cycles, ph) ** 2
        # slow stereo drift of each band
        drift = np.sin(2 * np.pi * (cycles + 1) * dsp.seconds(N) / T + ph) * 0.35
        left = band[:, 0] * mov * np.cos((drift + 1) * np.pi / 4)
        right = band[:, 1] * mov * np.sin((drift + 1) * np.pi / 4)
        out += g * np.stack([left, right], axis=-1)
    return out


def sparkle(rng: np.random.Generator) -> np.ndarray:
    out = np.zeros((N, 2))
    pool = ["A5", "B5", "C#6", "E6", "F#6", "A6", "B6", "E7"]
    t = 0.7
    while t < T:
        nm = pool[rng.integers(len(pool))]
        dur = rng.uniform(1.2, 2.6)
        g = dsp.bell(note(nm), dur, decay=rng.uniform(0.35, 0.8), rng=rng,
                     brightness=0.55, attack=0.012)
        g = dsp.fade_out(g, 0.3) * rng.uniform(0.35, 1.0)
        dsp.add_at(out, dsp.pan(g, rng.uniform(-0.85, 0.85)), t, wrap=True)
        # sparse: small clusters of 1-3 glints, then long silences
        t += rng.choice([0.18, 0.31, 2.4, 3.6, 5.2], p=[0.2, 0.15, 0.25, 0.25, 0.15])
    return out


def build() -> np.ndarray:
    rng = np.random.default_rng(SEED)
    d = drone(rng)
    p = pad(rng)
    w = wind(rng)
    s = sparkle(rng)
    # relative balance (pre-reverb); normalised to the target loudness at the end
    d /= np.sqrt(np.mean(d ** 2)); p /= np.sqrt(np.mean(p ** 2))
    w /= np.sqrt(np.mean(w ** 2)); s /= np.sqrt(np.mean(s ** 2))
    dry = 0.62 * d + 0.3 * p + 0.16 * w + 0.1 * s
    wet_src = 0.25 * d + 0.45 * p + 0.35 * w + 0.22 * s
    ir = dsp.reverb_ir(rt60=7.0, length=9.0, seed=SEED + 1, predelay=0.04, rt_high=2.6)
    wet = dsp.convolve_circular(wet_src, ir)
    wet /= np.sqrt(np.mean(wet ** 2)) / np.sqrt(np.mean(wet_src ** 2))
    mix = dry + 0.9 * wet
    # DC / sub rumble guard, circular
    spec = np.fft.rfft(mix, axis=0)
    f = np.fft.rfftfreq(N, 1 / SR)
    spec *= (1.0 / np.sqrt(1 + (30.0 / np.maximum(f, 1e-3)) ** 8))[:, None]
    mix = np.fft.irfft(spec, N, axis=0)
    return dsp.normalize_integrated(mix, -24.0, -1.5)


# Crossover between the floor and air stems: raised cosine on a log-frequency axis, flat floor
# below XO_LO, flat air above XO_HI (the recess covers the drone, 80-200 Hz and the wind's foot).
XO_LO = 180.0
XO_HI = 300.0


def split_floor_air(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Linear-phase complementary split over the whole (periodic) loop: floor + air == x."""
    n = x.shape[0]
    spec = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(n, 1 / SR)
    u = np.clip(np.log2(np.maximum(f, 1e-3) / XO_LO) / np.log2(XO_HI / XO_LO), 0.0, 1.0)
    h = 0.5 + 0.5 * np.cos(np.pi * u)          # 1 below XO_LO -> 0 above XO_HI
    floor = np.fft.irfft(spec * h[:, None], n, axis=0)
    return floor, x - floor


def main(floor_path: str, air_path: str) -> None:
    x = build()
    floor, air = split_floor_air(x)
    dsp.write_wav(floor_path, floor)
    dsp.write_wav(air_path, air)
    for name, y in [("amb_cosmos_loop (floor+air)", x), ("amb_cosmos_floor", floor),
                    ("amb_cosmos_air", air)]:
        seam = float(np.max(np.abs(y[0] - y[-1])))
        step = float(np.percentile(np.max(np.abs(np.diff(y, axis=0)), axis=1), 99.9))
        print(f"{name}: {y.shape[0] / SR:.1f}s  I={dsp.integrated_lufs(y):.1f} LUFS  "
              f"TP={dsp.true_peak_db(y):.1f} dBTP  seam_jump={seam:.5f} (p99.9 step {step:.5f})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
