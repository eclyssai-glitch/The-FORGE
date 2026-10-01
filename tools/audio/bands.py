"""Band analysis of a mix or asset (the low-end check of docs/AUDIO.md).

Prints, for FILE:
  1. EBU R128 split at 300 Hz (ffmpeg ebur128 on a zero-phase 4th-order Butterworth split,
     |LP|^2 + |HP|^2 = 1): integrated loudness of the part below and above 300 Hz.
  2. Max short-term loudness (ebur128 S, 3 s blocks) of each time window: blocks ending from
     1 s after the window start to 1 s after its end (the window's sound, not the previous one).
  3. Unweighted band energy (dBFS RMS, both channels) per time window, bands
     SUB 20-35 · LOW 35-80 · BODY 80-200 · WARM 110-220 · MID 200-2k · HIGH 2k-16k.
     WARM overlaps BODY on purpose: it is the harmonic weight a notebook speaker still plays.
Windows default to the GENESIS big moments; `--windows a-b,c-d` overrides.

Usage: bands.py FILE [--windows 8-13,18-21,...] [--json OUT.json]
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

BANDS = [("SUB", 20.0, 35.0), ("LOW", 35.0, 80.0), ("BODY", 80.0, 200.0),
         ("WARM", 110.0, 220.0), ("MID", 200.0, 2000.0), ("HIGH", 2000.0, 16000.0)]
# GENESIS: ambience alone, awaken, hands, dust, seed, magma, crust, atmosphere, moons..links,
# stable (the climax), tail.
DEFAULT_WINDOWS = [(4.5, 7.5, "awaken"), (8.0, 13.0, "hands"), (13.0, 18.0, "dust"),
                   (18.0, 21.0, "seed"), (22.0, 27.0, "magma"), (27.0, 32.0, "crust"),
                   (32.0, 37.0, "atmosphere"), (37.0, 53.0, "moons-links"),
                   (53.0, 57.0, "stable"), (57.0, 61.0, "stable tail")]


def load(path: str) -> tuple[int, np.ndarray]:
    if path.endswith(".wav"):
        sr, x = wavfile.read(path)
    else:
        with tempfile.TemporaryDirectory() as d:
            tmp = os.path.join(d, "x.wav")
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", path,
                            "-c:a", "pcm_f32le", tmp], check=True)
            sr, x = wavfile.read(tmp)
    x = x.astype(np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], -1)
    return sr, x


def split300(sr: int, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    lo = signal.sosfiltfilt(signal.butter(2, 300.0, "lowpass", fs=sr, output="sos"), x, axis=0)
    hi = signal.sosfiltfilt(signal.butter(2, 300.0, "highpass", fs=sr, output="sos"), x, axis=0)
    return lo, hi


def ebur128_short_term(path: str) -> list[tuple[float, float]]:
    """(t, S) per 100 ms frame from ffmpeg ebur128 (t = end of the 3 s block)."""
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-v", "verbose", "-i", path,
                        "-af", "ebur128=framelog=verbose", "-f", "null", "-"],
                       capture_output=True, text=True, check=True)
    out = []
    for m in re.finditer(r"t:\s*([\d.]+).*?S:\s*(-?[\d.]+|-inf)", p.stderr):
        if m.group(2) != "-inf":
            out.append((float(m.group(1)), float(m.group(2))))
    return out


def ebur128_integrated(sr: int, x: np.ndarray) -> float:
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "b.wav")
        wavfile.write(tmp, sr, x.astype(np.float32))
        p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", tmp, "-af", "ebur128",
                            "-f", "null", "-"], capture_output=True, text=True, check=True)
    s = p.stderr[p.stderr.rfind("Summary:"):]
    for line in s.splitlines():
        line = line.strip()
        if line.startswith("I:"):
            return float(line.split()[1])
    return float("nan")


def band_power(sr: int, x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """Per-sample power (L + R) of x band-passed to [lo, hi] (filtered whole, windowed later:
    filtering a cut segment would add edge transients to the lowest bands)."""
    sos = signal.butter(4, [lo, hi], "bandpass", fs=sr, output="sos")
    y = signal.sosfiltfilt(sos, x, axis=0)
    return np.sum(y ** 2, axis=1)


def analyse(path: str, windows) -> dict:
    sr, x = load(path)
    lo, hi = split300(sr, x)
    out = {"file": path, "I_below_300": ebur128_integrated(sr, lo),
           "I_above_300": ebur128_integrated(sr, hi), "I": ebur128_integrated(sr, x),
           "windows": []}
    dur = x.shape[0] / sr
    power = {name: band_power(sr, x, f0, f1) for name, f0, f1 in BANDS}
    st = ebur128_short_term(path)
    for a, b, label in windows:
        if a >= dur:
            continue
        s = slice(int(a * sr), int(min(b, dur) * sr))
        row = {"label": label, "from": a, "to": b}
        for name, _, _ in BANDS:
            row[name] = float(10 * np.log10(np.mean(power[name][s]) + 1e-20))
        vals = [v for t, v in st if a + 1.0 <= t < min(b, dur) + 1.0]
        row["S_max"] = max(vals) if vals else float("nan")
        out["windows"].append(row)
    return out


def main(argv: list[str]) -> int:
    path = argv[0]
    windows = DEFAULT_WINDOWS
    js = None
    i = 1
    while i < len(argv):
        if argv[i] == "--windows":
            windows = []
            for w in argv[i + 1].split(","):
                a, b = w.split("-")
                windows.append((float(a), float(b), w))
            i += 2
        elif argv[i] == "--json":
            js = argv[i + 1]
            i += 2
        else:
            i += 1
    r = analyse(path, windows)
    print(f"{os.path.basename(path)}: I {r['I']:.1f} LUFS  < 300 Hz {r['I_below_300']:.1f} LUFS  "
          f"> 300 Hz {r['I_above_300']:.1f} LUFS  (below - above {r['I_below_300'] - r['I_above_300']:+.1f} LU)")
    names = [b[0] for b in BANDS]
    print("| window | S max (LUFS) | " + " | ".join(names) + " | BODY-MID | WARM-LOW |")
    print("|---|" + "---:|" * (len(names) + 3))
    for w in r["windows"]:
        cells = " | ".join(f"{w[n]:.1f}" for n in names)
        print(f"| {w['label']} {w['from']:g}-{w['to']:g} s | {w['S_max']:.1f} | {cells} | {w['BODY'] - w['MID']:+.1f} | "
              f"{w['WARM'] - w['LOW']:+.1f} |")
    if js:
        with open(js, "w") as f:
            json.dump(r, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
