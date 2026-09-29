"""Shared DSP for the KORIUM UNIVERSE offline sound synthesis (tools/audio).

Pure numpy/scipy, deterministic: every random source takes an explicit seed.
Signals are float64 arrays shaped (n, 2) (stereo) unless noted; sample rate SR.
Nothing here reads samples or calls any service: every sound is built from oscillators,
noise and filters written in this folder.
"""
from __future__ import annotations

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000

# ---------------------------------------------------------------- pitch

def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


NOTE_INDEX = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
              "G#": 8, "A": 9, "A#": 10, "B": 11}


def note(name: str) -> float:
    """'A2' -> 110.0, 'C#4' -> 277.18. Octave numbering: A4 = 440 Hz."""
    pitch, octave = name[:-1], int(name[-1])
    return midi_hz(12 * (octave + 1) + NOTE_INDEX[pitch])


# ---------------------------------------------------------------- time helpers

def seconds(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def silence(dur: float) -> np.ndarray:
    return np.zeros((int(round(dur * SR)), 2))


def add_at(buf: np.ndarray, x: np.ndarray, start_s: float, wrap: bool = False) -> None:
    """Mixes x into buf starting at start_s. wrap=True wraps around the end (periodic loops)."""
    start = int(round(start_s * SR))
    n = buf.shape[0]
    if wrap:
        idx = (start + np.arange(x.shape[0])) % n
        np.add.at(buf, idx, x)
        return
    if start >= n:
        return
    end = min(n, start + x.shape[0])
    buf[start:end] += x[: end - start]


def pan(mono: np.ndarray, p) -> np.ndarray:
    """Equal-power pan. p in [-1, 1] (scalar or per-sample array)."""
    p = np.clip(p, -1.0, 1.0)
    a = (p + 1.0) * np.pi / 4.0
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=-1)


# ---------------------------------------------------------------- envelopes

def env_attack_decay(n: int, attack: float, decay: float, curve: float = 1.0) -> np.ndarray:
    """Raised-cosine attack (s) then exponential decay with time constant `decay` (s)."""
    t = seconds(n)
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    a = 0.5 - 0.5 * np.cos(np.pi * a)
    d = np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))
    return (a * d) ** curve


def env_swell(n: int, attack: float, hold: float, release: float) -> np.ndarray:
    """Smooth swell: raised-cosine attack, hold, raised-cosine release; zero after."""
    t = seconds(n)
    e = np.zeros(n)
    a = t < attack
    e[a] = 0.5 - 0.5 * np.cos(np.pi * t[a] / max(attack, 1e-4))
    h = (t >= attack) & (t < attack + hold)
    e[h] = 1.0
    r = (t >= attack + hold) & (t < attack + hold + release)
    e[r] = 0.5 + 0.5 * np.cos(np.pi * (t[r] - attack - hold) / max(release, 1e-4))
    return e


def fade_out(x: np.ndarray, dur: float) -> np.ndarray:
    n = min(x.shape[0], int(dur * SR))
    if n <= 0:
        return x
    y = x.copy()
    ramp = 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, n))
    y[-n:] *= ramp[:, None] if y.ndim == 2 else ramp
    return y


def fade_in(x: np.ndarray, dur: float) -> np.ndarray:
    n = min(x.shape[0], int(dur * SR))
    if n <= 0:
        return x
    y = x.copy()
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n))
    y[:n] *= ramp[:, None] if y.ndim == 2 else ramp
    return y


# ---------------------------------------------------------------- filters

