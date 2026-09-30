"""Parametric sculpted hand (SDF).

Authoring frame (units: wrist -> middle fingertip = 7 when straight):
  origin = wrist centre, +Y = along the hand towards the fingers, +Z = dorsal (back of the hand),
  +X = Y x Z. In this right-handed frame the thumb sits on +X, i.e. the authored hand is a LEFT
  hand. A right hand is ``sdf.mirror_x`` of an authored hand (with its own pose).

``build_hand(pose, detail)`` returns ``(sdf, anchors)``; anchors are points/directions in the
authoring frame (palm centre, palm normal, fingertips, wrist centre, forearm direction).
"""
from __future__ import annotations

import numpy as np

import sdf as S
from sdf import v3, normalize, rot_axis

FINGERS = ("index", "middle", "ring", "little")

# MCP joint centres (x, y) and the metacarpal base (x at the carpus) -- authored left hand
MCP = {"index": (1.06, 3.30), "middle": (0.33, 3.44), "ring": (-0.41, 3.34), "little": (-1.08, 3.08)}
CARPAL_X = {"index": 0.42, "middle": 0.12, "ring": -0.18, "little": -0.46}
LENGTHS = {
    "index": (1.42, 0.90, 0.70),
    "middle": (1.55, 1.00, 0.76),
    "ring": (1.46, 0.95, 0.72),
    "little": (1.12, 0.72, 0.62),
}
RADII = {  # at MCP, PIP, DIP, tip
    "index": (0.35, 0.31, 0.276, 0.240),
    "middle": (0.362, 0.32, 0.284, 0.25),
    "ring": (0.34, 0.30, 0.265, 0.231),
    "little": (0.295, 0.26, 0.23, 0.203),
}
DEBUG_PARTS: dict = {}
THUMB_LENGTHS = (1.40, 1.06, 0.90)
THUMB_RADII = (0.46, 0.405, 0.36, 0.29)


def _finger(base, frame, lengths, radii, flex, detail, scale_k=1.0):
    """One finger as a list of (sdf, k) parts plus its joint points and final frame."""
    X, Y, Z = frame[:, 0].copy(), frame[:, 1].copy(), frame[:, 2].copy()
    pts = [v3(base)]
    frames = []
    for i in range(3):
        R = rot_axis(X, -flex[i])
        Y = R @ Y
        Z = R @ Z
        frames.append(np.stack([X, Y, Z], axis=1))
        pts.append(pts[-1] + Y * lengths[i])
    parts = []
    core = S.union(*[S.round_cone(pts[i], pts[i + 1], radii[i], radii[i + 1]) for i in range(3)])
    parts.append((core, 0.0))
    if detail:
        for i in range(3):
            fr = frames[i]
            mid = 0.5 * (pts[i] + pts[i + 1])
            rm = 0.5 * (radii[i] + radii[i + 1])
            # palmar pad: the finger is fuller on the palm side than on the back
            pad_c = mid - fr[:, 2] * rm * 0.24 + fr[:, 1] * lengths[i] * 0.04
            parts.append((S.ellipsoid(pad_c, (rm * 0.80, lengths[i] * 0.43, rm * 0.8), fr),
                          0.10 * scale_k))
        for i in (1, 2):
            fr = frames[i - 1]
            # dorsal knuckle of the PIP / DIP joint
            parts.append((S.sphere(pts[i] + fr[:, 2] * radii[i] * 0.2, radii[i] * 0.86), 0.08 * scale_k))
    tip = pts[3] + frames[2][:, 1] * radii[3]
    return parts, pts, frames, tip


def _finger_cuts(pts, frames, lengths, radii, detail, nails=True):
    """Subtractive details: palmar joint creases and the insinuated nail plate."""
    cuts = []
    if not detail:
        return cuts
    for i in (1, 2):
        fr = frames[i - 1]
        X, Z = fr[:, 0], fr[:, 2]
        c = pts[i] - Z * radii[i] * 1.02
        cuts.append((S.capsule(c - X * radii[i] * 0.5, c + X * radii[i] * 0.5, 0.055), 0.13))
    if nails:
        fr = frames[2]
        r3 = radii[3]
        L = lengths[2]
        R = fr

        def nail(p, P=pts[2], R=R, r3=r3, L=L):
            q = (p - P) @ R
            z0 = r3 * 0.88
            y0 = L * 0.30
            # bounded slab: above the nail plane, from the cuticle to past the tip, one finger wide
            d = np.maximum(z0 - q[:, 2], y0 - q[:, 1])
            d = np.maximum(d, np.abs(q[:, 0]) - r3 * 1.15)
            d = np.maximum(d, q[:, 1] - (L + r3 * 2.0))
            return np.maximum(d, q[:, 2] - r3 * 2.5)
        S.with_bound(nail, pts[2] + fr[:, 1] * L * 0.6 + fr[:, 2] * r3, L + 3.0 * r3)
        cuts.append((nail, 0.06))
    return cuts


