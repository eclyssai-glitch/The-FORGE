#!/usr/bin/env python3
"""DEVELOPMENT ONLY - reads the dev inspector's JSON dumps (tools/inspector/dev_inspector.gd).

  tools/inspector/summarize.py DUMP.json                 readable summary of one dump
  tools/inspector/summarize.py DUMP.json --bones=all     ... with every bone (default: key bones)
  tools/inspector/summarize.py DUMP.json --section=miku  ... only that dev_inspect section, in full
  tools/inspector/summarize.py --diff A.json B.json      what changed between two dumps
        [--tol=1e-4] [--max=200] [--only=skeletons,sections] [--all]

The diff compares leaf values (numbers within --tol are equal); `time`, `motion_time`, `frame`
and the per-node labels of `tree` are skipped unless --all (tree changes are listed as added /
removed nodes). Python standard library only; never shipped (tools/ is excluded from the export).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

KEY_BONES = ["root", "hips", "spine", "chest", "neck", "head", "upper_arm.L", "forearm.L", "hand.L",
             "upper_arm.R", "forearm.R", "hand.R", "wrist", "palm", "index.0", "index.1"]
NOISY = {"time", "motion_time", "frame"}


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def fmt(v, digits: int = 3) -> str:
    if isinstance(v, bool) or v is None:
        return str(v).lower() if isinstance(v, bool) else "null"
    if isinstance(v, (int, float)):
        return f"{v:.{digits}f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)
    if isinstance(v, list):
        if v and len(v) <= 4 and all(isinstance(x, (int, float)) for x in v):
            return "(" + ", ".join(fmt(x, digits) for x in v) + ")"
        return "[" + ", ".join(fmt(x, digits) for x in v[:8]) + (", ..." if len(v) > 8 else "") + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k}: {fmt(x, digits)}" for k, x in list(v.items())[:8]) + \
            (", ..." if len(v) > 8 else "") + "}"
    return str(v)


def flatten(v, prefix: str = "", out: dict | None = None) -> dict:
    out = {} if out is None else out
    if isinstance(v, dict):
        if not v:
            out[prefix] = {}
        for k, x in v.items():
            flatten(x, f"{prefix}.{k}" if prefix else str(k), out)
    elif isinstance(v, list) and v and any(isinstance(x, (dict, list)) for x in v):
        for i, x in enumerate(v):
            flatten(x, f"{prefix}[{i}]", out)
    else:
        out[prefix] = v
    return out


def summarize(d: dict, bones: str, section: str | None) -> None:
    w = print
    if section:
        s = d.get("sections", {}).get(section)
        if s is None:
            w(f"no section '{section}' (sections: {', '.join(sorted(d.get('sections', {})))})")
            sys.exit(1)
        for k, v in sorted(flatten(s).items()):
            w(f"  {k} = {fmt(v)}")
        return
    q = d.get("quality", {})
    w(f"{d.get('format')}  frame {d.get('frame')}  time {fmt(d.get('time'))} s  motion {fmt(d.get('motion_time'))}"
      f"{'  (movie)' if d.get('movie') else ''}")
    w(f"sim T+{fmt(d.get('sim_time'), 2)} {d.get('sim_status')} x{fmt(d.get('sim_speed'))}  scenario {d.get('scenario')}"
      f"  phase {d.get('phase')}  mode {d.get('mode')}  quality {q.get('level')}{' (auto)' if q.get('auto') else ''}"
      f"  hud {fmt(d.get('hud'))}  cinematic {fmt(d.get('cinematic'))}  selected '{d.get('selected')}'")
    if d.get("context"):
        w("context: " + ", ".join(f"{k}={fmt(v)}" for k, v in sorted(d["context"].items())))
    cam = d.get("camera") or {}
    if cam:
        line = f"camera {cam.get('path')}  pos {fmt(cam.get('position'))}  target {fmt(cam.get('target'))}  fov {fmt(cam.get('fov'))}"
        if cam.get("rig"):
            r = cam["rig"]
            line += f"  rig yaw {fmt(r.get('yaw'))} pitch {fmt(r.get('pitch'))} dist {fmt(r.get('distance'))}"
        if cam.get("focused"):
            line += f"  focused {cam['focused']}"
        w(line)
    tree = d.get("tree", {})
    w(f"tree {tree.get('count')} nodes{' (truncated)' if tree.get('truncated') else ''} · relevant {len(d.get('nodes', {}))}"
      f" · skeletons {len(d.get('skeletons', {}))} · animation trees {len(d.get('animation_trees', {}))}"
      f" · sections {len(d.get('sections', {}))}")
    for path, sk in sorted(d.get("skeletons", {}).items()):
        tracked = sk.get("final_frame", -1) >= 0
        w(f"\nSKELETON {path}  {sk.get('bone_count')} bones  final pose {'frame ' + str(sk['final_frame']) if tracked else 'not tracked'}")
        for m in sk.get("modifiers", []):
            props = m.get("properties", {})
            bone = props.get("bone_name") or props.get("bone") or ""
            tg = ", ".join(f"{k} -> {t.get('node', t.get('missing'))} @{fmt(t.get('world_position'))}"
                           for k, t in sorted(m.get("targets", {}).items()))
            st = (" " + fmt(m["status"])) if m.get("status") else ""
            w(f"  modifier {m.get('name')} [{m.get('class')}] active={fmt(m.get('active'))} influence={fmt(m.get('influence'))}"
              f"{' bone=' + str(bone) if bone != '' else ''}{' ' + tg if tg else ''}{st}")
        names = sorted(sk.get("bones", {}), key=lambda n: sk["bones"][n].get("index", 0))
        if bones != "all":
            names = [n for n in names if n in KEY_BONES or any(n.startswith(k + ".") for k in ("hand",))]
        for n in names:
            b = sk["bones"][n]
            pose = b.get("final") or b.get("pose")
            rest = b.get("rest", {})
            w(f"  {n:<14} rot {fmt(pose.get('euler_deg'), 1)}°  rest {fmt(rest.get('euler_deg'), 1)}°"
              f"  scale {fmt(pose.get('scale'))}  world {fmt(b.get('world_position'))}")
    for path, t in sorted(d.get("animation_trees", {}).items()):
        w(f"\nANIMATION TREE {path} [{t.get('root')}] active={fmt(t.get('active'))}")
        for p, pb in sorted(t.get("playbacks", {}).items()):
            w(f"  {p}: {pb.get('current_node')} ({fmt(pb.get('position'))}/{fmt(pb.get('length'))} s)"
              f" travel {pb.get('travel_path')} fading_from '{pb.get('fading_from')}'")
        for p, v in sorted(t.get("parameters", {}).items()):
            w(f"  {p} = {fmt(v)}")
    for key, s in sorted(d.get("sections", {}).items()):
        w(f"\nSECTION {key}  ({s.get('_path')})")
        for k, v in sorted(s.items()):
            if not k.startswith("_"):
                w(f"  {k}: {fmt(v)}")
    if d.get("errors"):
        w("\nERRORS")
        for e in d["errors"]:
            w(f"  {e}")


def diff(a: dict, b: dict, tol: float, limit: int, only: list[str], everything: bool) -> int:
    w = print
    w(f"A frame {a.get('frame')} sim T+{fmt(a.get('sim_time'), 2)} {a.get('context', {})}")
    w(f"B frame {b.get('frame')} sim T+{fmt(b.get('sim_time'), 2)} {b.get('context', {})}")
    ta, tb = a.get("tree", {}).get("nodes", {}), b.get("tree", {}).get("nodes", {})
    added = sorted(set(tb) - set(ta))
    removed = sorted(set(ta) - set(tb))
    if added or removed:
        w(f"tree: +{len(added)} -{len(removed)} nodes")
        for p in added[:limit]:
            w(f"  + {p} [{tb[p]}]")
        for p in removed[:limit]:
            w(f"  - {p} [{ta[p]}]")
    fa, fb = flatten(a), flatten(b)
    changes = []
    for k in sorted(set(fa) | set(fb)):
        top = k.split(".", 1)[0].split("[", 1)[0]
        if not everything and (top in NOISY or top == "tree"):
            continue
        if only and top not in only:
            continue
        va, vb = fa.get(k, "<absent>"), fb.get(k, "<absent>")
        if va == vb:
            continue
        if isinstance(va, list) and isinstance(vb, list) and len(va) == len(vb) and \
                all(isinstance(x, (int, float)) and isinstance(y, (int, float)) for x, y in zip(va, vb)):
            if max(abs(x - y) for x, y in zip(va, vb)) <= tol:
                continue
        elif isinstance(va, (int, float)) and isinstance(vb, (int, float)) and not isinstance(va, bool) \
                and abs(va - vb) <= tol:
            continue
        changes.append((k, va, vb))
    w(f"{len(changes)} changed values (tol {tol}){' — first ' + str(limit) if len(changes) > limit else ''}")
    for k, va, vb in changes[:limit]:
        w(f"  {k}: {fmt(va)} -> {fmt(vb)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dumps", nargs="+")
    ap.add_argument("--diff", action="store_true")
    ap.add_argument("--bones", default="key", choices=["key", "all"])
    ap.add_argument("--section")
    ap.add_argument("--tol", type=float, default=1e-4)
    ap.add_argument("--max", type=int, default=200)
    ap.add_argument("--only", default="")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    for p in args.dumps:
        if not Path(p).is_file():
            print(f"summarize: {p} not found", file=sys.stderr)
            return 2
    if args.diff:
        if len(args.dumps) != 2:
            print("summarize: --diff needs two dumps", file=sys.stderr)
            return 2
        only = [s for s in args.only.split(",") if s]
        return diff(load(args.dumps[0]), load(args.dumps[1]), args.tol, args.max, only, args.all)
    for i, p in enumerate(args.dumps):
        if i:
            print("\n" + "=" * 80)
        print(f"DUMP {p}")
        summarize(load(p), args.bones, args.section)
    return 0


if __name__ == "__main__":
    sys.exit(main())