def butter(x: np.ndarray, kind: str, freq, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfiltfilt(sos, x, axis=0)


def spectral_shape(n: int, shape_fn, rng: np.random.Generator, channels: int = 2) -> np.ndarray:
    """Exactly periodic (length n) noise with magnitude spectrum shape_fn(freqs)."""
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    mag = shape_fn(freqs)
    mag[0] = 0.0
    out = np.empty((n, channels))
    for c in range(channels):
        ph = rng.uniform(0.0, 2.0 * np.pi, freqs.shape[0])
        out[:, c] = np.fft.irfft(mag * np.exp(1j * ph), n)
    out /= np.sqrt(np.mean(out ** 2)) + 1e-12
    return out


def band_shape(center: float, width_oct: float):
    """Gaussian band on a log-frequency axis (smooth, no ringing)."""
    def fn(f):
        lf = np.log2(np.maximum(f, 1.0) / center)
        return np.exp(-0.5 * (lf / width_oct) ** 2)
    return fn


def soft_saturate(x: np.ndarray, drive: float) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


# ---------------------------------------------------------------- oscillators

def partial_bank(freqs, amps, n: int, rng: np.random.Generator, decays=None,
                 attack: float = 0.004) -> np.ndarray:
    """Sum of sines (mono). decays: per-partial exponential time constants or None (sustained)."""
    t = seconds(n)
    y = np.zeros(n)
    for i, (f, a) in enumerate(zip(freqs, amps)):
        if f >= SR * 0.45 or a == 0.0:
            continue
        ph = rng.uniform(0.0, 2.0 * np.pi)
        s = a * np.sin(2.0 * np.pi * f * t + ph)
        if decays is not None:
            s *= np.exp(-t / decays[i])
        y += s
    if attack > 0:
        k = min(n, int(attack * SR))
        y[:k] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, k))
    return fade_out(y, min(0.25, n / SR * 0.2))  # never end on a cut


# Soft crystalline bell: near-harmonic partials, higher ones decay faster, paired detunes
# give a slow shimmer. No minor-third "church" partial (keeps the lydian/pentatonic colour).
BELL_RATIOS = [1.0, 1.0016, 2.0, 2.003, 3.01, 4.16, 5.43, 6.79]
BELL_AMPS = [1.0, 0.55, 0.42, 0.2, 0.16, 0.11, 0.06, 0.035]
BELL_DECAY = [1.0, 0.9, 0.55, 0.5, 0.33, 0.22, 0.15, 0.1]


def bell(f0: float, dur: float, decay: float, rng: np.random.Generator,
         brightness: float = 1.0, attack: float = 0.006) -> np.ndarray:
    n = int(dur * SR)
    amps = [a * (brightness ** i) for i, a in enumerate(BELL_AMPS)]
    return partial_bank([f0 * r for r in BELL_RATIOS], amps, n, rng,
                        decays=[decay * d for d in BELL_DECAY], attack=attack)


def celesta(f0: float, dur: float, decay: float, rng: np.random.Generator) -> np.ndarray:
    """Struck-bar tone: fundamental + octave + faint 4th harmonic, soft mallet."""
    n = int(dur * SR)
    return partial_bank([f0, f0 * 2.0, f0 * 4.0, f0 * 1.0009], [1.0, 0.3, 0.07, 0.5], n, rng,
                        decays=[decay, decay * 0.45, decay * 0.18, decay * 0.9], attack=0.003)


VOWELS = {
    # formant centre (Hz), bandwidth (Hz), gain
    "ah": ([800.0, 1150.0, 2900.0], [110.0, 120.0, 180.0], [1.0, 0.5, 0.18]),
    "oh": ([450.0, 800.0, 2830.0], [90.0, 100.0, 160.0], [1.0, 0.35, 0.08]),
    "oo": ([325.0, 700.0, 2530.0], [80.0, 90.0, 150.0], [1.0, 0.2, 0.05]),
    "eh": ([530.0, 1840.0, 2480.0], [90.0, 120.0, 160.0], [1.0, 0.4, 0.15]),
}


def formant_gain(f: np.ndarray, vowel: str) -> np.ndarray:
    fc, bw, g = VOWELS[vowel]
    out = np.full_like(f, 0.015, dtype=np.float64)
    for c, b, a in zip(fc, bw, g):
        out += a / (1.0 + ((f - c) / (b * 0.5)) ** 2)
    return out


