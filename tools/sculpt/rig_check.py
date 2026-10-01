#!/usr/bin/env python3
"""Deformation check of the baked rigs in limit poses (offline, numpy LBS = Godot's skinning).

  /opt/korium-py/bin/python tools/sculpt/rig_check.py [--rig miku|hand]

For each pose: max/min edge length ratio (a tear would show as a huge stretch; the rig cannot
tear because weights live on shared vertices, so this measures how hard the surface is pulled),
share of triangles whose normal turns against the skinned vertex normals (LBS folds/collapse at
the inside of a bend) and volume change of the whole mesh.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig_core import rot_local  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MESH_DIR = os.path.join(ROOT, "assets", "meshes")


def load(name):
    meta = json.load(open(os.path.join(MESH_DIR, name + ".json")))
    pay = json.load(open(os.path.join(MESH_DIR, meta["skin_file"])))

    def arr(k, dt, w):
        raw = zlib.decompress(base64.b64decode(pay["arrays"][k]["zlib_b64"]))
        return np.frombuffer(raw, dtype=dt).reshape(-1, w).astype(np.float64 if dt == "<f4" else np.int64)
    V = arr("vertex", "<f4", 3)
    N = arr("normal", "<f4", 3)
    B = arr("bones", "<i4", 4)
    W = arr("weights", "<f4", 4)
    F = arr("index", "<i4", 3)[:, [0, 2, 1]]          # back to CCW
    names = [b["name"] for b in meta["bones"]]
    par = [b["parent"] for b in meta["bones"]]
    G = np.zeros((len(names), 4, 4))
    for i, b in enumerate(meta["bones"]):
        G[i, :3, :3] = np.stack([b["basis_x"], b["basis_y"], b["basis_z"]], axis=1)
        G[i, :3, 3] = b["head"]
        G[i, 3, 3] = 1.0
    return meta, names, par, G, V, N, B, W, F


def fk(names, par, G, local_rot):
    """Global poses with per-bone local rotations (euler XYZ about the bone's own axes)."""
    P = np.zeros_like(G)
    for i in range(len(names)):
        L = G[i] if par[i] < 0 else np.linalg.inv(G[par[i]]) @ G[i]
        R = np.eye(4)
        if names[i] in local_rot:
            R[:3, :3] = rot_local(local_rot[names[i]])
        Li = L @ R
        P[i] = Li if par[i] < 0 else P[par[i]] @ Li
    return P


def deform(G, P, V, N, B, W):
    K = P @ np.linalg.inv(G)
    Vh = np.concatenate([V, np.ones((len(V), 1))], axis=1)
    out = np.zeros_like(V)
    nn = np.zeros_like(N)
    for j in range(4):
        T = K[B[:, j]]
        out += W[:, j:j + 1] * np.einsum("nij,nj->ni", T, Vh)[:, :3]
        nn += W[:, j:j + 1] * np.einsum("nij,nj->ni", T[:, :3, :3], N)
    return out, nn / np.linalg.norm(nn, axis=1)[:, None]


def volume(V, F):
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


def measure(V0, V1, N1, F):
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    r = np.linalg.norm(V1[e[:, 0]] - V1[e[:, 1]], axis=1) / np.linalg.norm(V0[e[:, 0]] - V0[e[:, 1]], axis=1)
    fn = np.cross(V1[F[:, 1]] - V1[F[:, 0]], V1[F[:, 2]] - V1[F[:, 0]])
    vn = N1[F[:, 0]] + N1[F[:, 1]] + N1[F[:, 2]]
    flipped = np.einsum("ij,ij->i", fn, vn) < 0.0
    return {"stretch_max": round(float(r.max()), 3), "stretch_min": round(float(r.min()), 3),
            "inverted_tris": int(flipped.sum()), "inverted_share": round(float(flipped.mean()), 5),
            "volume_change": round(volume(V1, F) / volume(V0, F) - 1.0, 4)}


MIKU_POSES = {
    "head_turn_tilt": {"neck": (0.0, 0.5, 0.15), "head": (0.2, 0.7, 0.35)},
    "head_up_back": {"neck": (-0.35, 0.0, 0.0), "head": (-0.55, -0.4, 0.0)},
    "elbows_flexed_110deg": {"forearm.L": (1.9, 0, 0), "forearm.R": (1.9, 0, 0)},
    "arms_raised": {"clavicle.L": (0, 0, 0.25), "clavicle.R": (0, 0, -0.25),
                    "upper_arm.L": (0.3, 0, 1.9), "upper_arm.R": (0.3, 0, -1.9)},
    "arms_forward_across": {"upper_arm.L": (1.3, 0, -0.6), "upper_arm.R": (1.3, 0, 0.6),
                            "forearm.L": (1.6, 0, 0), "forearm.R": (1.6, 0, 0)},
    "wrists_flexed": {"hand.L": (0.9, 0, 0.3), "hand.R": (-0.7, 0, -0.3)},
    "fists": {f"{f}.{k}.{s}": (a, 0, 0) for s in ("L", "R") for f, aa in
              (("thumb", (0.45, 0.8)), ("index", (1.3, 1.7)), ("middle", (1.3, 1.75)),
               ("ring", (1.25, 1.75)), ("little", (1.2, 1.7))) for k, a in enumerate(aa)},
    "torso_bend_twist": {"spine": (0.3, 0.3, 0.12), "chest": (0.25, 0.25, 0.15), "hips": (-0.1, 0, -0.08)},
    "skirt_swing": {"skirt.0": (0.15, 0, 0.12), "skirt.1": (0.2, 0, 0.15), "skirt.2": (0.25, 0, 0.18)},
}
HAND_POSES = {
    "fist": {f"{f}.{k}": (a, 0, 0) for f, aa in
             (("thumb", (0.55, 0.55, 0.65)), ("index", (1.25, 1.45, 0.9)), ("middle", (1.25, 1.5, 0.9)),
              ("ring", (1.2, 1.5, 0.9)), ("little", (1.15, 1.45, 0.9))) for k, a in enumerate(aa)},
    "open_spread": {"thumb.0": (-0.1, 0, 0.3), "index.0": (-0.2, 0, 0.18), "middle.0": (-0.2, 0, 0),
                    "ring.0": (-0.2, 0, -0.16), "little.0": (-0.2, 0, -0.32),
                    "index.1": (-0.15, 0, 0), "middle.1": (-0.15, 0, 0), "ring.1": (-0.15, 0, 0),
                    "little.1": (-0.15, 0, 0)},
    "wrist_flexed": {"palm": (0.95, 0, 0.25)},
    "wrist_extended": {"palm": (-0.8, 0, -0.2)},
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rig", choices=("miku", "hand"), action="append")
    args = ap.parse_args()
    for rig in args.rig or ("miku", "hand"):
        meta, names, par, G, V, N, B, W, F = load(f"{rig}_rig")
        for pose, rot in (MIKU_POSES if rig == "miku" else HAND_POSES).items():
            P = fk(names, par, G, rot)
            V1, N1 = deform(G, P, V, N, B, W)
            print(rig, pose, measure(V, V1, N1, F))


if __name__ == "__main__":
    main()
