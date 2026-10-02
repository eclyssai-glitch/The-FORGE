#!/usr/bin/env python3
"""DEV ONLY - Loop 5 r2: compares two r2_compare.gd traces (--trace=csv), legacy vs native body.

Usage: r2_analyze.py LEGACY.csv NATIVE.csv OUT_PREFIX
Writes OUT_PREFIX.txt (metrics) and OUT_PREFIX.ppm (curves; convert with ffmpeg). Pure Python.
Metrics: response time of every mood change (time to 90 % of the change of the shoulder raise and
of the chest pitch), peak angular speed / acceleration of the torso bones around it (pops),
largest per-frame step, life in calm (peak-to-peak of chest/head/clavicle), parity (RMS difference).
"""
import csv
import math
import sys

BONES = ["hips", "spine", "chest", "neck", "head", "clavicle.L"]
DT = 1.0 / 30.0


def load(path):
    rows = list(csv.DictReader(open(path)))
    out = {"t": [float(r["t"]) for r in rows], "mood": [r["mood"] for r in rows],
           "composure": [float(r["composure"]) for r in rows]}
    for b in BONES:
        for a in "xyz":
            out[b + "." + a] = [float(r[b + "." + a]) for r in rows]
        out[b + ".q"] = [tuple(float(r[b + ".q" + c]) for c in "xyzw") for r in rows]
    return out


def qangle(p, q):
    d = abs(sum(a * b for a, b in zip(p, q)))
    return math.degrees(2.0 * math.acos(min(1.0, d)))


def changes(tr):
    out = []
    for i in range(1, len(tr["t"])):
        if tr["mood"][i] != tr["mood"][i - 1]:
            out.append((tr["t"][i], tr["mood"][i - 1], tr["mood"][i], i))
    return out


def response(series, i0, horizon=90):
    """Seconds to 90 % of the change between frame i0 and the mean of the 0.5 s around i0+horizon."""
    end = min(len(series) - 1, i0 + horizon)
    lo = max(i0 + 1, end - 8)
    target = sum(series[lo:end + 1]) / (end + 1 - lo)
    start = series[i0]
    delta = target - start
    if abs(delta) < 0.3:
        return None, delta
    for k in range(i0, end + 1):
        if abs(series[k] - start) >= 0.9 * abs(delta):
            return (k - i0) * DT, delta
    return None, delta


def speeds(tr, b, i0, i1):
    q = tr[b + ".q"]
    v = [qangle(q[k], q[k - 1]) / DT for k in range(max(i0, 1), i1)]
    a = [abs(v[k] - v[k - 1]) / DT for k in range(1, len(v))]
    return (max(v) if v else 0.0), (max(a) if a else 0.0)


def main():
    leg, nat = load(sys.argv[1]), load(sys.argv[2])
    out = sys.argv[3]
    lines = []
    lines.append("mood changes (t from->to): response to 90 %% of change [s] (delta deg), legacy | native")
    for (t, a, b, i) in changes(leg):
        row = "%6.2f %-10s -> %-10s" % (t, a, b)
        for name in ["clavicle.L.z", "chest.x", "head.x"]:
            rl, dl = response(leg[name], i)
            rn, dn = response(nat[name], i)
            fmt = lambda r, d: ("%.2f" % r if r is not None else " -  ") + " (%+.1f)" % d
            row += " | %s: %s | %s" % (name, fmt(rl, dl), fmt(rn, dn))
        lines.append(row)
    lines.append("")
    lines.append("peak angular speed [deg/s] / peak angular acceleration [deg/s^2] in the 1.5 s after each change, legacy | native")
    for (t, a, b, i) in changes(leg):
        row = "%6.2f -> %-10s" % (t, b)
        for bone in ["chest", "neck", "head", "clavicle.L"]:
            vl, al = speeds(leg, bone, i, i + 45)
            vn, an = speeds(nat, bone, i, i + 45)
            row += " | %s %5.1f/%6.0f vs %5.1f/%6.0f" % (bone, vl, al, vn, an)
        lines.append(row)
    lines.append("")
    lines.append("largest per-frame step over the whole take [deg], legacy | native")
    for bone in BONES:
        sl = max(qangle(leg[bone + ".q"][k], leg[bone + ".q"][k - 1]) for k in range(2, len(leg["t"])))
        sn = max(qangle(nat[bone + ".q"][k], nat[bone + ".q"][k - 1]) for k in range(2, len(nat["t"])))
        lines.append("  %-11s %.2f | %.2f" % (bone, sl, sn))
    lines.append("")
    lines.append("life in calm (0.5-6 s): peak-to-peak [deg], legacy | native")
    i0, i1 = 15, 180
    for name in ["chest.x", "head.x", "head.z", "clavicle.L.z", "spine.z", "hips.z"]:
        pl = max(leg[name][i0:i1]) - min(leg[name][i0:i1])
        pn = max(nat[name][i0:i1]) - min(nat[name][i0:i1])
        lines.append("  %-13s %.2f | %.2f" % (name, pl, pn))
    lines.append("")
    lines.append("parity: RMS difference legacy-native over the take [deg] (per bone quaternion angle)")
    for bone in BONES:
        d = [qangle(leg[bone + ".q"][k], nat[bone + ".q"][k]) for k in range(len(leg["t"]))]
        lines.append("  %-11s rms %.2f  max %.2f" % (bone, math.sqrt(sum(x * x for x in d) / len(d)), max(d)))
    open(out + ".txt", "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    plot(leg, nat, out + ".ppm")


def plot(leg, nat, path):
    W, H = 1600, 900
    img = bytearray([18, 18, 26] * W * H)
    panels = [("clavicle.L.z", "shoulder raise (clavicle.L z)"), ("chest.x", "chest pitch"), ("head.x", "head pitch"),
              ("head.z", "head roll")]
    ph = H // len(panels)
    tmax = leg["t"][-1]
    colors = {"calm": (40, 60, 90), "focused": (40, 80, 60), "frustrated": (100, 70, 30), "angry": (110, 35, 35),
              "recovering": (60, 50, 100)}

    def put(x, y, c):
        if 0 <= x < W and 0 <= y < H:
            k = (y * W + x) * 3
            img[k:k + 3] = bytes(c)

    for p, (name, _label) in enumerate(panels):
        y0 = p * ph
        for x in range(W):
            k = min(len(leg["t"]) - 1, int(x / W * len(leg["t"])))
            c = colors.get(leg["mood"][k], (30, 30, 30))
            for y in range(y0 + ph - 6, y0 + ph - 2):
                put(x, y, c)
        vals = leg[name] + nat[name]
        lo, hi = min(vals), max(vals)
        span = max(hi - lo, 1e-3)
        for series, col in ((leg[name], (235, 200, 120)), (nat[name], (120, 200, 255))):
            prev = None
            for k, v in enumerate(series):
                x = int(leg["t"][k] / tmax * (W - 1))
                y = y0 + 8 + int((1.0 - (v - lo) / span) * (ph - 24))
                if prev:
                    for s in range(abs(y - prev[1]) + 1):
                        yy = prev[1] + (s if y >= prev[1] else -s)
                        put(x, yy, col)
                        put(x, yy + 1, col)
                put(x, y, col)
                put(x, y + 1, col)
                prev = (x, y)
        for x in range(W):
            put(x, y0, (60, 60, 70))
    with open(path, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (W, H))
        f.write(bytes(img))


if __name__ == "__main__":
    main()