def choir_voice(f0: float, n: int, rng: np.random.Generator, vowel_a: str, vowel_b: str,
                morph=None, vib_rate: float = 0.23, vib_depth: float = 0.0025,
                fmax: float = 5000.0, t0: float = 0.0, drift=None) -> np.ndarray:
    """One formant voice (mono). Additive harmonics with a vowel envelope morphing a->b.
    morph: per-sample array in [0,1] or None (vowel_a only). vib_* gives a slow sinusoidal drift
    (exactly periodic; used by the loop), not operatic vibrato. drift: optional per-sample
    fractional pitch deviation (random wander, one-shots) replacing the sinusoid.
    t0 offsets the time axis (for periodic loops the caller keeps f0*T integer)."""
    t = seconds(n) + t0
    if drift is not None:
        phase = 2.0 * np.pi * f0 * (t0 + np.cumsum(1.0 + drift) / SR)
    else:
        phase = 2.0 * np.pi * f0 * t + (vib_depth * f0 / max(vib_rate, 1e-6)) * np.sin(
            2.0 * np.pi * vib_rate * t + rng.uniform(0, 2 * np.pi))
    kmax = int(fmax // f0)
    ks = np.arange(1, kmax + 1)
    fk = ks * f0
    src = 1.0 / ks ** 1.1
    ga = src * formant_gain(fk, vowel_a)
    gb = src * formant_gain(fk, vowel_b)
    ya = np.zeros(n)
    yb = np.zeros(n) if morph is not None else None
    for i, k in enumerate(ks):
        s = np.sin(k * phase + rng.uniform(0, 2 * np.pi))
        ya += ga[i] * s
        if yb is not None:
            yb += gb[i] * s
    if morph is None:
        return ya
    return (1.0 - morph) * ya + morph * yb


def choir(freqs, n: int, rng: np.random.Generator, vowel_a="ah", vowel_b="oh", morph=None,
          voices: int = 3, detune_cents: float = 2.5, spread: float = 0.7,
          wander_cents: float = 3.0) -> np.ndarray:
    """Ethereal ensemble (stereo): several voices per note, spread across the image.
    Voices differ by a small fixed detune plus an independent slow random pitch wander and
    unequal levels, so their beating stays irregular and shallow (no tremolo)."""
    out = np.zeros((n, 2))
    for f in freqs:
        for v in range(voices):
            cents = (v - (voices - 1) / 2.0) * detune_cents + rng.uniform(-0.8, 0.8)
            fv = f * 2.0 ** (cents / 1200.0)
            w = butter(rng.standard_normal(n + 2 * SR), "lowpass", 0.4, 2)[SR:-SR]
            w *= (wander_cents / 1200.0 * np.log(2.0)) / (np.std(w) + 1e-12)
            y = choir_voice(fv, n, rng, vowel_a, vowel_b, morph, drift=w)
            p = spread * ((v / max(voices - 1, 1)) * 2.0 - 1.0) if voices > 1 else 0.0
            out += pan(y * (1.0 - 0.18 * v), p)
    return out / max(len(freqs) * voices, 1)


def pluck(f0: float, dur: float, rng: np.random.Generator, damping: float = 0.996,
          brightness: float = 0.5) -> np.ndarray:
    """Karplus-Strong harp-like pluck (mono), deterministic excitation from rng.
    Processed one period per block (each block only reads earlier samples)."""
    n = int(dur * SR)
    period = SR / f0
    p = int(period)
    frac = period - p
    exc = rng.uniform(-1.0, 1.0, p + 2)
    # soften the excitation (felt-plucked harp, not a pick)
    exc = signal.lfilter([brightness], [1.0, -(1.0 - brightness)], exc)
    exc -= exc.mean()
    total = n + p + 2
    y = np.zeros(total + p)
    y[: p + 2] = exc
    i = p + 2
    while i < total:
        j = min(i + p, total)
        a = y[i - p: j - p]
        b = y[i - p - 1: j - p - 1]
        c = y[i - p - 2: j - p - 2]
        d1 = (1 - frac) * a + frac * b
        d2 = (1 - frac) * b + frac * c
        y[i:j] = damping * 0.5 * (d1 + d2)
        i = j
    return fade_out(y[p + 2: p + 2 + n].copy(), min(0.25, n / SR * 0.2))


# ---------------------------------------------------------------- reverb

def reverb_ir(rt60: float, length: float, seed: int, predelay: float = 0.025,
              rt_high: float | None = None, rt_low: float | None = None,
              width: float = 1.0) -> np.ndarray:
    """Synthetic diffuse stereo IR: decorrelated noise with exponential decay per band
    (low / mid / high), soft onset. Energy-normalised."""
    rng = np.random.default_rng(seed)
    n = int(length * SR)
    t = seconds(n)
    noise = rng.standard_normal((n, 2))
    if width < 1.0:
        mid = noise.mean(axis=1, keepdims=True)
        noise = mid + width * (noise - mid)
    rt_high = rt_high if rt_high is not None else rt60 * 0.45
    rt_low = rt_low if rt_low is not None else rt60 * 1.1
    lo = butter(noise, "lowpass", 400.0, 2)
    hi = butter(noise, "highpass", 3500.0, 2)
    md = noise - lo - hi
    ir = (lo * np.exp(-6.91 * t / rt_low)[:, None] + md * np.exp(-6.91 * t / rt60)[:, None]
          + hi * np.exp(-6.91 * t / rt_high)[:, None])
    onset = np.clip(t / 0.06, 0, 1) ** 1.5
    ir *= onset[:, None]
    ir = np.concatenate([np.zeros((int(predelay * SR), 2)), ir])
    ir = fade_out(ir, min(0.5, length * 0.2))
    ir /= np.sqrt(np.sum(ir ** 2) / 2.0) + 1e-12
    return ir


def convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """Linear convolution (stereo x stereo, per channel). Output is len(x)+len(ir)-1."""
    if x.ndim == 1:
        x = np.stack([x, x], axis=-1)
    return np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], axis=-1)


