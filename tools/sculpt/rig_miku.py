"""MIKU rig (Loop 5): skeleton from the sculpture's own construction (miku.py) + hard labels.

Joints come from the SDF build, not from guesses on the mesh: the spine chain lives in the
chest frame R_CHEST (the whole upper body is ``place``d with it around the waist origin), the head
frame is exactly R_CHEST @ R_HEAD at the atlas, the arm chain is ARMS[side] (shoulder, elbow,
wrist), the hands are the authored hand (hand.JOINTS) scaled by HAND_SCALE, mirrored for her
right and placed with ``_hand_frame``; the skirt chain follows the gown axis (pelvis frame).

Hard labels per vertex (then rig_core.solve_weights spreads them along the surface):
  1. part = argmin of the figure's part SDFs: head (+hair), torso (+bodice), gown, arm L, arm R
     (each arm = upper arm + forearm + hand). The SDF seams are the sculpture's own creases.
  2. shoulder: near the shoulder joint and lateral, the plane through the joint normal to the
     upper arm decides arm vs torso (the deltoid cap follows the arm).
  3. torso/gown: joint planes along the spine/skirt chain (bisector of the two bone axes).
     Chest-band vertices near a clavicle -> clavicle; the rest of the chest band -> ribcage.
  4. arm: elbow and wrist planes; in the hand, argmin of the hand's part SDFs (palm, each
     finger, thumb) and planes at MCP/PIP (2 segments per finger: proximal, middle+distal).
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

import miku as M
import sdf as S
from hand import FINGERS, JOINTS, DEBUG_PARTS, build_hand
from rig_core import Skeleton, frame

SIDES = ((1.0, "L"), (-1.0, "R"))  # +X = her left
FINGERS_MIKU = ("thumb", "index", "middle", "ring", "little")

# blend widths (mesh units): how far each bone's influence spreads beyond its own region
WIDTH = {
    "hips": 0.20, "spine": 0.15, "ribcage": 0.14, "neck": 0.09, "head": 0.07,
    "clavicle": 0.10, "upper_arm": 0.10, "forearm": 0.07, "hand": 0.035,
    "finger0": 0.022, "finger1": 0.018, "thumb0": 0.03, "thumb1": 0.02,
    "skirt.0": 0.40, "skirt.1": 0.50, "skirt.2": 0.55,
}

# spine chain in the neutral (chest) frame
J_SPINE = (0.0, 0.04, -0.02)
J_CHEST = (0.0, 0.46, -0.03)
J_RIBCAGE = (0.0, 0.62, -0.03)       # centre of the chest volume (chest_volume scales about it)
J_NECK = (0.0, 0.92, -0.055)
CLAV_HEAD = (0.06, 0.895, -0.02)      # sternoclavicular joint (x mirrored per side)
HEAD_TOP = (0.0, 0.47, 0.075)         # head frame, above the crown
# skirt chain: heights on the gown axis (pelvis frame), hem
J_HIPS_Y = -0.18
SKIRT_Y = (-0.62, -1.75, -2.90)
HEM_Y = M.HEM_Y


def _upper(p):
    return M.R_CHEST @ np.asarray(p, dtype=np.float64)


def _gown_axis(y):
    t = min(max(-y / -M.HEM_Y, 0.0), 1.0)
    return M.R_PELVIS @ np.array([0.03 * t, y, 0.02 - 0.34 * t * t])


def _hand_xf(side):
    """Authored hand point/direction -> neutral frame (scale, mirror, place)."""
    fr, origin = M._hand_frame(side)
    mir = np.diag([side, 1.0, 1.0])

    def point(q):
        return origin + fr @ (mir @ (np.asarray(q, dtype=np.float64) * M.HAND_SCALE))

    def direction(d):
        v = fr @ (mir @ np.asarray(d, dtype=np.float64))
        return v / np.linalg.norm(v)
    return point, direction


def build_skeleton(anchors):
    build_hand(M.POSE_MIKU, detail=False, forearm=False)   # fills hand.JOINTS for MIKU's hands
    sk = Skeleton()
    up = _upper
    Rc = M.R_CHEST
    fwd_c = Rc[:, 2]
    sk.add("root", None, (0, 0, 0), np.eye(3), tail=(0, 0.3, 0), deform=False)
    hips_h = M.R_PELVIS @ np.array([0.0, J_HIPS_Y, -0.01])
    spine_h = up(J_SPINE)
    sk.add("hips", "root", hips_h, frame(spine_h - hips_h, M.R_PELVIS[:, 2]), tail=spine_h,
           width=WIDTH["hips"])
    chest_h = up(J_CHEST)
    sk.add("spine", "hips", spine_h, frame(chest_h - spine_h, fwd_c), tail=chest_h, width=WIDTH["spine"])
    neck_h = up(J_NECK)
    sk.add("chest", "spine", chest_h, frame(neck_h - chest_h, fwd_c), tail=neck_h, deform=False)
    chest_b = sk.bones[-1]["basis"]
    sk.add("ribcage", "chest", up(J_RIBCAGE), chest_b, tail=up(J_RIBCAGE) + chest_b[:, 1] * 0.2,
           width=WIDTH["ribcage"])
    atlas = up(M.ATLAS)
    sk.add("neck", "chest", neck_h, frame(atlas - neck_h, fwd_c), tail=atlas, width=WIDTH["neck"])
    Rh = Rc @ M.R_HEAD
    head_top = up(M.ATLAS + M.R_HEAD @ np.array(HEAD_TOP))
    sk.add("head", "neck", atlas, Rh, tail=head_top, width=WIDTH["head"])
    hr = np.array(anchors["hair_root"])
    ht = np.array(anchors["hair_root_tangent"])
    sk.add("hair_root", "head", hr, frame(ht, Rh[:, 1]), tail=hr + ht * 0.2, deform=False)
    # arms
    for side, sfx in SIDES:
        sh, el, wr = (np.array(x) for x in M.ARMS[side])
        a, b = el - sh, wr - el
        clav = np.array(CLAV_HEAD) * np.array([side, 1.0, 1.0])
        sk.add(f"clavicle.{sfx}", "chest", up(clav), frame(Rc @ (sh - clav), fwd_c), tail=up(sh),
               width=WIDTH["clavicle"], side=int(side))
        z_up = b - a * np.dot(a, b) / np.dot(a, a)        # elbow flexes towards the forearm
        sk.add(f"upper_arm.{sfx}", f"clavicle.{sfx}", up(sh), frame(Rc @ a, Rc @ z_up), tail=up(el),
               width=WIDTH["upper_arm"], side=int(side))
        z_fo = -a + b * np.dot(a, b) / np.dot(b, b)
        sk.add(f"forearm.{sfx}", f"upper_arm.{sfx}", up(el), frame(Rc @ b, Rc @ z_fo), tail=up(wr),
               width=WIDTH["forearm"], side=int(side))
        point, direction = _hand_xf(side)
        J = JOINTS
        mcp_mid = J["middle"][0][0]
        palmar = direction((0.0, 0.0, -1.0))
        sk.add(f"hand.{sfx}", f"forearm.{sfx}", up(point((0, 0, 0))),
               frame(Rc @ (point(mcp_mid) - point((0, 0, 0))), Rc @ palmar), tail=up(point(mcp_mid)),
               width=WIDTH["hand"], side=int(side))
        for f in FINGERS_MIKU:
            pts, frs, _radii, tip = J[f]
            if f == "thumb":   # thumb.0 = metacarpal (CMC -> MCP), thumb.1 = both phalanges
                segs = ((pts[0], pts[1], frs[0]), (pts[1], pts[2], frs[1]))
                ws = (WIDTH["thumb0"], WIDTH["thumb1"])
            else:              # .0 = proximal phalanx, .1 = middle + distal
                segs = ((pts[0], pts[1], frs[0]), (pts[1], pts[2], frs[1]))
                ws = (WIDTH["finger0"], WIDTH["finger1"])
            parent = f"hand.{sfx}"
            for k, (h, t, fr) in enumerate(segs):
                tail = point(t) if k == 0 else point(tip)
                B = frame(Rc @ direction(np.asarray(t) - np.asarray(h)), Rc @ direction(-fr[:, 2]))
                sk.add(f"{f}.{k}.{sfx}", parent, up(point(h)), B, tail=up(tail), width=ws[k],
                       side=int(side))
                parent = f"{f}.{k}.{sfx}"
            last = sk.bones[-1]
            sk.add(f"{f}.tip.{sfx}", parent, up(point(tip)), last["basis"],
                   tail=up(point(tip)) + last["basis"][:, 1] * 0.02, deform=False, side=int(side))
    # skirt (Y down the gown axis, Z front: +X rotation swings the hem forward)
    prev = "hips"
    for k, y in enumerate(SKIRT_Y):
        h = _gown_axis(y)
        t = _gown_axis(SKIRT_Y[k + 1] if k + 1 < len(SKIRT_Y) else HEM_Y)
        sk.add(f"skirt.{k}", prev, h, frame(t - h, M.R_PELVIS[:, 2]), tail=t, width=WIDTH[f"skirt.{k}"])
        prev = f"skirt.{k}"
    return sk


def _child_side(P, joint, n_parent, n_child):
    n = n_parent + n_child
    if np.linalg.norm(n) < 1e-3:
        n = n_child
    n = n / np.linalg.norm(n)
    return (P - joint[None, :]) @ n > 0.0


def _seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / np.dot(ab, ab), 0.0, 1.0)
    return np.linalg.norm(P - (a[None, :] + t[:, None] * ab[None, :]), axis=1)


def labels(V, sk):
    """Hard bone label per vertex (see module docstring)."""
    n = len(V)
    Pn = V @ M.R_CHEST                      # neutral (chest) frame, = R_CHEST^T v
    head = S.place(M._head_and_hair(), M.ATLAS + M.R_HEAD @ M.HEAD_C, M.R_HEAD)
    torso = M._bodice(M._torso())
    gown = M._gown()
    arms, _ = M._arms()
    d = np.stack([
        S.evaluate(head, Pn), S.evaluate(torso, Pn), S.evaluate(gown, V),
        S.evaluate(S.union(*arms[0]), Pn), S.evaluate(S.union(*arms[1]), Pn),
    ], axis=1)
    part = np.argmin(d, axis=1)             # 0 head, 1 torso, 2 gown, 3 arm L, 4 arm R
    # shoulder override: lateral vertices near the joint go with the arm beyond the plane
    for pi, (side, _sfx) in zip((3, 4), SIDES):
        sh, el, _wr = (np.array(x) for x in M.ARMS[side])
        au = (el - sh) / np.linalg.norm(el - sh)
        near = (np.linalg.norm(Pn - sh[None, :], axis=1) < 0.30) & (Pn[:, 0] * side > 0.30)
        near &= (part == 1) | (part == pi)
        beyond = (Pn - sh[None, :]) @ au > 0.0
        part = np.where(near & beyond, pi, np.where(near & ~beyond, 1, part))
    lab = np.full(n, -1, dtype=np.int64)
    B = sk.bones
    Y = {bn["name"]: bn["basis"][:, 1] for bn in B}
    H = {bn["name"]: bn["head"] for bn in B}
    idx = sk.index
    lab[part == 0] = idx["head"]
    body = (part == 1) | (part == 2)
    # spine / skirt chain planes (mesh space)
    above_spine = _child_side(V, H["spine"], Y["hips"], Y["spine"])
    above_chest = _child_side(V, H["chest"], Y["spine"], Y["chest"])
    above_neck = _child_side(V, H["neck"], Y["chest"], Y["neck"])
    below = [(V - H[f"skirt.{k}"][None, :]) @ Y[f"skirt.{k}"] > 0.0 for k in range(3)]
    chain = np.full(n, idx["hips"], dtype=np.int64)
    chain[below[0]] = idx["skirt.0"]
    chain[below[1]] = idx["skirt.1"]
    chain[below[2]] = idx["skirt.2"]
    chain[above_spine] = idx["spine"]
    chain[above_chest] = idx["ribcage"]
    chain[above_neck] = idx["neck"]
    # clavicles: lateral band of the chest/neck along each clavicle
    for side, sfx in SIDES:
        sh = np.array(M.ARMS[side][0])
        ch = np.array(CLAV_HEAD) * np.array([side, 1.0, 1.0])
        dseg = _seg_dist(Pn, ch, sh)
        band = (Pn[:, 0] * side > 0.16) & (dseg < 0.16) & (Pn[:, 1] > 0.6)
        band &= (chain == idx["ribcage"]) | (chain == idx["neck"])
        chain[band & (part == 1)] = idx[f"clavicle.{sfx}"]
    lab[body] = chain[body]
    # arms
    build_hand(M.POSE_MIKU, detail=False, forearm=False)   # fills JOINTS / DEBUG_PARTS
    parts = [DEBUG_PARTS["palm"]] + list(DEBUG_PARTS["fingers"]) + [DEBUG_PARTS["thumb"]]
    part_names = ["palm"] + list(FINGERS) + ["thumb"]
    for pi, (side, sfx) in zip((3, 4), SIDES):
        sel = np.flatnonzero(part == pi)
        P = V[sel]
        to_child = lambda a, b, j: _child_side(P, H[j], Y[a], Y[b])  # noqa: E731
        beyond_el = to_child(f"upper_arm.{sfx}", f"forearm.{sfx}", f"forearm.{sfx}")
        beyond_wr = to_child(f"forearm.{sfx}", f"hand.{sfx}", f"hand.{sfx}")
        out = np.full(len(sel), idx[f"upper_arm.{sfx}"], dtype=np.int64)
        out[beyond_el] = idx[f"forearm.{sfx}"]
        hand_sel = np.flatnonzero(beyond_wr)
        out[hand_sel] = idx[f"hand.{sfx}"]
        # hand-local (authoring) coordinates of the hand vertices
        fr, origin = M._hand_frame(side)
        mir = np.array([side, 1.0, 1.0])
        q = (((Pn[sel][hand_sel] - origin[None, :]) @ fr) * mir[None, :]) / M.HAND_SCALE
        dh = np.stack([S.evaluate(f, q) for f in parts], axis=1)
        which = np.argmin(dh, axis=1)
        for k, name in enumerate(part_names):
            if name == "palm":
                continue
            m = which == k
            pts = JOINTS[name][0]
            y0 = (pts[1] - pts[0]) / np.linalg.norm(pts[1] - pts[0])
            y1 = (pts[2] - pts[1]) / np.linalg.norm(pts[2] - pts[1])
            past_base = (q - pts[0][None, :]) @ y0 > (0.0 if name != "thumb" else -0.2)
            seg1 = _child_side(q, pts[1], y0, y1)
            lab_f = np.where(seg1, idx[f"{name}.1.{sfx}"], idx[f"{name}.0.{sfx}"])
            lab_f = np.where(past_base, lab_f, idx[f"hand.{sfx}"])
            out[hand_sel[m]] = lab_f[m]
        lab[sel] = out
    assert (lab >= 0).all()
    return lab


def widths(sk):
    return np.array([bn["width"] for bn in sk.bones])


def anchors_local(sk, anchors):
    """Sculpture anchors (miku_body.json) re-expressed in the rest frame of the bone that carries
    them, so the runtime can follow them in any pose: global = bone_global_pose * local."""
    owner = {"head_top": "head", "forehead": "head", "hair_root": "head", "hair_root_tangent": "head",
             "palm_left": "hand.L", "palm_left_normal": "hand.L", "palm_right": "hand.R",
             "palm_right_normal": "hand.R", "chest": "ribcage", "gown_hem_center": "skirt.2"}
    out = {}
    for key, bone in owner.items():
        bn = sk.bones[sk.id(bone)]
        v = np.array(anchors[key], dtype=np.float64)
        is_dir = key.endswith("_normal") or key.endswith("_tangent")
        loc = bn["basis"].T @ (v if is_dir else v - bn["head"])
        out[key] = {"bone": bone, "local": [round(float(x), 6) + 0.0 for x in loc],
                    "kind": "direction" if is_dir else "point"}
    return out


def load_anchors(mesh_dir):
    with open(os.path.join(mesh_dir, "miku_body.json"), encoding="ascii") as fh:
        return json.load(fh)["anchors"]


# head bone helper for docs: the head frame bow (rad) relative to the neck
HEAD_BOW = math.degrees(0.30)
