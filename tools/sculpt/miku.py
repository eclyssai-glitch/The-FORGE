"""MIKU -- original sacred statue (SDF). Brancusi-like serenity, art-deco marble: ~9 heads tall,
oval head bowed forward, long neck, closed eyes suggested by relief, no detailed mouth, discreet
dignified torso, long arms opening forward and down, slender joined-finger hands, light
contrapposto, and from the waist a long bell gown whose hem ends open with a soft irregular
edge (it dissolves into dust in the shader/particles). No feet, no legs, no loose hair: only a
smooth gathered hair cap that flows back into a short tapering knot where runtime ribbons start.

Mesh frame: +Y up, +Z front, origin = waist centre. Head top ~ +1.83, hem ~ -4.15 (6.0 tall).
"""
from __future__ import annotations

import math

import numpy as np

import sdf as S
from hand import build_hand, ray_hit
from sdf import v3, normalize, smoothstep

# ------------------------------------------------------------------ global pose
R_CHEST = S.rot_z(0.045) @ S.rot_y(0.06) @ S.rot_x(0.05)   # left shoulder up, turn, lean forward
R_PELVIS = S.rot_z(-0.05)                                   # right hip up (weight leg)
ATLAS = v3(0.0, 1.30, -0.035)                             # top of the neck, head pivot
R_HEAD = S.rot_x(0.30) @ S.rot_z(-0.07) @ S.rot_y(0.07)    # bowed, tilted, slightly turned
HEAD_C = v3(0.0, 0.20, 0.075)                              # head centre in the atlas frame

HEM_Y = -4.15
GOWN_TOP = 0.03


# ------------------------------------------------------------------ head
def _head_mass(p):
    cran = S.ellipsoid((0, 0.07, -0.035), (0.205, 0.245, 0.25))(p)
    face = S.ellipsoid((0, -0.045, 0.04), (0.163, 0.235, 0.195))(p)
    d = S.smin(cran, face, 0.12)
    d = S.smin(d, S.ellipsoid((0, -0.19, 0.075), (0.118, 0.10, 0.118))(p), 0.10)
    d = S.smin(d, S.sphere((0, -0.235, 0.145), 0.05)(p), 0.07)
    # jawline: gonion -> chin, so the profile has a jaw and the neck sits behind the face
    for s in (-1.0, 1.0):
        d = S.smin(d, S.capsule((s * 0.118, -0.145, -0.055), (s * 0.04, -0.258, 0.135), 0.036)(p), 0.05)
    return d


S.with_bound(_head_mass, (0, 0, 0), 0.42)


def _head():
    """Head in head-centre coordinates (+Z = face)."""
    base = _head_mass
    feats = []
    for s in (-1.0, 1.0):
        # shallow socket, then a large almond lid (closed) that nearly fills it
        feats.append(("sub", S.ellipsoid((s * 0.072, 0.010, 0.232), (0.064, 0.036, 0.046)), 0.06))
        feats.append(("add", S.ellipsoid((s * 0.071, 0.004, 0.192), (0.060, 0.030, 0.034),
                                         S.rot_z(-s * 0.12)), 0.022))
        # closed-lid line: a faint arc along the lower edge of the lid
        arc = S.tube([(s * 0.026, -0.006, 0.212), (s * 0.070, -0.018, 0.221),
                      (s * 0.116, -0.004, 0.197)], [0.0045, 0.0055, 0.0045])
        feats.append(("sub", arc, 0.012))
        feats.append(("add", S.ellipsoid((s * 0.078, 0.064, 0.192), (0.074, 0.02, 0.026),
                                         S.rot_z(s * 0.12)), 0.06))
        feats.append(("add", S.ellipsoid((s * 0.1, -0.045, 0.118), (0.07, 0.05, 0.06)), 0.12))
        feats.append(("add", S.sphere((s * 0.019, -0.08, 0.244), 0.014), 0.018))
    feats.append(("add", S.round_cone((0, 0.06, 0.222), (0, -0.062, 0.272), 0.016, 0.02), 0.03))
    feats.append(("add", S.sphere((0, -0.068, 0.263), 0.022), 0.02))
    feats.append(("add", S.ellipsoid((0, -0.152, 0.2), (0.042, 0.028, 0.03)), 0.04))

    return S.sculpt(base, feats)


# gathered hair: a compact bun on the back of the skull; the runtime ribbons leave from its
# upper-back end, heading up and back (tangent 55 degrees above the horizontal, world)
BUN_C = v3(0.0, 0.07, -0.25)
BUN_R = (0.125, 0.105, 0.095)
_ROOT_WORLD = normalize((0.0, math.sin(math.radians(55.0)), -math.cos(math.radians(55.0))))
ROOT_DIR = R_HEAD.T @ _ROOT_WORLD   # the same direction in head coordinates
KNOT_T = (0.0, 0.07)