def convolve_circular(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """Circular convolution over len(x): the reverb tail wraps into the start (seamless loops)."""
    n = x.shape[0]
    out = np.empty_like(x)
    for c in range(2):
        out[:, c] = np.fft.irfft(np.fft.rfft(x[:, c]) * np.fft.rfft(ir[:, c], n), n)
    return out


def wet_dry(dry: np.ndarray, ir: np.ndarray, wet: float, tail: float) -> np.ndarray:
    """dry*(1-wet) + reverb*wet, extended by `tail` seconds (linear convolution)."""
    n = dry.shape[0] + int(tail * SR)
    padded = np.zeros((n, 2))
    padded[: dry.shape[0]] = dry
    rev = convolve(padded, ir)[:n]
    return (1.0 - wet) * padded + wet * rev


# ---------------------------------------------------------------- loudness (ITU-R BS.1770-4)

_K1_B = [1.53512485958697, -2.69169618940638, 1.19839281085285]
_K1_A = [1.0, -1.69065929318241, 0.73248077421585]
_K2_B = [1.0, -2.0, 1.0]
_K2_A = [1.0, -1.99004745483398, 0.99007225036621]


def _k_weighted_power(x: np.ndarray) -> np.ndarray:
    y = signal.lfilter(_K1_B, _K1_A, x, axis=0)
    y = signal.lfilter(_K2_B, _K2_A, y, axis=0)
    return np.sum(y ** 2, axis=1)  # channel weights = 1 (L, R)


def _block_loudness(p: np.ndarray, win: float, step: float, pad: bool) -> np.ndarray:
    w = int(win * SR)
    s = int(step * SR)
    if pad and p.shape[0] < w:
        p = np.concatenate([p, np.zeros(w - p.shape[0])])
    c = np.concatenate([[0.0], np.cumsum(p)])
    starts = np.arange(0, max(p.shape[0] - w, 0) + 1, s)
    ms = (c[starts + w] - c[starts]) / w
    return -0.691 + 10.0 * np.log10(ms + 1e-20)


def integrated_lufs(x: np.ndarray) -> float:
    lk = _block_loudness(_k_weighted_power(x), 0.4, 0.1, pad=True)
    lk = lk[lk > -70.0]
    if lk.size == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(10 ** ((lk + 0.691) / 10))) - 10.0
    lk = lk[lk > rel]
    return float(-0.691 + 10 * np.log10(np.mean(10 ** ((lk + 0.691) / 10))))


