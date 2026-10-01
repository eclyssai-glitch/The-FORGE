"""Generic offline skinning for the baked sculptures (rig bake, Loop 5).

A rig = a skeleton (named bones with global rest frames) + per-vertex skin weights (<= 4
influences, sum 1) over the *baked* mesh (assets/meshes/<name>.obj, read back exactly).

Bone frame convention (documented in docs/PROCEDURAL.md, section Rig):
  +Y = along the bone (head -> child joint), +Z = the side the joint FLEXES towards (palm side for
  fingers/hand, front for spine/neck/head, inside of the bend for the arm), +X = Y x Z.
  A positive rotation about local +X therefore always flexes (curls a finger, bends the elbow,
  nods the head forward). Left/right bones are mirror images with X flipped (proper rotations),
  so +X flexes on both sides while twist (Y) and abduction (Z) turn in mirrored senses.

Weights: every vertex first gets ONE bone (hard label, decided by the figure's own SDF parts
and joint planes -- see rig_miku.py / rig_hand.py); then each bone spreads into its neighbours
along the SURFACE (geodesic distance on the mesh graph, Dijkstra) with a per-bone blend width
W: w_b = (1 - D_b / W_b)^2 (1 inside its own region), normalised, top 4 kept, renormalised, then
a few umbrella smoothing passes. Geodesic spreading never jumps across a gap (fingers, arm vs
skirt), and weights are per shared vertex, so the skinned surface cannot tear.

Everything is deterministic (no randomness, stable sorts, fixed iteration counts).
"""
from __future__ import annotations

import base64
import hashlib
import json
import zlib

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

MAX_INFLUENCES = 4
FORMAT_VERSION = 1


# --------------------------------------------------------------------------- mesh I/O

def read_obj(path):
    """Reads the baked OBJ exactly (``v x y z r g b`` / ``vn`` / ``f a//a b//b c//c``).
    Returns V (n,3) float64, N (n,3), AO (n,), F (t,3) int64 (CCW from outside, OBJ order)."""
    V, C, N, F = [], [], [], []
    with open(path, "r", encoding="ascii") as fh:
        for line in fh:
            if line.startswith("v "):
                p = line.split()
                V.append((float(p[1]), float(p[2]), float(p[3])))
                C.append(float(p[4]))
            elif line.startswith("vn "):
                p = line.split()
                N.append((float(p[1]), float(p[2]), float(p[3])))
            elif line.startswith("f "):
                p = line.split()
                F.append(tuple(int(x.split("/")[0]) - 1 for x in p[1:4]))
    V = np.array(V, dtype=np.float64)
    N = np.array(N, dtype=np.float64)
    assert len(N) == len(V), "one normal per vertex expected"
    return V, N, np.array(C, dtype=np.float64), np.array(F, dtype=np.int64)


def file_sha256(path) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


# --------------------------------------------------------------------------- skeleton

