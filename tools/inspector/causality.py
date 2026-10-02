#!/usr/bin/env python3
"""DEVELOPMENT ONLY - causality gate of MIKU's action timelines (Loop 5, round 2).

Reads dev inspector dumps (tools/inspector/dev_inspector.gd) - files and/or directories of dumps
(e.g. the <base>_inspect/ of `tools/record_living.sh --inspect-every=<s>`, or a capture directory
written with --inspect) - takes `sections.miku.causality` of each one, unites the entries seen
across dumps and checks the causal chain of every execution (docs/ANIMATION.md, "Linha do tempo
causal"; docs/BUILD.md, "Gate de causalidade").

  tools/inspector/causality.py DIR_OR_DUMP [...]            table + summary, exit 1 on any FAIL
  tools/inspector/causality.py DIR --require                ... and big actions must be complete
  tools/inspector/causality.py DIR --failures-only          only the failing rows + summary

Entry (one per execution): {request_id, step, action, channel: main|overlay|follower|task, stage,
phase: ""|finished|failed|cancelled, t: {intent, anticipation, gesture, thread, hand, matter,
result}} in seconds of MIKU's clock (`sections.miku.clock`), each stage stamped the first time.

Rules (every entry):
  - `intent` is always present (an entry is opened with it);
  - the stages present form a PREFIX of intent -> anticipation -> gesture -> thread -> hand ->
    matter (a stage present without the previous one fails: "thread without gesture");
  - their times never decrease along the chain ("gesture 12.4 before anticipation 12.5");
  - `result` is present exactly when the phase is a terminal, and result >= every stage;
  - channel, phase and stage names are the known ones;
  - the same execution seen in several dumps never changes a stamp it already had, and never goes
    back from a terminal to running.
--require (big actions, REQUIRED below): an entry that FINISHED must reach its required stage
(the whole chain up to it). Cancelled, failed and still-running entries are checked for order only:
an interrupted action legitimately stops early.

Union of dumps: dumps are read in `frame` order (file name when absent). An execution is identified
by (session, request_id, step, action, channel, stage, t.intent): the five fields of the entry plus
its intent stamp, because MIKU's own actions (request_id 0) repeat with the same five fields; the
session changes when her clock goes back (the scenario was reset and a new MIKU composed). Of the
copies of one execution the most complete is kept (more stamps, then a terminal phase).

A dump whose window (Miku.TIMELINE_MAX = 48 executions) is full and shares no execution with the
previous dump is reported as a possible gap (WARNING, not a failure): executions may have come and
gone between the two dumps unseen - dump more often.

Exit: 0 = every entry PASS; 1 = some entry FAIL; 2 = usage error, unreadable dump or no
causality data at all. The last line is always `causality=PASS|FAIL <passed>/<entries>`.
Python standard library only; never shipped (tools/ is excluded from the export).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

CHAIN = ["intent", "anticipation", "gesture", "thread", "hand", "matter"]
RESULT = "result"
STAGES = CHAIN + [RESULT]
ABBR = {"intent": "int", "anticipation": "ant", "gesture": "ges", "thread": "thr", "hand": "hnd",
        "matter": "mat", "result": "res"}
CHANNELS = {"main", "overlay", "follower", "task"}
TERMINALS = {"finished", "failed", "cancelled"}
PHASES = TERMINALS | {""}
EPS = 1e-6
# Miku.TIMELINE_MAX: executions kept in one dump.
WINDOW = 48

# "Big" actions for --require: (action, channel or None = any, needs a world stage) -> the last
# stage of the chain that a FINISHED execution must have reached. The required stage is the last
# one the action's beats (src/miku/actions) can produce:
#   WORK on the task channel with a world stage (GATHER, CORE, LAYERS, ADJUST): the matter answers
#       her hands -> matter. This includes the failure story (WORK {"fail": true}: the crack, the
#       collapse and the furious rebuild are task stages of the same work).
#   SUMMON_HANDS: call -> threads -> the hands answer the pull -> hand (no matter is touched).
#   EDIT_FILE: call -> thread -> editor hand -> the artifact is held/edited -> matter.
#   DISCARD: look/windup -> the flick -> gesture (no thread, no hand: the artifact vanishes).
#   The failure story's moods: FRUSTRATED (breath, shoulders, tapping), ANGRY (breath, the claws),
#       RECOVER (the long breath, the smoothing hand) -> gesture.
REQUIRED = [
    ("WORK", "task", True, "matter"),
    ("SUMMON_HANDS", None, False, "hand"),
    ("EDIT_FILE", None, False, "matter"),
    ("DISCARD", None, False, "gesture"),
    ("FRUSTRATED", None, False, "gesture"),
    ("ANGRY", None, False, "gesture"),
    ("RECOVER", None, False, "gesture"),
]


def required_stage(entry: dict) -> str:
    """The stage --require demands of `entry` ("" when it is not a big action)."""
    for action, channel, needs_stage, stage in REQUIRED:
        if entry.get("action") != action:
            continue
        if channel is not None and entry.get("channel") != channel:
            continue
        if needs_stage and not entry.get("stage"):
            continue
        return stage
    return ""


def dump_paths(inputs: list[str]) -> list[Path]:
    out: list[Path] = []
    for raw in inputs:
        p = Path(raw)
        if p.is_dir():
            out.extend(sorted(x for x in p.iterdir() if x.suffix == ".json" and x.is_file()))
        elif p.is_file():
            out.append(p)
        else:
            raise FileNotFoundError(f"{raw}: no such file or directory")
    return out


def miku_section(data: dict) -> dict | None:
    """MIKU's section of a dump (or the dump itself when it is a bare section). The section key
    is the node's inspect_section() or its name ("Miku"): matched without case, else the first
    section that carries a `causality` list."""
    if not isinstance(data, dict):
        return None
    sections = data.get("sections")
    if isinstance(sections, dict):
        named = [v for k, v in sections.items() if str(k).lower() == "miku"]
        others = [v for k, v in sections.items() if str(k).lower() != "miku"]
        for sec in named + others:
            if isinstance(sec, dict) and isinstance(sec.get("causality"), list):
                return sec
        return None
    if isinstance(data.get("causality"), list):
        return data
    return None


def stamps(entry: dict) -> dict:
    t = entry.get("t")
    return t if isinstance(t, dict) else {}


def score(entry: dict) -> tuple:
    return (len(stamps(entry)), 1 if entry.get("phase") in TERMINALS else 0)


class Execution:
    """One execution of an action, united across dumps."""

    def __init__(self, key: tuple, entry: dict, source: str) -> None:
        self.key = key
        self.entry = entry
        self.first = source
        self.last = source
        self.copies = 1
        self.conflicts: list[str] = []
        self._seen_terminal = entry.get("phase") if entry.get("phase") in TERMINALS else ""

    def add(self, entry: dict, source: str) -> None:
        self.copies += 1
        self.last = source
        old, new = stamps(self.entry), stamps(entry)
        for k in set(old) & set(new):
            if not _same(old[k], new[k]):
                self.conflicts.append(f"{k} changed {fmt(old[k])}->{fmt(new[k])} in {source}")
        if not (set(old) <= set(new) or set(new) <= set(old)):
            self.conflicts.append(f"stamps disagree in {source} ({sorted(old)} vs {sorted(new)})")
        phase = entry.get("phase")
        if self._seen_terminal and phase != self._seen_terminal:
            self.conflicts.append(f"phase {self._seen_terminal!r} became {phase!r} in {source}")
        if phase in TERMINALS and not self._seen_terminal:
            self._seen_terminal = phase
        if score(entry) > score(self.entry):
            self.entry = entry


def _same(a, b) -> bool:
    try:
        return abs(float(a) - float(b)) <= EPS
    except (TypeError, ValueError):
        return a == b


def fmt(v) -> str:
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return f"{float(v):.3f}"
    return str(v)


def check(entry: dict, require: bool) -> list[str]:
    """Reasons `entry` fails (empty = PASS)."""
    why: list[str] = []
    t = entry.get("t")
    if not isinstance(t, dict):
        return ["no stamps (t)"]
    channel, phase = entry.get("channel"), entry.get("phase")
    if channel not in CHANNELS:
        why.append(f"unknown channel {channel!r}")
    if phase not in PHASES:
        why.append(f"unknown phase {phase!r}")
    unknown = sorted(k for k in t if k not in STAGES)
    if unknown:
        why.append("unknown stage " + ", ".join(unknown))
    for k in STAGES:
        if k in t and not (isinstance(t[k], (int, float)) and not isinstance(t[k], bool)):
            why.append(f"{k} is not a time ({t[k]!r})")
            return why
    if "intent" not in t:
        why.append("no intent")
    prev = None
    for k in CHAIN:
        if k not in t:
            continue
        idx = CHAIN.index(k)
        if idx > 0 and CHAIN[idx - 1] not in t:
            why.append(f"{k} without {CHAIN[idx - 1]}")
        if prev is not None and float(t[k]) < float(t[prev]) - EPS:
            why.append(f"{k} {fmt(t[k])} before {prev} {fmt(t[prev])}")
        prev = k
    if RESULT in t:
        late = [k for k in CHAIN if k in t and float(t[k]) > float(t[RESULT]) + EPS]
        if late:
            why.append(f"result {fmt(t[RESULT])} before " + ", ".join(f"{k} {fmt(t[k])}" for k in late))
        if phase == "":
            why.append("result while still running")
    elif phase in TERMINALS:
        why.append(f"{phase} without result")
    if require and phase == "finished":
        need = required_stage(entry)
        if need:
            missing = [k for k in CHAIN[:CHAIN.index(need) + 1] if k not in t]
            if missing:
                why.append(f"required chain to {need}: missing " + ", ".join(missing))
    return why


def chain_text(entry: dict) -> str:
    """`int 12.300 ant +0.00 ges +0.05 ...`: intent absolute, the rest relative to it."""
    t = stamps(entry)
    base = t.get("intent")
    parts = []
    for k in STAGES:
        if k not in t:
            continue
        v = t[k]
        if k == "intent" or not isinstance(base, (int, float)) or not isinstance(v, (int, float)):
            parts.append(f"{ABBR[k]} {fmt(v)}")
        else:
            parts.append(f"{ABBR[k]} +{float(v) - float(base):.2f}")
    return " ".join(parts)


def load_executions(paths: list[Path]) -> tuple[list[Execution], dict]:
    docs = []
    stats = {"files": len(paths), "with_miku": 0, "sessions": 0}
    for i, p in enumerate(paths):
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            raise ValueError(f"{p}: cannot read ({e})") from e
        sec = miku_section(data)
        if sec is None:
            continue
        frame = data.get("frame") if isinstance(data, dict) else None
        docs.append((frame if isinstance(frame, (int, float)) else float("inf"), i, p, sec))
    docs.sort(key=lambda d: (d[0], d[1]))
    stats["with_miku"] = len(docs)
    found: dict[tuple, Execution] = {}
    order: list[Execution] = []
    session = 0
    last_clock = None
    prev_keys: set = set()
    stats["gaps"] = []
    for _frame, _i, p, sec in docs:
        clock = sec.get("clock")
        if isinstance(clock, (int, float)):
            if last_clock is not None and float(clock) < last_clock - EPS:
                session += 1
                prev_keys = set()
            last_clock = float(clock)
        keys = set()
        for e in sec["causality"]:
            if not isinstance(e, dict):
                continue
            key = (session, e.get("request_id"), e.get("step"), e.get("action"), e.get("channel"),
                   e.get("stage", ""), stamps(e).get("intent"))
            keys.add(key)
            if key in found:
                found[key].add(e, p.name)
            else:
                found[key] = Execution(key, e, p.name)
                order.append(found[key])
        # A full window that shares nothing with the previous dump: executions may have been
        # opened and evicted between the two dumps without being seen (dump more often).
        if prev_keys and len(keys) >= WINDOW and not keys & prev_keys:
            stats["gaps"].append(p.name)
        prev_keys = keys or prev_keys
    stats["sessions"] = session + 1 if docs else 0
    # Oldest first: by session, then intent (an entry without intent keeps its first-seen place).
    seen = {id(x): i for i, x in enumerate(order)}
    order.sort(key=lambda x: (x.key[0], _num(stamps(x.entry).get("intent"), seen[id(x)]), seen[id(x)]))
    return order, stats


def _num(v, fallback) -> float:
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else float(fallback)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Causality gate of MIKU's action timelines (dev inspector dumps).")
    ap.add_argument("inputs", nargs="+", help="dump files and/or directories of dumps")
    ap.add_argument("--require", action="store_true",
                    help="finished big actions (REQUIRED in this script) must reach their whole chain")
    ap.add_argument("--failures-only", action="store_true", help="print only the failing entries")
    args = ap.parse_args(argv)
    try:
        paths = dump_paths(args.inputs)
        execs, stats = load_executions(paths)
    except (FileNotFoundError, ValueError) as e:
        print(f"causality: {e}", file=sys.stderr)
        print("causality=FAIL 0/0")
        return 2
    if not execs:
        print(f"causality: no timeline entry: {stats['files']} file(s), {stats['with_miku']} with a MIKU "
              "section (sections.Miku|miku.causality), all empty or absent.", file=sys.stderr)
        print("causality=FAIL 0/0")
        return 2

    rows = []
    passed = 0
    big = big_ok = 0
    for n, ex in enumerate(execs, 1):
        e = ex.entry
        why = check(e, args.require) + ex.conflicts
        need = required_stage(e) if args.require else ""
        if need and e.get("phase") == "finished":
            big += 1
            big_ok += 0 if any(w.startswith("required chain") for w in why) else 1
        ok = not why
        passed += 1 if ok else 0
        rows.append((n, ex, ok, why, need))

    header = f"{'#':>3} {'S':>1} {'req':>4} {'stp':>3} {'action':<13} {'channel':<8} {'stage':<7} {'phase':<9} " \
             f"{'verdict':<7} chain"
    print(header)
    print("-" * len(header))
    for n, ex, ok, why, need in rows:
        if args.failures_only and ok:
            continue
        e = ex.entry
        req = f" [req {ABBR[need]}]" if need and e.get("phase") == "finished" else ""
        print(f"{n:>3} {ex.key[0]:>1} {str(e.get('request_id')):>4} {str(e.get('step')):>3} "
              f"{str(e.get('action')):<13} {str(e.get('channel')):<8} {str(e.get('stage') or '-'):<7} "
              f"{str(e.get('phase') or 'running'):<9} {'PASS' if ok else 'FAIL':<7} {chain_text(e)}{req}")
        for w in why:
            print(f"{'':>8}-> {w}")
    failed = len(rows) - passed
    phases = {}
    for _n, ex, _ok, _why, _need in rows:
        ph = ex.entry.get("phase") or "running"
        phases[ph] = phases.get(ph, 0) + 1
    print("-" * len(header))
    print(f"causality: {len(rows)} executions from {stats['with_miku']}/{stats['files']} dumps "
          f"({stats['sessions']} session(s)) - " + ", ".join(f"{k} {v}" for k, v in sorted(phases.items())))
    if stats["gaps"]:
        print(f"causality: WARNING possible gap before {len(stats['gaps'])} dump(s) (a full window with nothing "
              f"in common with the previous dump; dump more often): " + ", ".join(stats["gaps"][:5]))
    if args.require:
        print(f"causality: --require: {big_ok}/{big} finished big actions with their whole chain"
              + ("" if big else " (WARNING: none seen)"))
    print(f"causality: {passed} PASS, {failed} FAIL")
    verdict = "PASS" if failed == 0 else "FAIL"
    print(f"causality={verdict} {passed}/{len(rows)}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