def _knot_points():
    """Two points along the ribbon exit direction starting at the bun centre (for anchors)."""
    return [tuple(BUN_C + ROOT_DIR * t) for t in KNOT_T]


def _hair():
    """Smooth hair gathered close to the skull: a soft hairline (no ledge) and a broad volume
    swept back where the runtime ribbons start."""
    n_top = normalize((0.0, 0.8, -0.6))
    c_top = float(np.dot(v3(0, 0.155, 0.2), n_top))
    bun = S.ellipsoid(BUN_C, BUN_R, S.rot_x(-0.35))
    flow = S.round_cone(BUN_C - ROOT_DIR * 0.02, BUN_C + ROOT_DIR * 0.075, 0.085, 0.06)
    knot = S.union(bun, flow, k=0.03)

    def cap(p):
        # hair region = above the forehead/temple line  OR  behind the ear and above the nape;
        # the union draws the natural hairline curve around the (unmodelled) ear
        top = (p @ n_top) - c_top - 0.5 * p[:, 0] ** 2
        # behind the ear: an arc that comes forward above and below the ear, closed at the nape
        back = -p[:, 2] - 0.035 + 1.1 * (p[:, 1] + 0.02) ** 2
        back = S.smin(back, (p[:, 1] + 0.2) * 0.8, 0.04)
        s = S.smax(top, back, 0.07)
        thick = 0.017 * smoothstep(-0.008, 0.045, s)
        d = _head_mass(p) - thick
        return S.smin(d, knot(p), 0.05)
    return S.with_bound(cap, (0, 0.05, -0.15), 0.72)


def _head_and_hair():
    head = _head()
    hair = _hair()

    return S.union(head, hair, k=0.006)


# ------------------------------------------------------------------ torso (neutral frame)
def _torso(skip=()):
    parts = []
    base = S.ellipsoid((0, 0.55, -0.025), (0.29, 0.35, 0.185))
    named = [
        ("chest", S.ellipsoid((0, 0.74, 0.0), (0.32, 0.14, 0.165)), 0.12),
        ("belly", S.ellipsoid((0, 0.20, 0.0), (0.235, 0.27, 0.158)), 0.18),
        ("waist", S.ellipsoid((0, -0.05, -0.005), (0.212, 0.14, 0.15)), 0.12),
        ("yoke", S.ellipsoid((0, 0.87, -0.035), (0.40, 0.10, 0.14)), 0.12),
    ]
    for s in (-1.0, 1.0):
        named += [
            ("deltoid", S.ellipsoid((s * 0.43, 0.80, -0.03), (0.11, 0.13, 0.115)), 0.10),
            ("trapezius", S.round_cone((s * 0.06, 1.05, -0.07), (s * 0.37, 0.87, -0.05), 0.08, 0.062), 0.14),
            ("scapula", S.ellipsoid((s * 0.16, 0.66, -0.15), (0.12, 0.14, 0.05)), 0.10),
            ("breast", S.ellipsoid((s * 0.125, 0.50, 0.11), (0.095, 0.086, 0.074)), 0.13),
            ("clavicle", S.capsule((s * 0.04, 0.915, 0.10), (s * 0.37, 0.905, -0.005), 0.018), 0.05),
            ("scm", S.capsule((s * 0.09, 1.33, -0.03), (s * 0.042, 0.97, 0.09), 0.024), 0.07),
        ]
    named.append(("neck", S.round_cone((0, 0.86, -0.05), ATLAS, 0.12, 0.102), 0.10))
    parts = [(g, k) for n, g, k in named if n not in skip]
    torso = S.blend(base, parts)
    if "spine" not in skip:
        torso = S.subtract(torso, S.capsule((0, 0.08, -0.188), (0, 0.80, -0.212), 0.02), 0.07)
    return torso