def build_hand(pose: dict, detail: bool = True, forearm: bool = True):
    finger_sdfs = []
    cuts = []
    anchors = {}
    arch = pose.get("arch", 0.15)
    squeeze = pose.get("mcp_squeeze", 1.0)  # < 1 brings the knuckles (and fingers) together
    # ---------------------------------------------------------------- fingers
    finger_frames = {}
    for name in FINGERS:
        spread, roll, flex = pose["fingers"][name]
        mx, my = MCP[name]
        mx *= squeeze
        mz = arch * (1.0 - (mx / 1.2) ** 2) * 0.35
        base = v3(mx, my, mz)
        Y0 = v3(0, 1, 0)
        Z0 = v3(0, 0, 1)
        R = rot_axis(Z0, -spread)  # positive spread = towards the thumb (+X)
        Y0, X0 = R @ Y0, R @ v3(1, 0, 0)
        Rr = rot_axis(Y0, roll)
        X0, Z0 = Rr @ X0, Rr @ Z0
        frame = np.stack([X0, Y0, Z0], axis=1)
        parts, pts, frames, tip = _finger(base, frame, LENGTHS[name], RADII[name], flex, detail)
        finger_sdfs.append(S.blend(parts[0][0], parts[1:]))
        cuts += _finger_cuts(pts, frames, LENGTHS[name], RADII[name], detail, pose.get("nails", True))
        finger_frames[name] = (pts, frames)
        anchors[f"tip_{name}"] = tip
    # ---------------------------------------------------------------- thumb
    th = pose["thumb"]
    cmc = v3(th["cmc"])
    tframe = S.frame_from(th["dir"], th["dorsal"])
    t_parts, t_pts, t_frames, t_tip = _finger(cmc, tframe, THUMB_LENGTHS, THUMB_RADII,
                                              (0.0,) + tuple(th["flex"]), detail)
    thumb_sdf = S.blend(t_parts[0][0], t_parts[1:])
    cuts += _finger_cuts(t_pts, t_frames, THUMB_LENGTHS, THUMB_RADII, detail, pose.get("nails", True))
    anchors["tip_thumb"] = t_tip
    # ---------------------------------------------------------------- palm mass
    palm = []
    for name in FINGERS:
        mx, my = MCP[name]
        mx *= squeeze
        mz = arch * (1.0 - (mx / 1.2) ** 2) * 0.35
        r0 = RADII[name][0]
        palm.append(S.round_cone((CARPAL_X[name], 0.85, 0.02), (mx * 0.98, my - 0.12, mz - 0.02),
                                 0.34, r0 + 0.02))
    body = S.union(*palm, k=0.55)
    core = S.ellipsoid((0.0, 1.95, -0.03), (1.16, 1.62, 0.45))
    carpus = S.ellipsoid((0.0, 0.5, -0.04), (0.98, 0.7, 0.5))
    thenar = S.ellipsoid(th.get("thenar_c", (0.72, 1.30, -0.36)), (0.62, 0.98, 0.46),
                         S.rot_z(-0.42) @ S.rot_y(0.25))
    hypo = S.ellipsoid((-0.88, 1.64, -0.26), (0.44, 1.15, 0.40), S.rot_z(0.08))
    pad = S.capsule((-0.95, 2.88, -0.26), (0.95, 3.10, -0.22), 0.34)
    palm_sdf = S.blend(body, [(core, 0.45), (carpus, 0.45), (thenar, 0.40), (hypo, 0.38), (pad, 0.30)])
    hollow = S.ellipsoid((0.02, 2.05, -0.98), (0.70, 0.98, 0.48))
    palm_sdf = S.subtract(palm_sdf, hollow, 0.40)
    palm_sdf = S.cup(palm_sdf, arch * 0.12)
    parts = [(palm_sdf, 0.0)]
    # wrist bones
    parts.append((S.sphere((-0.90, 0.10, 0.22), 0.20), 0.40))   # ulnar head (little-finger side)
    parts.append((S.sphere((0.92, 0.02, 0.0), 0.16), 0.40))     # radial styloid
    if detail:
        # metacarpal heads (knuckles) and dorsal extensor tendons
        for name in FINGERS:
            pts, frames = finger_frames[name]
            parts.append((S.sphere(pts[0] + frames[0][:, 2] * 0.06, RADII[name][0] + 0.02), 0.18))
        for name in FINGERS:
            # extensor tendons: only a soft relief over the middle of the dorsum
            mx, my = MCP[name]
            mx *= squeeze
            y0, y1 = 1.25, my - 0.75
            x0, x1 = CARPAL_X[name] * 0.55 + mx * 0.45, mx * 0.9
            top0 = _surface_z(palm_sdf, x0, y0)
            top1 = _surface_z(palm_sdf, x1, y1)
            a = v3(x0, y0, top0 - 0.16)
            b = v3(x1, y1, top1 - 0.14)
            parts.append((S.round_cone(a, b, 0.04, 0.065), 0.4))
    # ---------------------------------------------------------------- forearm (stump)
    fa_dir = normalize(pose.get("forearm_dir", (0.0, -1.0, 0.0)))
    if forearm:
        # spindle-shaped forearm fragment: narrow wrist, muscle belly, long soft taper
        L = pose.get("forearm_len", 3.6)
        spindle = S.tube([(0, 0.0, 0), (0, L * 0.4, 0.05), (0, L * 0.78, 0.02), (0, L, 0.0)],
                         [0.56, 0.66, 0.5, 0.2])
        flat = S.scale(spindle, (1.5, 1.0, 1.0))
        stump = S.place(flat, (0, 0.35, 0), S.frame_from(fa_dir, (0, 0, 1)))
        parts.append((stump, 0.55))
        anchors["forearm_end"] = v3(0, 0.35, 0) + fa_dir * (L + 0.2)
    else:
        parts.append((S.ellipsoid((0, 0.05, 0.0), (0.92, 0.55, 0.52)), 0.4))
    # ---------------------------------------------------------------- assemble
    # fingers blend with the palm only (never with each other, which would make a mitten)
    palm_all = S.blend(parts[0][0], parts[1:])
    DEBUG_PARTS.clear()
    DEBUG_PARTS.update({"palm": palm_all, "fingers": finger_sdfs, "thumb": thumb_sdf})
    # "fuse_k" > 0 joins touching fingers along their length (stylised closed hand, grooves)
    fingers = S.union(*finger_sdfs, k=pose.get("fuse_k", 0.0))
    with_fingers = S.union(palm_all, fingers, k=pose.get("finger_k", 0.30))
    with_thumb = S.union(palm_all, thumb_sdf, k=pose.get("thumb_k", 0.42))
    body = S.union(with_fingers, with_thumb)
    for c, k in cuts:
        body = S.subtract(body, c, k)
    anchors["wrist_center"] = v3(0, 0, 0)
    anchors["forearm_dir"] = fa_dir
    return body, anchors


def _surface_z(f, x, y, z_lo=-0.2, z_hi=2.0):
    """Height of the dorsal surface of ``f`` above (x, y) by bisection along +Z."""
    lo, hi = z_lo, z_hi
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        d = f(np.array([[x, y, mid]]))[0]
        if d < 0:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def ray_hit(f, origin, direction, t_max, steps=200):
    """First surface crossing of f along origin + t*direction (either sign change)."""
    o = v3(origin)
    dvec = normalize(direction)
    ts = np.linspace(0.0, t_max, steps)
    d = f(o[None, :] + ts[:, None] * dvec[None, :])
    idx = np.flatnonzero(np.sign(d[:-1]) != np.sign(d[1:]))
    if len(idx) == 0:
        raise ValueError("ray does not cross the surface")
    lo, hi = ts[idx[0]], ts[idx[0] + 1]
    s_lo = np.sign(d[idx[0]])
    for _ in range(50):
        mid = 0.5 * (lo + hi)
        if np.sign(f((o + mid * dvec)[None, :])[0]) == s_lo:
            lo = mid
        else:
            hi = mid
    return o + 0.5 * (lo + hi) * dvec