def frame(y_axis, z_hint):
    """Orthonormal right-handed basis (columns X, Y, Z) with Y exact and Z closest to z_hint."""
    y = np.asarray(y_axis, dtype=np.float64)
    y = y / np.linalg.norm(y)
    z = np.asarray(z_hint, dtype=np.float64)
    z = z - y * np.dot(z, y)
    z = z / np.linalg.norm(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


class Skeleton:
    """Bones in parent-first order. Each bone: name, parent index (-1 = root), global rest
    (basis 3x3 columns X/Y/Z, head point), tail (for docs/tests only), blend width, deform."""

    def __init__(self):
        self.bones = []
        self.index = {}

    def add(self, name, parent, head, basis, tail=None, width=0.0, deform=True, side=0):
        assert name not in self.index, name
        p = -1 if parent is None else self.index[parent]
        B = np.asarray(basis, dtype=np.float64)
        assert abs(np.linalg.det(B) - 1.0) < 1e-6, (name, np.linalg.det(B))
        head = np.asarray(head, dtype=np.float64)
        tail = head + B[:, 1] * 0.1 if tail is None else np.asarray(tail, dtype=np.float64)
        self.index[name] = len(self.bones)
        self.bones.append({"name": name, "parent": p, "basis": B, "head": head, "tail": tail,
                           "width": float(width), "deform": bool(deform), "side": int(side)})
        return self.index[name]

    def __len__(self):
        return len(self.bones)

    def id(self, name):
        return self.index[name]


# --------------------------------------------------------------------------- weights

def edge_graph(V, F):
    """Symmetric sparse graph of the mesh edges weighted by length."""
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    e = np.sort(e, axis=1)
    key = np.unique(e[:, 0] * len(V) + e[:, 1])
    a, b = key // len(V), key % len(V)
    w = np.linalg.norm(V[a] - V[b], axis=1)
    g = coo_matrix((np.concatenate([w, w]), (np.concatenate([a, b]), np.concatenate([b, a]))),
                   shape=(len(V), len(V))).tocsr()
    return g, a, b


def majority_filter(labels, a, b, passes=2, locked=None):
    """Removes isolated label specks: a vertex whose neighbours mostly share another label takes
    it (only if that label holds > 60% of its 1-ring). ``locked`` vertices never change."""
    n = len(labels)
    lab = labels.copy()
    nl = int(lab.max()) + 1
    for _ in range(passes):
        cnt = np.zeros((n, nl), dtype=np.int32)
        np.add.at(cnt, (a, lab[b]), 1)
        np.add.at(cnt, (b, lab[a]), 1)
        deg = cnt.sum(axis=1)
        best = np.argmax(cnt, axis=1)
        share = cnt[np.arange(n), best] / np.maximum(deg, 1)
        change = (best != lab) & (share > 0.6)
        if locked is not None:
            change &= ~locked
        if not change.any():
            break
        lab = np.where(change, best, lab)
    return lab


def solve_weights(V, F, labels, widths, smooth_passes=2):
    """Hard labels (bone per vertex) -> top-4 normalised weights (geodesic spreading)."""
    n = len(V)
    g, a, b = edge_graph(V, F)
    used = np.unique(labels)
    cols = []
    for bone in used:
        W = float(widths[bone])
        src = np.flatnonzero(labels == bone)
        if W <= 0.0:
            w = (labels == bone).astype(np.float64)
        else:
            D = dijkstra(g, directed=False, indices=src, min_only=True, limit=W)
            x = np.clip(D / W, 0.0, 1.0)
            w = np.where(np.isfinite(D), (1.0 - x) ** 2, 0.0)
        cols.append(w)
    Wm = np.stack(cols, axis=1)                       # (n, k) dense over used bones
    for _ in range(smooth_passes):
        acc = np.zeros_like(Wm)
        cnt = np.zeros(n)
        np.add.at(acc, a, Wm[b])
        np.add.at(acc, b, Wm[a])
        np.add.at(cnt, a, 1.0)
        np.add.at(cnt, b, 1.0)
        Wm = 0.5 * Wm + 0.5 * acc / np.maximum(cnt, 1.0)[:, None]
    Wm /= np.maximum(Wm.sum(axis=1), 1e-12)[:, None]
    # top 4 (stable: ties broken by bone order), renormalised
    order = np.argsort(-Wm, axis=1, kind="stable")[:, :MAX_INFLUENCES]
    top = np.take_along_axis(Wm, order, axis=1)
    top[top < 1e-4] = 0.0
    top /= top.sum(axis=1)[:, None]
    bones = used[order].astype(np.int32)
    bones[top == 0.0] = 0
    # deterministic layout: influences sorted by weight (desc), unused slots = (bone 0, 0.0)
    return bones, top


# --------------------------------------------------------------------------- skinning (check)

def global_rest(sk):
    """(n, 4, 4) global rest matrices."""
    M = np.zeros((len(sk), 4, 4))
    for i, bn in enumerate(sk.bones):
        M[i, :3, :3] = bn["basis"]
        M[i, :3, 3] = bn["head"]
        M[i, 3, 3] = 1.0
    return M


def skin(V, bones, weights, pose_global, rest_global):
    """Linear blend skinning: sum_i w_i * (P_b * R_b^-1) * v."""
    K = np.einsum("bij,bjk->bik", pose_global, np.linalg.inv(rest_global))
    Vh = np.concatenate([V, np.ones((len(V), 1))], axis=1)
    out = np.zeros((len(V), 3))
    for i in range(bones.shape[1]):
        T = K[bones[:, i]]
        out += weights[:, i:i + 1] * np.einsum("nij,nj->ni", T, Vh)[:, :3]
    return out


# --------------------------------------------------------------------------- output

def _blob(arr, dtype):
    raw = np.ascontiguousarray(arr, dtype=dtype).tobytes()
    comp = zlib.compress(raw, 9)
    return {"bytes": len(raw), "zlib_b64": base64.b64encode(comp).decode("ascii")}


def r(v, n=6):
    return [round(float(x), n) + 0.0 for x in np.asarray(v, float).reshape(-1)]


def write_rig(json_path, skin_path, name, source, sk, V, N, AO, F, bones, weights, extra):
    """``<name>_rig.json`` (readable: skeleton, conventions, stats) + ``<name>_rig.skin.json``
    (payload: zlib + base64 little-endian arrays). Float32 positions/normals/weights, int32 bones
    and indices; faces already in Godot's clockwise front order."""
    nb = len(sk)
    out_bones = []
    for bn in sk.bones:
        out_bones.append({
            "name": bn["name"], "parent": bn["parent"],
            "head": r(bn["head"]), "tail": r(bn["tail"]),
            "basis_x": r(bn["basis"][:, 0]), "basis_y": r(bn["basis"][:, 1]),
            "basis_z": r(bn["basis"][:, 2]),
            "deform": bn["deform"], "side": bn["side"], "blend_width": round(bn["width"], 4),
        })
    counts = np.bincount(bones[weights > 0].reshape(-1), minlength=nb)
    meta = {
        "name": name,
        "format_version": FORMAT_VERSION,
        "generator": "tools/sculpt/rig_bake.py",
        "source_mesh": source["path"],
        "source_sha256": source["sha256"],
        "vertices": int(len(V)),
        "triangles": int(len(F)),
        "max_influences": MAX_INFLUENCES,
        "bone_count": nb,
        "bones": out_bones,
        "vertices_per_bone": {sk.bones[i]["name"]: int(counts[i]) for i in range(nb)},
        "skin_file": skin_path.replace("\\", "/").split("/")[-1],
    }
    meta.update(extra)
    with open(json_path, "w", encoding="ascii") as fh:
        fh.write(json.dumps(meta, indent=1, sort_keys=True) + "\n")
    Fg = F[:, [0, 2, 1]]  # OBJ CCW -> Godot CW front faces
    col = np.stack([AO, AO, AO, np.ones_like(AO)], axis=1)
    payload = {
        "name": name,
        "format_version": FORMAT_VERSION,
        "vertex_count": int(len(V)),
        "index_count": int(Fg.size),
        "arrays": {
            "vertex": _blob(V, "<f4"),
            "normal": _blob(N, "<f4"),
            "color": _blob(col, "<f4"),
            "bones": _blob(bones, "<i4"),
            "weights": _blob(weights, "<f4"),
            "index": _blob(Fg, "<i4"),
        },
    }
    with open(skin_path, "w", encoding="ascii") as fh:
        fh.write(json.dumps(payload, indent=1, sort_keys=True) + "\n")