# ------------------------------------------------------------------ arms and hands
ARMS = {
    # side: shoulder, elbow, wrist (neutral frame); +1 = her left (+X)
    1.0: ((0.42, 0.79, -0.03), (0.74, 0.02, 0.30), (1.04, -0.46, 0.92)),
    -1.0: ((-0.42, 0.79, -0.03), (-0.72, 0.06, 0.26), (-1.03, -0.39, 0.88)),
}
HAND_SCALE = 0.56 / 7.0
POSE_MIKU = {
    "arch": 0.22,
    "fingers": {
        "index": (-0.035, 0.04, (0.10, 0.16, 0.10)),
        "middle": (0.0, 0.0, (0.13, 0.19, 0.12)),
        "ring": (0.025, -0.03, (0.17, 0.22, 0.13)),
        "little": (0.06, -0.07, (0.22, 0.26, 0.15)),
    },
    "thumb": {"cmc": (0.80, 0.95, -0.28), "dir": (0.42, 0.85, -0.30), "dorsal": (0.5, -0.1, 0.9),
              "flex": (0.12, 0.16)},
    "finger_k": 0.22,
    "thumb_k": 0.35,
    "fuse_k": 0.28,
    "mcp_squeeze": 0.9,
    "nails": False,
}


def _hand_frame(side):
    sh, el, wr = (v3(x) for x in ARMS[side])
    d = normalize(wr - el)
    y = normalize(d + v3(0.08 * side, -0.38, 0.0))            # wrist droops gracefully
    palm = normalize(v3(0.62 * side, -0.72, 0.18))            # palm faces out and down
    z = -palm
    return S.frame_from(y, z), wr


def _arms():
    fs = []
    hand_local, h_anchors = build_hand(POSE_MIKU, detail=False, forearm=False)
    hand_small = S.scale(hand_local, HAND_SCALE)
    anchors = {}
    for side in (1.0, -1.0):
        sh, el, wr = (v3(x) for x in ARMS[side])
        up = S.tube([sh, sh + (el - sh) * 0.4, el], [0.10, 0.086, 0.064])
        fore = S.tube([el, el + (wr - el) * 0.28, wr], [0.066, 0.071, 0.046])
        frame, origin = _hand_frame(side)
        if side > 0:
            hand = S.place(hand_small, origin, frame)
        else:
            hand = S.place(S.mirror_x(hand_small), origin, frame)
        fs.append((up, fore, hand))
        anchors[side] = (frame, origin)
    return fs, anchors


# ------------------------------------------------------------------ gown (pelvis frame)
FOLDS = ((3, 0.25, 0.9, 1.4), (5, 0.40, 0.4, 1.1), (8, 0.30, 2.2, -0.8), (13, 0.16, 4.1, 1.6),
         (21, 0.07, 1.0, 0.9))


def _gown_radius(t, theta, y):
    hips = smoothstep(0.0, 0.14, t) * (1.0 - 0.3 * smoothstep(0.14, 0.55, t))
    base = 0.208 + 0.17 * hips + 0.23 * t + 0.64 * t ** 4.2
    amp = 0.014 + 0.10 * t ** 1.4
    fold = np.zeros_like(t)
    for n, a, ph, tw in FOLDS:
        fold += a * np.sin(n * theta + ph + tw * t * 3.0)
    band = 0.012 * np.exp(-((y + 0.075) / 0.028) ** 2)
    dth = np.angle(np.exp(1j * (theta - 0.55)))
    thigh = 0.045 * np.exp(-(dth / 0.5) ** 2) * smoothstep(-0.5, -1.4, y) * (1 - smoothstep(-2.3, -3.2, y))
    knee = 0.025 * np.exp(-(dth / 0.45) ** 2 - ((y + 2.05) / 0.3) ** 2)
    return base + amp * fold + band + thigh + knee


def _gown():
    def f(p):
        q = p @ R_PELVIS
        y = q[:, 1]
        t = np.clip(-y / -HEM_Y, 0.0, 1.0)
        cx = 0.03 * t
        cz = 0.02 - 0.34 * t * t
        ax = 1.0 + 0.16 * smoothstep(0.0, 0.12, t) * (1.0 - t) ** 2
        az = 0.73 + 0.27 * np.sqrt(t)
        dx = (q[:, 0] - cx) / ax
        dz = (q[:, 2] - cz) / az
        rho = np.sqrt(dx * dx + dz * dz)
        theta = np.arctan2(dx, dz)
        R = _gown_radius(t, theta, y)
        e = 1e-3
        Ry = (_gown_radius(np.clip(-(y + e) / -HEM_Y, 0, 1), theta, y + e) - R) / e
        Rt = (_gown_radius(t, theta + e, y) - R) / e
        g = np.sqrt(1.0 + Ry * Ry + (Rt / np.maximum(rho, 0.05)) ** 2)
        d_out = (rho - R) * np.minimum(ax, az) / g
        bell = S.smax(d_out, y - GOWN_TOP, 0.012)
        hem = (HEM_Y + 0.14 * np.cos(theta) + 0.07 * np.sin(2 * theta + 0.6)
               + 0.045 * np.sin(3 * theta + 1.9) + 0.025 * np.sin(5 * theta + 0.4))
        th = 0.030 + 0.012 * (1.0 - t)
        # hollow bell: the cavity follows the outer surface (fabric thickness th) and closes in a
        # parabolic dome around y = -1.7 (hard max: no thin smooth-max sheets)
        dome = (y - (-1.7 - 0.9 * rho * rho)) * 0.6
        cavity = np.maximum(d_out + th, dome)
        d = S.smax(bell, -cavity, 0.012)
        return S.smax(d, hem - y, 0.022)
    return S.with_bound(f, (0, -2.1, -0.3), 2.75)


