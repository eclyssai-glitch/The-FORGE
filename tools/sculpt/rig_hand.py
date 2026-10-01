"""Generic angelic hand rig (Loop 5): one rig over hand_left.obj, serving N instances; the right
hand is its mirror image built at runtime (HandRig.build(RIGHT): z -> -z, see docs).

Bones: wrist (root: wrist joint, carries the forearm stump), palm (wrist -> palm), palm_center
(non-deform anchor on the palm surface: +Y = palm normal, +Z = towards the fingers), thumb.0/1/2
(metacarpal, proximal, distal), index/middle/ring/little.0/1/2 (proximal, middle, distal) and
non-deform <finger>.tip anchors. Joints are the authored hand's own chains (hand.JOINTS) in the
export frame of giant_hands.py (fingers +X, palm faces +Y, thumb towards -Z, origin = palm
centre).
"""
from __future__ import annotations

import numpy as np

import giant_hands as G
import sdf as S
from hand import DEBUG_PARTS, FINGERS, JOINTS, build_hand
from rig_core import Skeleton, frame

CHAINS = ("thumb",) + FINGERS
WIDTH = {"wrist": 0.55, "palm": 0.32, "thumb0": 0.34, "seg": 0.17}


def _export():
    """(A, origin, anchors): authored local point q -> mesh A @ q + origin (left hand)."""
    _f, anchors = G.build("left")
    return G.R_LEFT, np.asarray(anchors["wrist_center"], dtype=np.float64), anchors


def build_skeleton():
    build_hand(G.POSE_LEFT, detail=True)
    A, origin, anchors = _export()

    def pt(q):
        return A @ np.asarray(q, dtype=np.float64) + origin

    def dr(d):
        v = A @ np.asarray(d, dtype=np.float64)
        return v / np.linalg.norm(v)
    sk = Skeleton()
    palmar = dr((0, 0, -1))
    mcp_mid = JOINTS["middle"][0][0]
    wrist_b = frame(dr(mcp_mid), palmar)
    sk.add("wrist", None, origin, wrist_b, tail=origin + wrist_b[:, 1] * 1.0, width=WIDTH["wrist"])
    sk.add("palm", "wrist", origin, wrist_b, tail=pt(mcp_mid), width=WIDTH["palm"])
    pc = np.asarray(anchors["palm_center"], dtype=np.float64)
    sk.add("palm_center", "palm", pc, frame(-palmar, dr(mcp_mid)), tail=pc - palmar * 0.5, deform=False)
    for f in CHAINS:
        pts, frs, _radii, tip = JOINTS[f]
        parent = "palm"
        for k in range(3):
            h, t = pts[k], (pts[k + 1] if k < 2 else tip)
            B = frame(dr(np.asarray(pts[k + 1]) - np.asarray(h)), dr(-frs[k][:, 2]))
            w = WIDTH["thumb0"] if (f == "thumb" and k == 0) else WIDTH["seg"]
            sk.add(f"{f}.{k}", parent, pt(h), B, tail=pt(t), width=w)
            parent = f"{f}.{k}"
        last = sk.bones[-1]
        sk.add(f"{f}.tip", parent, pt(tip), last["basis"], tail=pt(tip) + last["basis"][:, 1] * 0.3,
               deform=False)
    return sk, anchors


def labels(V, sk):
    build_hand(G.POSE_LEFT, detail=True)
    A, origin, _anchors = _export()
    q = (V - origin[None, :]) @ A            # A orthonormal: local = A^T (v - origin)
    parts = [DEBUG_PARTS["palm"]] + list(DEBUG_PARTS["fingers"]) + [DEBUG_PARTS["thumb"]]
    names = ["palm"] + list(FINGERS) + ["thumb"]
    d = np.stack([S.evaluate(f, q) for f in parts], axis=1)
    which = np.argmin(d, axis=1)
    idx = sk.index
    lab = np.full(len(V), idx["palm"], dtype=np.int64)
    # wrist joint plane (bisector of the forearm axis reversed and the hand axis)
    fa = np.asarray(G.POSE_LEFT["forearm_dir"], dtype=np.float64)
    n = -fa / np.linalg.norm(fa) + np.array([0.0, 1.0, 0.0])
    n /= np.linalg.norm(n)
    lab[q @ n < 0.0] = idx["wrist"]
    for k, name in enumerate(names):
        if name == "palm":
            continue
        m = which == k
        pts = JOINTS[name][0]
        ys = [(pts[i + 1] - pts[i]) / np.linalg.norm(pts[i + 1] - pts[i]) for i in range(3)]
        seg = np.zeros(len(V), dtype=np.int64)
        for j in (1, 2):
            nj = ys[j - 1] + ys[j]
            nj /= np.linalg.norm(nj)
            seg += ((q - pts[j][None, :]) @ nj > 0.0).astype(np.int64)
        seg = np.minimum(seg, 2)
        past = (q - pts[0][None, :]) @ ys[0] > (0.0 if name != "thumb" else -0.6)
        lf = np.array([idx[f"{name}.0"], idx[f"{name}.1"], idx[f"{name}.2"]])[seg]
        lf = np.where(past, lf, lab)
        lab[m] = lf[m]
    return lab


def widths(sk):
    return np.array([bn["width"] for bn in sk.bones])
