#!/usr/bin/env bash
# Runs the real game (real renderer) with --smoke-test: the active scenario (ORIGIN CHAMBER by
# default; extra arguments reach the game, e.g. `tools/smoke_test.sh --scenario=genesis`) is
# played at 8x, then pause and reset are exercised, then the native UI (transport buttons
# Start/Pause/Reset of group "ui_transport", visible "demo_badge" with "DEMO" in every mode).
# The world must be composed for the scenario with every module (`modules=N/N`, AudioDirector
# included); GENESIS also requires the audio anchors planet/miku/hands (`audio=present anchors=`).
# Without a sound card (Linux, no /dev/snd) the Dummy audio driver is used (tools/_proc.sh).
# Exit 0 = PASS. A HUD without those groups fails (`ui=absent`) unless SMOKE_ALLOW_MISSING_UI=1,
# which passes --allow-missing-ui to the game (only for branches where the UI does not exist yet).
# Fails on: RESULT=FAIL, missing RESULT line (e.g. a script failed to load),
# any SCRIPT ERROR / Parse Error in the log, a `modules=N/M` line with N != M (a world module
# — entity, fx or camera script — failed to load), or the TIMEOUT (seconds, default 240) expiring.
# If the engine prints its RESULT line but then hangs on exit, it gets SMOKE_GRACE s (default 15)
# and is then killed ("forced exit after result" on stderr; the verdict comes from the log).
# The game's whole process session (godot, xvfb-run, Xvfb) is always killed at the end.
#   tools/smoke_test.sh                         run from project sources
#   tools/smoke_test.sh --pack <exe|pck>        run the pack embedded in an export
#                                              (e.g. build/windows/KoriumUniverse.exe)
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/_proc.sh
pack=""
if [ "${1:-}" = "--pack" ]; then pack="$2"; shift 2; fi
TIMEOUT="${TIMEOUT:-240}"
game_flags=(--smoke-test)
if [ "${SMOKE_ALLOW_MISSING_UI:-0}" = "1" ]; then game_flags+=(--allow-missing-ui); fi
GRACE="${SMOKE_GRACE:-15}"
timeout -k 10 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
log="$(mktemp)"
PROC_ON_EXIT='rm -f "$log"'
trap 'rm -f "$log"' EXIT
if [ -n "$pack" ]; then
  cmd=(tools/godot.sh "${GODOT_AUDIO_FLAGS[@]}" --main-pack "$pack" -- "${game_flags[@]}" "$@")
else
  cmd=(tools/godot.sh "${GODOT_AUDIO_FLAGS[@]}" --path . -- "${game_flags[@]}" "$@")
fi
has_result() { grep -qE "^RESULT=(PASS|FAIL)" "$log"; }
proc_start "$log" tools/_display.sh "${cmd[@]}"
proc_supervise "$TIMEOUT" "$GRACE" has_result
status=$PROC_STATUS
if [ "$PROC_OUTCOME" = "timeout" ]; then echo "smoke_test: TIMEOUT after ${TIMEOUT}s" >&2; exit 1; fi
if [ "$PROC_OUTCOME" = "forced" ]; then
  echo "smoke_test: forced exit after result (engine did not quit ${GRACE}s after RESULT)." >&2
  status=0  # the verdict below comes from the RESULT line
elif [ "$status" -ge 128 ] && has_result; then
  # Killed by a signal after reporting (e.g. automation.gd's own exit watchdog).
  echo "smoke_test: forced exit after result (engine killed by signal $((status - 128)))." >&2
  status=0
fi
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
  echo "smoke_test: script errors in log — failing." >&2; exit 1
fi
modules_line="$(grep -oE "^modules=[0-9]+/[0-9]+" "$log" | tail -n1 || true)"
if [ -z "$modules_line" ]; then echo "smoke_test: no modules= line." >&2; exit 1; fi
loaded="${modules_line#modules=}"; total="${loaded#*/}"; loaded="${loaded%/*}"
if [ "$loaded" != "$total" ]; then
  echo "smoke_test: only $loaded of $total world modules loaded — failing." >&2; exit 1
fi
ui_line="$(grep -oE "^ui=[a-z]+" "$log" | tail -n1 || true)"
if [ -z "$ui_line" ]; then echo "smoke_test: no ui= line." >&2; exit 1; fi
if [ "$ui_line" = "ui=absent" ] && [ "${SMOKE_ALLOW_MISSING_UI:-0}" != "1" ]; then
  echo "smoke_test: native UI absent (ui=absent) — failing (SMOKE_ALLOW_MISSING_UI=1 tolerates it)." >&2; exit 1
fi
grep -q "^RESULT=PASS" "$log" || { echo "smoke_test: no RESULT=PASS line." >&2; exit 1; }
exit "$status"