def short_term_max_lufs(x: np.ndarray) -> float:
    return float(np.max(_block_loudness(_k_weighted_power(x), 3.0, 0.1, pad=True)))


def momentary_max_lufs(x: np.ndarray) -> float:
    return float(np.max(_block_loudness(_k_weighted_power(x), 0.4, 0.1, pad=True)))


def true_peak_db(x: np.ndarray) -> float:
    up = signal.resample_poly(x, 4, 1, axis=0)
    return float(20 * np.log10(np.max(np.abs(up)) + 1e-12))


def sample_peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(np.max(np.abs(x)) + 1e-12))


# ---------------------------------------------------------------- dynamics

def limit(x: np.ndarray, ceiling_db: float, lookahead: float = 0.012,
          release: float = 0.12) -> np.ndarray:
    """Transparent-ish lookahead peak limiter. The gain never exceeds what each sample needs
    (min-filter over +-lookahead, then a moving average shorter than the min window)."""
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    c = 10 ** (ceiling_db / 20.0)
    peak = np.max(np.abs(x), axis=1)
    need = np.minimum(1.0, c / np.maximum(peak, 1e-12))
    if np.all(need >= 1.0):
        return x
    # gain at each sample = min of what any sample within +-R needs, averaged over R:
    # never above what the sample itself needs, attack spread over R/2, release over R.
    R = max(int(max(lookahead, release) * SR), 1)
    g = uniform_filter1d(minimum_filter1d(need, size=2 * R + 1, mode="nearest"), size=R,
                         mode="nearest")
    return x * g[:, None]


def _enforce_ceiling(y: np.ndarray, ceiling_dbtp: float) -> np.ndarray:
    margin = 0.3
    while true_peak_db(y) > ceiling_dbtp and margin < 3.0:
        y = limit(y, ceiling_dbtp - margin)
        margin += 0.3
    return y


def normalize_short_term(x: np.ndarray, target_lufs: float, ceiling_dbtp: float) -> np.ndarray:
    y = x * 10 ** ((target_lufs - short_term_max_lufs(x)) / 20.0)
    return _enforce_ceiling(y, ceiling_dbtp)


def normalize_integrated(x: np.ndarray, target_lufs: float, ceiling_dbtp: float) -> np.ndarray:
    y = x * 10 ** ((target_lufs - integrated_lufs(x)) / 20.0)
    return _enforce_ceiling(y, ceiling_dbtp)


def normalize_peak(x: np.ndarray, peak_db: float) -> np.ndarray:
    return x * 10 ** ((peak_db - true_peak_db(x)) / 20.0)


# ---------------------------------------------------------------- output

def trim_tail(x: np.ndarray, floor_db: float = -72.0, min_len: float = 0.2,
              fade: float = 0.25) -> np.ndarray:
    """Cuts trailing near-silence (below floor relative to full scale) and fades the end."""
    thr = 10 ** (floor_db / 20.0)
    loud = np.nonzero(np.max(np.abs(x), axis=1) > thr)[0]
    end = int(max(loud[-1] + 1 if loud.size else 0, min_len * SR))
    return fade_out(x[: min(end + int(0.05 * SR), x.shape[0])], fade)


def write_wav(path: str, x: np.ndarray) -> None:
    wavfile.write(path, SR, np.ascontiguousarray(x.astype(np.float32)))
