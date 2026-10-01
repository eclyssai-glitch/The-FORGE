"""The two monumental auxiliary hands (GENESIS). Poses from docs/contracts/loop-04.md:
left cradles from below (palm up, shallow shell), right weaves from above (palm down, fingers
parted and softly curled at staggered depths, threads of light running between them). Each hand has its own pose; the right is not a mirror copy.

Export frame (mesh space), origin = palm centre (on the palm surface):
  left : fingers -> +X, palm normal -> +Y (up), forearm towards -X
  right: fingers -> -X, palm normal -> -Y (down), forearm towards +X
"""
from __future__ import annotations

import numpy as np

import sdf as S
from hand import build_hand, ray_hit
from sdf import v3, normalize

POSE_LEFT = {
    "arch": 0.34,
    "fingers": {  # spread (+ = towards thumb), roll (+ = cupping for index side), flex MCP/PIP/DIP
        "index": (0.08, 0.12, (0.26, 0.34, 0.20)),
        "middle": (0.015, 0.03, (0.30, 0.38, 0.22)),
        "ring": (-0.07, -0.08, (0.34, 0.42, 0.24)),
        "little": (-0.17, -0.20, (0.40, 0.46, 0.28)),
    },
    "thumb": {
        "cmc": (0.80, 0.90, -0.30),
        "dir": (0.52, 0.74, -0.44),
        "dorsal": (0.55, -0.2, 0.85),
        "flex": (0.26, 0.34),
    },
    "forearm_dir": (0.06, -1.0, -0.14),
    "finger_k": 0.30,
    "thumb_k": 0.45,
}

POSE_RIGHT = {
    # the weaver's gesture: palm down, fingers parted and softly curled at staggered depths, as
    # if threads of light were running between them (no pointing index); the thumb rests open
    # beside the index, not pinching
    "arch": 0.3,
    "fingers": {
        "index": (0.2, 0.06, (0.24, 0.3, 0.18)),
        "middle": (0.05, 0.0, (0.34, 0.4, 0.24)),
        "ring": (-0.12, -0.06, (0.27, 0.34, 0.2)),
        "little": (-0.3, -0.14, (0.4, 0.46, 0.28)),
    },
    "thumb": {
        "cmc": (0.80, 0.92, -0.34),
        "dir": (0.6, 0.72, -0.36),
        "dorsal": (0.6, -0.2, 0.78),
        "flex": (0.2, 0.26),
    },
    "forearm_dir": (-0.10, -1.0, 0.30),
    "forearm_len": 2.4,          # short: the wrist dissolves into the mist soon after
    "finger_k": 0.28,
    "thumb_k": 0.42,
}

# export rotations: columns = authored local axes (x, y, z) expressed in mesh space
R_LEFT = np.array([[0.0, 1.0, 0.0], [0.0, 0.0, -1.0], [-1.0, 0.0, 0.0]])
R_RIGHT = np.array([[0.0, -1.0, 0.0], [0.0, 0.0, 1.0], [-1.0, 0.0, 0.0]])
MIRROR = np.diag([-1.0, 1.0, 1.0])


def _export(local_sdf, anchors, R, mirror: bool):
    """Returns (world sdf, world anchors) with the palm centre at the origin."""
    M = MIRROR if mirror else np.eye(3)
    A = R @ M  # local point -> mesh space (before translation)
    # palm centre: from inside the palm straight out through the palmar surface (-Z local)
    palm_inside = v3(0.0, 2.05, -0.05)
    palm_local = ray_hit(local_sdf, palm_inside, (0, 0, -1), 2.0)
    origin = -(A @ palm_local)

    def world(p):
        q = (p - origin) @ A  # A is orthonormal: inverse = transpose
        return local_sdf(q)

    pts = {}
    for key, val in anchors.items():
        if key == "forearm_dir":
            continue
        pts[key] = A @ val + origin
    out = {
        "palm_center": A @ palm_local + origin,
        "wrist_center": pts["wrist_center"],
        "forearm_dir": normalize(A @ anchors["forearm_dir"]),
        "forearm_end": pts.get("forearm_end"),
        "tips": {n: pts[f"tip_{n}"] for n in ("thumb", "index", "middle", "ring", "little")},
    }
    return world, out


def build(side: str):
    if side == "left":
        local, anchors = build_hand(POSE_LEFT, detail=True)
        return _export(local, anchors, R_LEFT, mirror=False)
    local, anchors = build_hand(POSE_RIGHT, detail=True)
    return _export(S.mirror_x(local), {k: (MIRROR @ v if k != "forearm_dir" else MIRROR @ v)
                                        for k, v in anchors.items()}, R_RIGHT, mirror=False)
