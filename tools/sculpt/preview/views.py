"""Camera views of the versioned previews (tools/sculpt/previews): writes views_final_*.json into
the directory given as first argument. Head views are placed in MIKU's head frame (true front,
3/4 and profile of the bowed head)."""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import miku  # noqa: E402
from sdf import v3  # noqa: E402

D = sys.argv[1]
R = miku.R_CHEST @ miku.R_HEAD


def hp(local):
    return miku._head_point(v3(local)).tolist()


def hv(name, deg, dist, y, tgt, fov, light="studio"):
    a = np.radians(deg)
    return {"name": name, "pos": hp((dist * np.sin(a), y, dist * np.cos(a))), "target": hp(tgt),
            "fov": fov, "light": light, "up": (R @ v3(0, 1, 0)).tolist()}


mk = [
    {"name": "miku_front", "pos": [0, -0.8, 11.5], "target": [0, -1.25, 0], "fov": 36},
    {"name": "miku_q34", "pos": [7.2, 0.2, 8.8], "target": [0, -1.2, 0], "fov": 36},
    {"name": "miku_side", "pos": [11.5, -0.8, -0.2], "target": [0, -1.25, -0.2], "fov": 36},
    {"name": "miku_back", "pos": [-3.5, 0.0, -10.8], "target": [0, -1.2, -0.2], "fov": 36},
    {"name": "miku_low", "pos": [2.0, -4.6, 7.4], "target": [0, -0.6, 0.2], "fov": 40},
    {"name": "miku_bust_q34", "pos": [2.6, 1.2, 3.4], "target": [0.1, 0.9, 0.2], "fov": 34},
    hv("miku_head_face", 0, 1.9, 0.05, (0, -0.02, 0.05), 22),
    hv("miku_head_q34l", 38, 1.9, 0.1, (0, -0.02, 0.05), 22),
    hv("miku_head_sidel", 90, 1.9, 0.0, (0, 0, -0.02), 24),
    hv("miku_head_soft", 30, 1.7, 0.05, (0, -0.02, 0.08), 19, "soft_side"),
    hv("miku_head_hard", 12, 1.7, 0.2, (0, -0.02, 0.08), 19, "hard"),
    {"name": "miku_hand_left", "pos": [2.0, -0.35, 2.4], "target": [1.15, -0.64, 0.95], "fov": 24},
]
json.dump(mk, open(os.path.join(D, "views_final_miku.json"), "w"))


def hands(side, sx, sy):
    p = "hand_" + side
    return [
        {"name": p + "_q34", "pos": [5 * sx, 5, 9], "target": [1 * sx, 0, 0], "fov": 40},
        {"name": p + "_front", "pos": [1 * sx, 0.5, 12.5], "target": [1 * sx, 0, 0], "fov": 42},
        {"name": p + "_top", "pos": [1 * sx, 12, 1.5], "target": [1 * sx, 0, 0], "fov": 42},
        {"name": p + "_under", "pos": [1 * sx, -12, 1.5], "target": [1 * sx, 0, 0], "fov": 42},
        {"name": p + "_low", "pos": [10 * sx, 1.5 * sy, 5], "target": [2 * sx, 0, 0], "fov": 40},
        {"name": p + "_soft", "pos": [5 * sx, 4 * sy, 7], "target": [2.5 * sx, 0.5 * sy, 0.3], "fov": 30,
         "light": "soft_side"},
        {"name": p + "_hard", "pos": [3 * sx, 6 * sy, 8], "target": [1.5 * sx, 0, 0], "fov": 36,
         "light": "hard"},
    ]


json.dump(hands("left", 1, 1), open(os.path.join(D, "views_final_left.json"), "w"))
json.dump(hands("right", -1, -1), open(os.path.join(D, "views_final_right.json"), "w"))
