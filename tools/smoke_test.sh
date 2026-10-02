#!/usr/bin/env bash
# Runs the real game (real renderer) with --smoke-test: the active scenario (ORIGIN CHAMBER by
# default; extra arguments reach the game, e.g. `tools/smoke_test.sh --scenario=genesis`) is
# played at 8x, then pause and reset are exercised, then the native UI (transport buttons
# Start/Pause/Reset of group "ui_transport", visible "demo_badge" with "DEMO" in every mode).
# The world must be composed for the scenario with every module (`modules=N/N`, AudioDirector
# included); GENESIS also requires the audio anchors planet/miku/hands (`audio=present anchors=`).
# Without a sound card (Linux, no /dev/snd) the Dummy audio driver is used (tools/_proc.sh).
# LIVING (`--scenario=living`, Loop 5): played at 8x to the end, then real interaction requests
# (clicks on MIKU/a world, call-line texts: attention, world target, config patches, REQUIRES_ASSET,
# SEMANTIC without provider) must end with their expected status, the configuration must change
# and be restored exactly (`config_mutated=true`, `config_reverted=true`), seek is refused and
# reset recomposes the scene. Its time is a BUDGET DERIVED by the game (docs/BUILD.md): duration of
# the roteiro + MIKU's estimates of the test plans + margin; the smoke FAILS itself when it uses more.
# Each request is awaited by its own request_id (interaction_started -> interaction_reported) up to
# its plan's worst case (sum of the step timeouts); the report lists request_id, steps, real vs
# estimated durations, failures, timeouts and cancellations. The game prints
# `smoke_deadline_seconds=N` (worst case of a correct run) first; this script then uses
# N + SMOKE_BOOT_SLACK (default 30) as its hang guard instead of TIMEOUT (only if larger).
# Exit 0 = PASS. A HUD without those groups fails (`ui=absent`) unless SMOKE_ALLOW_MISSING_UI=1,
# which passes --allow-missing-ui to the game (only for branches where the UI does not exist yet).
# SMOKE_ALLOW_MISSING_MODULES=1 (LIVING only) passes --allow-missing-modules: missing world modules
# are reported as WARN and `modules=N/M` with N != M does not fail (only for branches where the
# animator's LIVING modules do not exist yet).
# Causality gate (LIVING, docs/BUILD.md "Gate de causalidade"): the game samples MIKU's causal
# timeline into a temporary directory (--causality-dir, every 0.5 s from the roteiro to the end of
# the requests) and reports `causality_samples=N`; this script then runs
# tools/inspector/causality.py --require on the samples, prints its failing rows and summary and
# the line `causality=PASS|FAIL n/m`, and FAILS on causality=FAIL. Without python3 the gate is
# reported as `causality=SKIPPED` (WARN) and does not fail. SMOKE_CAUSALITY=0 turns it off.
# Fails on: RESULT=FAIL, missing RESULT line (e.g. a script failed to load),
# any SCRIPT ERROR / Parse Error in the log, a `modules=N/M` line with N != M (a world module
# — entity, fx or camera script — failed to load), or the TIMEOUT (seconds, default 240) expiring.
# If the engine prints its RESULT line but then hangs on exit, it gets SMOKE_GRACE s (default 15)
# and is then killed ("forced exit after result" on stderr; the verdict comes from the log).
# The game's whole process session (godot, xvfb-run, Xvfb) is always killed at the end.
#   tools/smoke_test.sh                         run from project sources
#   tools/smoke_test.sh --pack <exe|pck>        run the pack embedded in an export
#                                              (e.g. build/windows/KoriumUniverse.exe). The engine
#                                              runs from an empty temporary directory: with
#                                              --main-pack, res:// files missing from the pack are
#                                              read from the working directory, so running it from
#                                              the project would hide files the export left out
#                                              (e.g. tools/inspector would load).
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/_proc.sh
pack=""
if [ "${1:-}" = "--pack" ]; then pack="$2"; shift 2; fi
TIMEOUT="${TIMEOUT:-240}"
game_flags=(--smoke-test)
if [ "${SMOKE_ALLOW_MISSING_UI:-0}" = "1" ]; then game_flags+=(--allow-missing-ui); fi
if [ "${SMOKE_ALLOW_MISSING_MODULES:-0}" = "1" ]; then game_flags+=(--allow-missing-modules); fi
GRACE="${SMOKE_GRACE:-15}"
timeout -k 10 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
log="$(mktemp)"
rundir="$(mktemp -d)"
causdir="$(mktemp -d)"
PROC_ON_EXIT='rm -f "$log"; rm -rf "$rundir" "$causdir"'
trap 'rm -f "$log"; rm -rf "$rundir" "$causdir"' EXIT
if [ "${SMOKE_CAUSALITY:-1}" != "0" ]; then game_flags+=("--causality-dir=$causdir"); fi
if [ -n "$pack" ]; then
  [ -f "$pack" ] || { echo "smoke_test: pack $pack not found." >&2; exit 1; }
  pack_abs="$(cd "$(dirname "$pack")" && pwd)/$(basename "$pack")"
  cmd=(bash -c 'cd "$1" && shift && exec "$@"' _ "$rundir" "$PWD/tools/godot.sh" "${GODOT_AUDIO_FLAGS[@]}" \
    --main-pack "$pack_abs" -- "${game_flags[@]}" "$@")