# ------------------------------------------------------------------ assembly
def build():
    torso = _torso()
    head = S.place(_head_and_hair(), ATLAS + R_HEAD @ HEAD_C, R_HEAD)
    arms, hand_frames = _arms()
    gown = _gown()

    ops = [("add", head, 0.035)]
    for up, fore, hand in arms:
        ops.append(("add", S.union(up, fore, hand, k=0.028), 0.06))
    upper = S.sculpt(torso, ops)
    body = S.union(S.place(upper, (0, 0, 0), R_CHEST), gown, k=0.05)

    anchors = {"hand_frames": hand_frames}
    return body, anchors


def _to_world_upper(p):
    return R_CHEST @ p


def _head_point(local):
    return _to_world_upper(ATLAS + R_HEAD @ (HEAD_C + local))


def metadata(f, anchors):
    """Anchors in mesh space for docs/contracts (see docs/PROCEDURAL.md)."""
    head_c = _head_point(v3(0, 0, 0))
    up_dir = normalize(_to_world_upper(R_HEAD @ v3(0, 1, 0)))
    head_top = ray_hit(f, head_c, up_dir, 0.6)
    face_dir = normalize(_to_world_upper(R_HEAD @ normalize(v3(0, 0.62, 1.0))))
    forehead = ray_hit(f, head_c, face_dir, 0.6)
    kp = _knot_points()
    knot_tip = _head_point(v3(kp[-1]))
    knot_prev = _head_point(v3(kp[-2]))
    tangent = normalize(knot_tip - knot_prev)
    hair_root = ray_hit(f, knot_tip - tangent * 0.02, tangent, 0.3)
    palms = {}
    for side, key in ((1.0, "palm_left"), (-1.0, "palm_right")):
        frame, origin = anchors["hand_frames"][side]
        inside = _to_world_upper(origin + frame @ (v3(0, 2.05, -0.05) * HAND_SCALE))
        normal_guess = _to_world_upper(frame @ v3(0, 0, -1))
        palms[key] = ray_hit(f, inside, normal_guess, 0.2)
        palms[key + "_normal"] = S.gradient(f, palms[key][None, :], 0.003)[0]
    chest = ray_hit(f, _to_world_upper(v3(0, 0.62, 0.0)), _to_world_upper(v3(0, 0, 1)), 0.5)
    # hem ring: outer gown surface just above the (irregular) hem line, averaged
    pts = []
    for th in np.linspace(0, 2 * math.pi, 72, endpoint=False):
        hem = (HEM_Y + 0.14 * math.cos(th) + 0.07 * math.sin(2 * th + 0.6)
               + 0.045 * math.sin(3 * th + 1.9) + 0.025 * math.sin(5 * th + 0.4))
        c = R_PELVIS @ v3(0.03, hem + 0.03, 0.02 - 0.34)
        dirv = R_PELVIS @ v3(math.sin(th), 0, math.cos(th))
        pts.append(ray_hit(f, c + dirv * 2.0, -dirv, 2.0))
    pts = np.array(pts)
    hem_center = pts.mean(axis=0)
    hem_radius = float(np.mean(np.linalg.norm((pts - hem_center)[:, [0, 2]], axis=1)))
    from bake_all import r
    return {
        "origin": "waist centre",
        "frame": "+Y up, +Z front (MIKU faces +Z); her left hand is on +X",
        "anchors": {
            "head_top": r(head_top),
            "forehead": r(forehead),
            "hair_root": r(hair_root),
            "hair_root_tangent": r(tangent),
            "palm_left": r(palms["palm_left"]),
            "palm_left_normal": r(palms["palm_left_normal"]),
            "palm_right": r(palms["palm_right"]),
            "palm_right_normal": r(palms["palm_right_normal"]),
            "chest": r(chest),
            "gown_hem_center": r(hem_center),
            "gown_hem_radius": round(hem_radius, 4),
        },
    }
