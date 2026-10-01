#!/usr/bin/env python3
"""Bakes the rigs of the baked sculptures (Loop 5): skeleton + per-vertex skin weights.

  /opt/korium-py/bin/python tools/sculpt/rig_bake.py               # miku + hand
  /opt/korium-py/bin/python tools/sculpt/rig_bake.py --only hand --out /tmp/x

Reads assets/meshes/miku_body.obj / hand_left.obj EXACTLY (vertex order and values are kept: the
rest pose of the rig is the sculpture), writes assets/meshes/<rig>_rig.json (skeleton, readable)
+ <rig>_rig.skin.json (arrays, zlib + base64). Deterministic: same inputs -> same bytes.
"""
from __future__ import annotations

import argparse
import os
import sys
import time

for _var in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_var, "1")

import numpy as np  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rig_core as RC  # noqa: E402
import rig_hand  # noqa: E402
import rig_miku  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MESH_DIR = os.path.join(ROOT, "assets", "meshes")


def log(msg):
    print(f"[rig {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _stats(sk, V, F, bones, weights, lab):
    s = weights.sum(axis=1)
    used = (weights > 0).sum(axis=1)
    rest = RC.global_rest(sk)
    Vs = RC.skin(V, bones, weights, rest, rest)
    out = {
        "weight_sum_max_error": float(np.abs(s - 1.0).max()),
        "influences_max": int(used.max()),
        "influences_mean": round(float(used.mean()), 3),
        "rigid_vertices_share": round(float((used == 1).mean()), 4),
        "rest_pose_max_error": float(np.abs(Vs - V).max()),
        "orphans": int((s < 0.999).sum()),
    }
    assert out["weight_sum_max_error"] < 1e-5 and out["orphans"] == 0, out
    assert out["rest_pose_max_error"] < 1e-5, out
    return out


def bake_miku(out_dir):
    t0 = time.time()
    src = os.path.join(MESH_DIR, "miku_body.obj")
    V, N, AO, F = RC.read_obj(src)
    anchors = rig_miku.load_anchors(MESH_DIR)
    sk = rig_miku.build_skeleton(anchors)
    lab = rig_miku.labels(V, sk)
    g, a, b = RC.edge_graph(V, F)
    lab = RC.majority_filter(lab, a, b, passes=3)
    bones, weights = RC.solve_weights(V, F, lab, rig_miku.widths(sk))
    st = _stats(sk, V, F, bones, weights, lab)
    log(f"miku: {len(sk)} bones, {len(V)} vertices, {st} ({time.time() - t0:.0f}s)")
    extra = {
        "frame": "+Y up, +Z front (MIKU faces +Z), origin = waist centre; her left = +X (.L)",
        "rest_pose": "the sculpted pose of miku_body.obj (bit-identical vertices)",
        "anchors_local": rig_miku.anchors_local(sk, anchors),
        "stats": st,
        "label_counts": {sk.bones[i]["name"]: int(c) for i, c in
                         enumerate(np.bincount(lab, minlength=len(sk))) if c},
    }
    RC.write_rig(os.path.join(out_dir, "miku_rig.json"), os.path.join(out_dir, "miku_rig.skin.json"),
                 "miku_rig", {"path": "res://assets/meshes/miku_body.obj", "sha256": RC.file_sha256(src)},
                 sk, V, N, AO, F, bones, weights, extra)
    return sk, V, F, bones, weights, lab


def bake_hand(out_dir):
    t0 = time.time()
    src = os.path.join(MESH_DIR, "hand_left.obj")
    V, N, AO, F = RC.read_obj(src)
    sk, anchors = rig_hand.build_skeleton()
    lab = rig_hand.labels(V, sk)
    g, a, b = RC.edge_graph(V, F)
    lab = RC.majority_filter(lab, a, b, passes=3)
    bones, weights = RC.solve_weights(V, F, lab, rig_hand.widths(sk))
    st = _stats(sk, V, F, bones, weights, lab)
    log(f"hand: {len(sk)} bones, {len(V)} vertices, {st} ({time.time() - t0:.0f}s)")
    extra = {
        "frame": ("LEFT hand as authored: fingers +X, palm faces +Y, thumb towards -Z, origin = palm "
                  "centre; RIGHT = runtime mirror z -> -z (fingers +X, palm +Y, thumb +Z)"),
        "rest_pose": "the sculpted pose of hand_left.obj (bit-identical vertices)",
        "stats": st,
        "label_counts": {sk.bones[i]["name"]: int(c) for i, c in
                         enumerate(np.bincount(lab, minlength=len(sk))) if c},
    }
    RC.write_rig(os.path.join(out_dir, "hand_rig.json"), os.path.join(out_dir, "hand_rig.skin.json"),
                 "hand_rig", {"path": "res://assets/meshes/hand_left.obj", "sha256": RC.file_sha256(src)},
                 sk, V, N, AO, F, bones, weights, extra)
    return sk, V, F, bones, weights, lab


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=("miku", "hand"), action="append")
    ap.add_argument("--out", default=MESH_DIR)
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    for name in args.only or ("miku", "hand"):
        (bake_miku if name == "miku" else bake_hand)(args.out)


if __name__ == "__main__":
    main()
