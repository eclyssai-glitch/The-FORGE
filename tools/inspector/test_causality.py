#!/usr/bin/env python3
"""DEVELOPMENT ONLY - tests of tools/inspector/causality.py against the fixtures in
tools/inspector/testdata/causality/. Standard library only:

  python3 tools/inspector/test_causality.py        (also run by tests/integration/test_causality_gate.gd)
"""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import causality  # noqa: E402

DATA = HERE / "testdata" / "causality"


def run(*args: str) -> tuple[int, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = causality.main([str(a) for a in args])
    return code, out.getvalue() + err.getvalue()


def last_line(text: str) -> str:
    return text.strip().splitlines()[-1]


class CausalityGate(unittest.TestCase):
    def test_pass_run_unites_dumps(self) -> None:
        code, out = run(DATA / "pass_run")
        self.assertEqual(code, 0, out)
        # 7 executions: the ACKNOWLEDGE evicted from the 2nd dump is kept; the two own
        # ACKNOWLEDGEs (request 0, same fields) stay apart by their intent stamps.
        self.assertEqual(last_line(out), "causality=PASS 7/7")
        self.assertIn("2 dumps", out)

    def test_most_complete_copy_kept(self) -> None:
        execs, _ = causality.load_executions(causality.dump_paths([str(DATA / "pass_run")]))
        summon = [x for x in execs if x.entry["action"] == "SUMMON_HANDS"]
        self.assertEqual(len(summon), 1)
        self.assertEqual(summon[0].entry["phase"], "finished")
        self.assertIn("hand", summon[0].entry["t"])
        self.assertEqual(summon[0].copies, 2)

    def test_require_passes_complete_and_interrupted(self) -> None:
        code, out = run(DATA / "pass_run", "--require")
        self.assertEqual(code, 0, out)
        self.assertIn("2/2 finished big actions", out)  # WORK GATHER (task) + SUMMON_HANDS

    def test_stage_before_previous_fails(self) -> None:
        code, out = run(DATA / "fail_order.json")
        self.assertEqual(code, 1, out)
        self.assertIn("gesture 1.100 before anticipation 1.200", out)
        self.assertEqual(last_line(out), "causality=FAIL 0/1")

    def test_stage_without_previous_fails(self) -> None:
        code, out = run(DATA / "fail_skip.json")
        self.assertEqual(code, 1, out)
        self.assertIn("thread without gesture", out)

    def test_result_before_stage_fails(self) -> None:
        code, out = run(DATA / "fail_result.json")
        self.assertEqual(code, 1, out)
        self.assertIn("result 5.000 before matter 6.000", out)

    def test_require_incomplete_big_action(self) -> None:
        code, out = run(DATA / "require_incomplete.json")
        self.assertEqual(code, 0, out)  # order is right: only --require asks for the whole chain
        code, out = run(DATA / "require_incomplete.json", "--require")
        self.assertEqual(code, 1, out)
        self.assertIn("required chain to hand: missing hand", out)
        # The failed EDIT_FILE is checked for order only.
        self.assertEqual(last_line(out), "causality=FAIL 1/2")

    def test_changed_stamp_between_dumps_fails(self) -> None:
        code, out = run(DATA / "conflict")
        self.assertEqual(code, 1, out)
        self.assertIn("gesture changed 1.200->1.400", out)

    def test_clock_going_back_is_a_new_session(self) -> None:
        code, out = run(DATA / "reset")
        self.assertEqual(code, 0, out)
        self.assertIn("2 session(s)", out)
        self.assertEqual(last_line(out), "causality=PASS 2/2")

    def test_no_data_is_an_error(self) -> None:
        code, out = run(DATA / "empty.json")
        self.assertEqual(code, 2, out)
        code, out = run(DATA / "does_not_exist")
        self.assertEqual(code, 2, out)

    def test_full_window_without_overlap_warns_gap(self) -> None:
        def dump(frame: int, start: float) -> dict:
            entries = [{"request_id": 0, "step": 0, "action": "THINK", "channel": "main", "stage": "",
                        "phase": "finished", "t": {"intent": start + i, "anticipation": start + i, "result": start + i + 0.5}}
                       for i in range(causality.WINDOW)]
            return {"frame": frame, "sections": {"Miku": {"clock": start + 60.0, "causality": entries}}}
        with tempfile.TemporaryDirectory() as tmp:
            for n, (frame, start) in enumerate([(10, 0.0), (20, 100.0)]):
                Path(tmp, f"d{n}.json").write_text(json.dumps(dump(frame, start)), encoding="utf-8")
            code, out = run(tmp)
        self.assertEqual(code, 0, out)  # a warning, not a failure
        self.assertIn("WARNING possible gap before 1 dump(s)", out)
        self.assertEqual(last_line(out), f"causality=PASS {2 * causality.WINDOW}/{2 * causality.WINDOW}")

    def test_check_rules(self) -> None:
        ok = {"channel": "main", "phase": "", "t": {"intent": 1.0, "anticipation": 1.0}}
        self.assertEqual(causality.check(ok, True), [])
        self.assertIn("no intent", causality.check({"channel": "main", "phase": "", "t": {"anticipation": 1.0}}, False))
        self.assertIn("finished without result",
                      causality.check({"channel": "main", "phase": "finished", "t": {"intent": 1.0}}, False))
        self.assertIn("result while still running",
                      causality.check({"channel": "main", "phase": "", "t": {"intent": 1.0, "result": 2.0}}, False))
        self.assertIn("unknown channel 'side'", causality.check({"channel": "side", "phase": "", "t": {"intent": 1.0}}, False))
        self.assertIn("unknown stage wobble",
                      causality.check({"channel": "main", "phase": "", "t": {"intent": 1.0, "wobble": 1.0}}, False))

    def test_required_table(self) -> None:
        self.assertEqual(causality.required_stage({"action": "WORK", "channel": "task", "stage": "CORE"}), "matter")
        self.assertEqual(causality.required_stage({"action": "WORK", "channel": "task", "stage": ""}), "")
        self.assertEqual(causality.required_stage({"action": "WORK", "channel": "main", "stage": ""}), "")
        self.assertEqual(causality.required_stage({"action": "SUMMON_HANDS", "channel": "main"}), "hand")
        self.assertEqual(causality.required_stage({"action": "LOOK_AT_USER", "channel": "overlay"}), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
