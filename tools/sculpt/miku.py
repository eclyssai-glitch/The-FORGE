"""MIKU -- original sacred statue (SDF), votive statuary (korai, art-deco marble), never a
mannequin: oval head bowed forward, long neck, closed eyes as convex lid masses under a brow
plane, lips as volumes; a sculpted hair MASS combed back in wavy locks into a coiled knot high
on the back of the head, whose short tail is where the runtime ribbons of light take over;
sloping shoulders with clavicles; a draped bodice (cowl swags, broad pleats, no modelled breasts)
flowing without a waistband into a long bell gown whose hem ends open with a soft irregular edge
(it dissolves into dust in the shader/particles); long arms opening forward and down, slender
hands, light contrapposto. No feet, no legs.

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
GOWN_TOP = 0.22


# ------------------------------------------------------------------ head
# Head frame: origin = head centre, +Y = crown, +Z = face. Chin -> crown ~0.53 u (1 cm ~ 0.023 u),
# eyes on the mid line (y ~ 0). The face is a smooth relief (height field) over an egg-shaped
# oval: every feature is a soft Gaussian swell or hollow, so the whole face reads as one
# continuous form (Brancusi, "Sleeping Muse") with no crease anywhere.

def egg(c, r, taper, chin=0.0):
    """Ellipsoid whose x radius shrinks towards -Y (taper > 0) and narrows quadratically in its
    lower half (``chin``): an egg / face oval with a delicate chin."""
    c = v3(c)
    r = v3(r)

    def f(p):
        q = p - c
        t = q[:, 1] / r[1]
        sx = np.clip(1.0 + taper * t - chin * np.clip(-t, 0.0, 1.0) ** 2, 0.45, 1.4)
        rr = np.empty_like(q)
        rr[:, 0] = r[0] * sx
        rr[:, 1] = r[1]
        rr[:, 2] = r[2]
        k0 = np.sqrt(np.sum((q / rr) ** 2, axis=1))
        k1 = np.sqrt(np.sum((q / (rr * rr)) ** 2, axis=1))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-12)
    return S.with_bound(f, c, float(np.max(r)) * 1.4)


def _g(x, y, cx, cy, sx, sy):
    return np.exp(-((x - cx) / sx) ** 2 - ((y - cy) / sy) ** 2)


def face_relief(x, y):
    """Height (z) of the face surface above the point (x, y) of the head frame."""
    ax = np.abs(x)
    # base: gently arched profile; elliptic cross-section whose half-width follows the face oval,
    # so the front plane turns into the sides without a mask edge
    z = 0.214 - 0.5 * (y + 0.02) ** 2
    # (every clamp is smooth: a kink here would show as a seam in the gradient normals)
    t = (y + 0.03) / 0.27
    t = 0.97 * np.tanh(t / 0.97)
    tn = 0.5 * (-t + np.sqrt(t * t + 0.01))                     # smooth max(-t, 0)
    b = 1.05 * 0.15 * (1.0 + 0.08 * t - 0.42 * tn * tn) * np.sqrt(np.maximum(1.0 - t * t, 0.0))
    b = 0.5 * (b + 0.08 + np.sqrt((b - 0.08) ** 2 + 0.02 ** 2))  # smooth max(b, 0.08)
    depth = 0.14 + 0.05 * smoothstep(0.0, 0.2, y)                # rounder forehead
    z = z - depth * (np.cosh(2.5 * ax / b) - 1.0) / (math.cosh(2.5) - 1.0)
    # forehead: a full, smooth dome
    z = z + 0.006 * _g(x, y, 0.0, 0.14, 0.11, 0.08)
    # votive-statue brow: one continuous plane from the forehead into the bridge of the nose
    # (Greek profile), and the upper orbital rim as a MASS -- a ridge that overhangs the eye and
    # throws a soft shadow onto the lid, never a drawn line
    z = z + 0.009 * _g(x, y, 0.0, 0.05, 0.026, 0.035)           # glabella -> bridge
    arc_y = 0.052 - 2.2 * (ax - 0.062) ** 2
    rim = np.exp(-((ax - 0.064) / 0.056) ** 2 - ((y - arc_y) / 0.02) ** 2)
    z = z + 0.011 * rim
    z = z - 0.009 * _g(ax, y, 0.145, 0.06, 0.03, 0.05)          # temples
    # eye: the socket sinks under the brow, the eyeball swells under the closed upper lid and the
    # lid itself is a convex almond MASS whose lower edge overhangs the (receding) lower lid
    z = z - 0.030 * _g(ax, y, 0.066, 0.004, 0.046, 0.03)
    z = z + 0.011 * _g(ax, y, 0.066, -0.002, 0.034, 0.022)      # eyeball under the lid
    d = (ax - 0.066) / 0.039
    span = smoothstep(0.0, 1.0, np.clip(1.0 - d * d, 0.0, 1.0))
    y_c = -0.002 + 0.05 * (ax - 0.066)                          # canthi: outer a touch higher
    y_up = y_c + 0.024 * span                                    # top of the lid mass
    y_lash = y_c - 0.010 * span                                 # lid edge (lash line)
    lid = smoothstep(-0.008, 0.016, y_up - y) * smoothstep(-0.006, 0.009, y - y_lash)
    z = z + 0.012 * lid * span
    z = z + 0.005 * _g(ax, y, 0.068, y_c - 0.027, 0.03, 0.009)  # lower lid roll
    # cheekbones and soft cheeks
    z = z + 0.013 * _g(ax, y, 0.1, -0.045, 0.045, 0.035)
    z = z + 0.006 * _g(ax, y, 0.07, -0.1, 0.05, 0.05)
    z = z + 0.005 * _g(ax, y, 0.075, -0.09, 0.04, 0.05)
    # nose: a straight ridge continuing the brow plane to a small rounded tip
    u = (0.03 - y) / 0.10                                      # 0 = root, 1 = tip
    h_ridge = np.where(u < 0.0, 0.006 * np.exp(-(u / 0.3) ** 2),
                       np.where(u <= 1.0, 0.006 + 0.038 * np.clip(u, 0, 1) ** 1.25,
                                0.044 * np.exp(-((u - 1.0) / 0.21) ** 2)))
    w_ridge = 0.014 + 0.009 * np.clip(u, 0.0, 1.1) ** 2 + 0.04 * np.clip(-u, 0.0, 1.0)
    z = z + h_ridge * np.exp(-(x / w_ridge) ** 2)
    z = z + 0.009 * _g(ax, y, 0.021, -0.08, 0.014, 0.012)     # nostril wings
    # mouth: lips as full MASSES (upper lip with its bow, fuller lower lip), the parting only
    # where the two masses meet; corners tucked in; a soft hollow under the lower lip
    z = z + 0.006 * _g(x, y, 0.0, -0.13, 0.05, 0.035)          # muzzle
    z = z - 0.002 * _g(ax, y, 0.006, -0.108, 0.004, 0.01)       # philtrum
    y_up_lip = -0.123 + 0.004 * np.exp(-((ax - 0.011) / 0.008) ** 2)
    # (lip heights taper towards the corners: rounded, never a box)
    z = z + 0.011 * np.exp(-(x / 0.027) ** 2 - ((y - y_up_lip) / (0.0085 * (1.0 - 0.45 * (x / 0.04) ** 2))) ** 2)
    z = z - 0.0025 * _g(x, y, 0.0, -0.1345, 0.028, 0.0035)      # parting
    z = z + 0.013 * np.exp(-(x / 0.023) ** 2 - ((y + 0.146) / (0.0105 * (1.0 - 0.5 * (x / 0.035) ** 2))) ** 2)
    z = z - 0.004 * _g(ax, y, 0.034, -0.136, 0.009, 0.011)      # mouth corners
    z = z - 0.004 * _g(x, y, 0.0, -0.17, 0.035, 0.011)          # under the lower lip
    # small, defined chin; below the jaw line the relief turns under (submental plane)
    z = z + 0.017 * _g(x, y, 0.0, -0.21, 0.034, 0.026)
    y_jaw = -0.255 + 3.0 * x * x
    z = z - 12.0 * np.clip(y_jaw - y, 0.0, None) ** 2
    return z


FACE_OVAL = egg((0, -0.03, -0.04), (0.15, 0.27, 0.4), 0.08, 0.42)


def _face_solid(p):
    x, y = p[:, 0], p[:, 1]
    e = 1e-3
    z0 = face_relief(x, y)
    zx = (face_relief(x + e, y) - z0) / e
    zy = (face_relief(x, y + e) - z0) / e
    d = (p[:, 2] - z0) / np.sqrt(1.0 + zx * zx + zy * zy)
    d = S.smax(d, FACE_OVAL(p), 0.045)
    # the mask only reaches back to the jaw angle; below the ear the cut slopes forward, so the
    # jaw line rises from the chin towards the ear instead of hanging as a jowl
    lo = -0.1 - p[:, 1]
    z_cut = -0.06 + 0.75 * 0.5 * (lo + np.sqrt(lo * lo + 0.03 ** 2))
    return S.smax(d, (z_cut - p[:, 2]) / 1.25, 0.05)


S.with_bound(_face_solid, (0, -0.03, 0.05), 0.36)
_CRANIUM = S.ellipsoid((0, 0.045, -0.035), (0.163, 0.216, 0.205))
_FOREHEAD = S.ellipsoid((0, 0.13, 0.06), (0.13, 0.12, 0.14))


def _skull_raw(p):
    d = S.smin(_CRANIUM(p), _FOREHEAD(p), 0.05)
    return S.smin(d, _face_solid(p), 0.06)


_skull = S.with_bound(_skull_raw, (0, 0, 0), 0.42)


def _face():
    """Extra volumes on top of the skull (none: the relief carries every feature)."""
    return []


# Sculpted hair (votive statuary): a real MASS over the skull, not a painted cap. Combed back
# from a soft rolled hairline, it swells over the crown and covers the ears in two full bands,
# is carved into broad wavy locks (grooves between them, a few finer strand lines inside), and
# gathers into a coiled knot high on the back of the head. The knot ends in a short tapering
# tail -- the root where the runtime ribbons of light take over (`hair_root`), heading up and
# back (ROOT_ELEV above horizontal, world).
CHIG_C = v3(0.0, 0.085, -0.232)
CHIG_R = (0.105, 0.088, 0.085)
ROOT_ELEV = 50.0
_ROOT_WORLD = normalize((0.0, math.sin(math.radians(ROOT_ELEV)), -math.cos(math.radians(ROOT_ELEV))))
ROOT_DIR = R_HEAD.T @ _ROOT_WORLD   # the same direction in head coordinates
KNOT_T = (0.05, 0.13)
TAIL_LEN = 0.13
HAIR_LOCKS = 21        # broad locks around the head (meridians to the knot)
HAIR_LOCK_AMP = 0.0095 # lock relief (ridge above groove)
HAIR_STRAND_AMP = 0.0018


def _knot_points():
    """Two points along the ribbon exit direction starting at the knot centre (for anchors)."""
    return [tuple(CHIG_C + ROOT_DIR * t) for t in KNOT_T]


HAIRLINE = (  # azimuth from the face (rad) -> hairline height (head frame)
    (0.0, 0.5, 0.9, 1.25, 1.55, 1.9, 2.5, math.pi),
    (0.172, 0.16, 0.118, 0.045, -0.05, -0.105, -0.15, -0.165),
)


def _hair_region(p):
    """> 0 inside the hair: above a hairline that runs over the forehead, down in front of the
    (unmodelled) ear to its lobe, and back to the nape; the hair covers the whole ear."""
    th = np.abs(np.arctan2(p[:, 0], p[:, 2]))
    # near the vertical axis the azimuth is undefined: fall back to a constant height there
    w = smoothstep(0.03, 0.12, np.hypot(p[:, 0], p[:, 2]))
    return p[:, 1] - (w * np.interp(th, *HAIRLINE) + (1.0 - w) * 0.0)


def _knot():
    """Coiled knot + tail along ROOT_DIR, with a spiral twist carved in (reads as wound hair)."""
    tail_end = CHIG_C + ROOT_DIR * TAIL_LEN
    body = S.union(S.ellipsoid(CHIG_C, CHIG_R),
                   S.round_cone(CHIG_C + ROOT_DIR * 0.02, tail_end, 0.072, 0.032), k=0.05)
    ax = normalize(ROOT_DIR)
    b1 = normalize(np.cross(ax, (1.0, 0.0, 0.0)))
    b2 = np.cross(ax, b1)

    def f(p):
        d = body(p)
        q = p - CHIG_C
        t = q @ ax
        psi = np.arctan2(q @ b1, q @ b2)
        twist = np.cos(3.0 * psi + t * 42.0)
        return d - 0.0045 * twist
    return S.with_bound(f, CHIG_C + ROOT_DIR * 0.06, 0.24)


def _hair():
    knot = _knot()
    # locks: meridians around an axis through the face and the knot, so they sweep back from the
    # hairline and converge under the knot
    pole = normalize(CHIG_C - v3(0, -0.02, 0.3))
    e1 = normalize(np.cross(pole, (1.0, 0.0, 0.0)))
    e2 = np.cross(pole, e1)

    def cap(p):
        s = _hair_region(p)
        # a decisive but soft roll at the hairline: the mass stands off the forehead
        ramp = smoothstep(-0.012, 0.075, s)
        th = np.abs(np.arctan2(p[:, 0], p[:, 2]))
        over_ear = smoothstep(0.85, 1.45, th) * (1.0 - smoothstep(2.2, 2.8, th))
        over_ear = over_ear * smoothstep(-0.2, -0.05, p[:, 1]) * (1.0 - smoothstep(0.08, 0.2, p[:, 1]))
        crown = smoothstep(-0.05, 0.2, p[:, 1])
        back = smoothstep(0.1, -0.2, p[:, 2])
        thick = (0.02 + 0.02 * crown + 0.03 * over_ear + 0.012 * back) * ramp
        q = p - CHIG_C
        a1, a2 = q @ e1, q @ e2
        ra = np.sqrt(a1 * a1 + a2 * a2)
        phi = np.arctan2(a1, a2)
        # distance travelled from the face towards the knot (angle about the knot centre)
        along = np.arccos(np.clip(-(q @ pole) / np.maximum(np.linalg.norm(q, axis=1), 1e-6), -1, 1))
        wav = phi + 0.1 * np.sin(6.0 * along + 2.0 * phi)
        u = wav * HAIR_LOCKS / (2.0 * math.pi)
        fr = u - np.floor(u)
        ridge = 1.0 - (2.0 * fr - 1.0) ** 2
        strands = 0.5 - 0.5 * np.cos(2.0 * math.pi * 3.0 * u)
        fade = smoothstep(-0.005, 0.06, s) * smoothstep(0.05, 0.15, ra)
        relief = (HAIR_LOCK_AMP * (ridge - 0.6) - HAIR_STRAND_AMP * strands) * fade
        d = _skull(p) - thick - relief
        return S.smin(d, knot(p), 0.06)
    return S.with_bound(cap, (0, 0.02, -0.08), 0.62)


def _head_and_hair():
    return S.sculpt(_hair(), _face())


# ------------------------------------------------------------------ torso (neutral frame)
def _torso(skip=()):
    """Neutral-frame torso: long neck, sloping shoulders (the trapezius falls in a long line from
    the neck to a low, narrow shoulder), visible clavicles with the hollow above them, no modelled
    breasts (the draped bodice covers the chest as one plane of fabric)."""
    parts = []
    base = S.ellipsoid((0, 0.55, -0.025), (0.28, 0.35, 0.18))
    named = [
        ("chest", S.ellipsoid((0, 0.70, -0.005), (0.29, 0.15, 0.16)), 0.12),
        ("belly", S.ellipsoid((0, 0.20, 0.0), (0.228, 0.27, 0.155)), 0.18),
        ("waist", S.ellipsoid((0, -0.05, -0.005), (0.208, 0.14, 0.148)), 0.12),
        ("yoke", S.ellipsoid((0, 0.82, -0.04), (0.33, 0.09, 0.13)), 0.12),
    ]
    for s in (-1.0, 1.0):
        named += [
            ("deltoid", S.ellipsoid((s * 0.405, 0.75, -0.03), (0.105, 0.125, 0.11)), 0.10),
            ("trapezius", S.round_cone((s * 0.05, 1.07, -0.07), (s * 0.35, 0.83, -0.045), 0.078, 0.05), 0.16),
            ("scapula", S.ellipsoid((s * 0.16, 0.64, -0.15), (0.12, 0.14, 0.05)), 0.10),
            ("clavicle", S.round_cone((s * 0.035, 0.895, 0.105), (s * 0.34, 0.845, -0.005), 0.021, 0.017), 0.035),
            ("scm", S.capsule((s * 0.085, 1.33, -0.03), (s * 0.038, 0.96, 0.095), 0.024), 0.06),
        ]
    named.append(("neck", S.round_cone((0, 0.86, -0.05), ATLAS, 0.115, 0.1), 0.10))
    parts = [(g, k) for n, g, k in named if n not in skip]
    torso = S.blend(base, parts)
    if "hollows" not in skip:
        for s in (-1.0, 1.0):   # supraclavicular hollows: the clavicle reads as a bone
            torso = S.subtract(torso, S.ellipsoid((s * 0.17, 0.935, 0.025), (0.075, 0.02, 0.03)), 0.07)
    if "spine" not in skip:
        torso = S.subtract(torso, S.capsule((0, 0.08, -0.183), (0, 0.80, -0.207), 0.02), 0.07)
    return torso


# draped bodice: one plane of cloth from the shoulders to the waist (Greek peplos, abstracted);
# broad pleats fan from the shoulders and converge on the waist, where the fabric flows into
# the skirt with no band. Neckline: a soft scoop below the clavicles; bare arms and shoulder caps.
BODICE_T = 0.011
PLEAT_AMP = 0.017
PLEATS = 7


def _bodice(torso):
    drape = S.blend(S.ellipsoid((0, 0.43, 0.012), (0.245, 0.4, 0.172)),
                    [(S.ellipsoid((0, 0.66, -0.01), (0.285, 0.16, 0.17)), 0.12)])

    def f(p):
        x, y, z = p[:, 0], p[:, 1], p[:, 2]
        ax = np.abs(x)
        d0 = S.smin(torso(p), drape(p), 0.09)
        front = smoothstep(-0.02, 0.1, z)
        # pleats: rays from a point below the waist (a little to her right, so the drape runs
        # on a diagonal from her left shoulder), fanning up towards the shoulders
        ang = np.arctan2(x + 0.06, y + 0.3)
        ph = PLEATS * ang + 0.9 * np.sin(2.3 * ang + 0.4)
        pleat = PLEAT_AMP * (0.5 + 0.5 * np.cos(ph))
        # (the pleats calm down over the chest and the shoulders: the cloth lies smooth there,
        # no stripes on the shoulder caps)
        pleat *= smoothstep(-0.12, 0.12, y) * (1.0 - 0.8 * smoothstep(0.5, 0.66, y))
        pleat *= 0.55 + 0.45 * smoothstep(-0.05, 0.12, z)
        # cowl: soft U-shaped swags hanging across the chest under the neckline
        cu = (y - 1.9 * (x - 0.02) ** 2 - 0.47) / 0.085
        swag = 0.5 + 0.5 * np.cos(2.0 * math.pi * np.clip(cu, -0.5, 2.5))
        swag *= front * smoothstep(-0.5, 0.2, cu) * (1.0 - smoothstep(1.6, 2.4, cu))
        cloth = d0 - BODICE_T - pleat - 0.013 * swag
        # coverage (< 0 inside): below the neckline (a soft scoop under the clavicles in front,
        # lower on the back); the cloth passes over the shoulder caps
        neck = 0.705 + 0.2 * smoothstep(0.04, 0.2, ax) ** 1.2
        neck = front * neck + (1.0 - front) * (0.8 + 0.1 * smoothstep(0.05, 0.2, ax))
        # (no armhole cut: the arms are blended over the cloth at the shoulder, so there is no
        # thin lip of fabric next to the skin -- such a lip closes into tunnels in the armpit)
        cover = y - neck
        return S.smax(cloth, cover, 0.012)
    body = S.with_bound(f, (0, 0.4, 0), 0.75)
    return S.union(torso, body, k=0.004)


# ------------------------------------------------------------------ arms and hands
ARMS = {
    # side: shoulder, elbow, wrist (neutral frame); +1 = her left (+X)
    1.0: ((0.40, 0.76, -0.03), (0.78, 0.0, 0.28), (1.10, -0.47, 0.90)),
    -1.0: ((-0.40, 0.76, -0.03), (-0.77, 0.04, 0.24), (-1.10, -0.40, 0.86)),
}
HAND_SCALE = 0.56 / 7.0
POSE_MIKU = {
    "arch": 0.24,
    "fingers": {  # a soft open hand: small fan, flexion growing towards the little finger
        "index": (0.12, 0.05, (0.08, 0.14, 0.09)),
        "middle": (0.01, 0.0, (0.13, 0.2, 0.12)),
        "ring": (-0.11, -0.04, (0.19, 0.26, 0.15)),
        "little": (-0.24, -0.09, (0.26, 0.32, 0.18)),
    },
    "thumb": {"cmc": (0.80, 0.95, -0.28), "dir": (0.46, 0.83, -0.32), "dorsal": (0.5, -0.1, 0.9),
              "flex": (0.14, 0.2)},
    "finger_k": 0.2,
    "thumb_k": 0.32,
    "fuse_k": 0.05,     # fingers only touch at the base: each one reads at a distance
    "mcp_squeeze": 0.97,
    "nails": False,
}


def _hand_frame(side):
    sh, el, wr = (v3(x) for x in ARMS[side])
    d = normalize(wr - el)
    y = normalize(d + v3(0.08 * side, -0.38, 0.0))            # wrist droops gracefully
    palm = normalize(v3(0.62 * side, -0.72, 0.18))            # palm faces out and down
    z = -palm
    return S.frame_from(y, z), wr


def _arm(side):
    """Upper arm and forearm with stylised anatomy: a full deltoid cap, biceps and triceps
    bellies, a soft elbow, the forearm muscles swelling below the elbow and tapering to a slim,
    flattened wrist (thin across the palm)."""
    sh, el, wr = (v3(x) for x in ARMS[side])
    a, b = el - sh, wr - el
    au, bu = normalize(a), normalize(b)
    front_a = normalize(v3(0, 0, 1) - au * au[2])
    front_b = normalize(v3(0, 0, 1) - bu * bu[2])
    fa = S.frame_from(au, front_a)
    fb = S.frame_from(bu, front_b)
    out_a = fa[:, 0] * side
    upper = S.tube([sh, sh + a * 0.3, sh + a * 0.66, el], [0.102, 0.099, 0.086, 0.07])
    upper = S.blend(upper, [
        (S.ellipsoid(sh + au * 0.1 + out_a * 0.03, (0.108, 0.2, 0.102), fa), 0.07),     # deltoid
        (S.ellipsoid(sh + a * 0.56 + front_a * 0.03, (0.066, 0.21, 0.064), fa), 0.07),  # biceps
        (S.ellipsoid(sh + a * 0.42 - front_a * 0.028, (0.07, 0.25, 0.066), fa), 0.07),  # triceps
        (S.sphere(el - front_a * 0.012, 0.064), 0.05),                                  # elbow
    ])
    palm = normalize(v3(0.62 * side, -0.72, 0.18))
    fore = S.tube([el, el + b * 0.22, el + b * 0.58, wr - bu * 0.02], [0.07, 0.086, 0.07, 0.048])
    fore = S.blend(fore, [
        (S.ellipsoid(el + b * 0.27 + fb[:, 0] * side * 0.014, (0.094, 0.27, 0.078), fb), 0.07),
        (S.ellipsoid(el + b * 0.5 - fb[:, 0] * side * 0.01, (0.07, 0.22, 0.06), fb), 0.07),
        (S.ellipsoid(wr - bu * 0.05, (0.054, 0.08, 0.037), S.frame_from(bu, palm)), 0.05),  # wrist
    ])
    return upper, fore


def _arms():
    fs = []
    hand_local, h_anchors = build_hand(POSE_MIKU, detail=False, forearm=False)
    hand_small = S.scale(hand_local, HAND_SCALE)
    anchors = {}
    for side in (1.0, -1.0):
        up, fore = _arm(side)
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
    # no waistband and no pencil-skirt hip: the skirt leaves the bodice softly and falls
    hips = smoothstep(0.0, 0.2, t) * (1.0 - 0.12 * smoothstep(0.2, 0.55, t))
    base = 0.206 + 0.13 * hips + 0.25 * t + 0.64 * t ** 4.2
    amp = 0.014 + 0.10 * t ** 1.4
    fold = np.zeros_like(t)
    for n, a, ph, tw in FOLDS:
        fold += a * np.sin(n * theta + ph + tw * t * 3.0)
    dth = np.angle(np.exp(1j * (theta - 0.55)))
    thigh = 0.045 * np.exp(-(dth / 0.5) ** 2) * smoothstep(-0.5, -1.4, y) * (1 - smoothstep(-2.3, -3.2, y))
    knee = 0.025 * np.exp(-(dth / 0.45) ** 2 - ((y + 2.05) / 0.3) ** 2)
    # above the waist the skirt dives under the bodice (smooth max(y, 0)): the two garments
    # meet in one continuous surface, never a lip or a band
    dive = 0.6 * 0.5 * (y + np.sqrt(y * y + 0.04 ** 2))
    return base + amp * fold + thigh + knee - dive


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
    torso = _bodice(_torso())
    head = S.place(_head_and_hair(), ATLAS + R_HEAD @ HEAD_C, R_HEAD)
    arms, hand_frames = _arms()
    gown = _gown()

    ops = [("add", head, 0.035)]
    for up, fore, hand in arms:
        ops.append(("add", S.union(S.union(up, fore, k=0.045), hand, k=0.028), 0.06))
    upper = S.sculpt(torso, ops)
    body = S.union(S.place(upper, (0, 0, 0), R_CHEST), gown, k=0.07)

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


def bake_spec():
    """Mesher options: a finer marching-cubes grid around the head (RadialWarp) and decimation
    importance that keeps triangles on the face and the hands, where the detail is."""
    from mesher import RadialWarp
    head_c = _head_point(v3(0, 0, 0))
    hands = [_to_world_upper(_hand_frame(s)[1]) for s in (1.0, -1.0)]

    R = R_CHEST @ R_HEAD

    def importance(P):
        q = (P - head_c[None, :]) @ R            # head frame
        r = np.linalg.norm(q, axis=1)
        w = 1.0 + 11.0 * np.exp(-(r / 0.3) ** 4)
        # the face itself is (almost) never simplified: it keeps the fine warped grid
        w += 150.0 * np.exp(-(r / 0.29) ** 8) * smoothstep(0.05, 0.14, q[:, 2])
        for hc in hands:
            w += 4.0 * np.exp(-(np.linalg.norm(P - hc[None, :], axis=1) / 0.3) ** 4)
        return w
    return {"warp": RadialWarp(head_c, 1.8, 0.34, 0.62), "importance": importance}