else
  cmd=(tools/godot.sh "${GODOT_AUDIO_FLAGS[@]}" --path . -- "${game_flags[@]}" "$@")
fi
has_result() { grep -qE "^RESULT=(PASS|FAIL)" "$log"; }
BOOT_SLACK="${SMOKE_BOOT_SLACK:-30}"
# Hang guard derived by the game (LIVING): its announced worst case + boot slack, if above TIMEOUT.
derived_timeout() {
  local d
  d="$(grep -oE "^smoke_deadline_seconds=[0-9]+" "$log" | tail -n1 | cut -d= -f2 || true)"
  [ -n "$d" ] || return 0
  d=$((d + BOOT_SLACK))
  if [ "$d" -gt "$TIMEOUT" ]; then echo "$d"; else echo "$TIMEOUT"; fi
}
PROC_TIMEOUT_FN=derived_timeout
proc_start "$log" tools/_display.sh "${cmd[@]}"
proc_supervise "$TIMEOUT" "$GRACE" has_result
status=$PROC_STATUS
if [ "$PROC_OUTCOME" = "timeout" ]; then echo "smoke_test: TIMEOUT (hang guard $(derived_timeout || true) ${TIMEOUT}s)" >&2; exit 1; fi
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
if [ "$loaded" != "$total" ] && [ "${SMOKE_ALLOW_MISSING_MODULES:-0}" != "1" ]; then
  echo "smoke_test: only $loaded of $total world modules loaded — failing." >&2; exit 1
fi
ui_line="$(grep -oE "^ui=[a-z]+" "$log" | tail -n1 || true)"
if [ -z "$ui_line" ]; then echo "smoke_test: no ui= line." >&2; exit 1; fi
if [ "$ui_line" = "ui=absent" ] && [ "${SMOKE_ALLOW_MISSING_UI:-0}" != "1" ]; then
  echo "smoke_test: native UI absent (ui=absent) — failing (SMOKE_ALLOW_MISSING_UI=1 tolerates it)." >&2; exit 1
fi
grep -q "^RESULT=PASS" "$log" || { echo "smoke_test: no RESULT=PASS line." >&2; exit 1; }
# Causality gate: only when the game sampled MIKU's timeline (LIVING).
if grep -qE "^causality_samples=" "$log"; then
  if command -v python3 >/dev/null; then
    set +e
    caus_out="$(python3 tools/inspector/causality.py --require --failures-only "$causdir" 2>&1)"
    caus_status=$?
    set -e
    printf '%s\n' "$caus_out" | sed '$!s/^/smoke_test: /'
    if [ "$caus_status" -ne 0 ]; then
      echo "smoke_test: causality gate failed (status $caus_status) - failing." >&2; exit 1
    fi
  else
    echo "smoke_test: WARN python3 not found - causality=SKIPPED" >&2
  fi
fi
exit "$status"
