#!/usr/bin/env bash
# Runs the real game (real renderer) with --smoke-test: the ORIGIN CHAMBER demo is
# played at 8x, then pause and reset are exercised. Exit 0 = PASS.
# Fails on: RESULT=FAIL, missing RESULT line (e.g. a script failed to load),
# any SCRIPT ERROR / Parse Error in the log, a `modules=N/M` line with N != M (a world module
# — entity, fx or camera script — failed to load), or the TIMEOUT (seconds) expiring.
#   tools/smoke_test.sh                         run from project sources
#   tools/smoke_test.sh --pack <exe|pck>        run the pack embedded in an export
#                                              (e.g. build/windows/KoriumUniverse.exe)
set -euo pipefail
cd "$(dirname "$0")/.."
pack=""
if [ "${1:-}" = "--pack" ]; then pack="$2"; shift 2; fi
TIMEOUT="${TIMEOUT:-240}"
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if [ -n "$pack" ]; then
  cmd=(tools/godot.sh --main-pack "$pack" -- --smoke-test "$@")
else
  cmd=(tools/godot.sh --path . -- --smoke-test "$@")
fi
set +e
timeout "$TIMEOUT" tools/_display.sh "${cmd[@]}" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [ "$status" -eq 124 ]; then echo "smoke_test: TIMEOUT after ${TIMEOUT}s" >&2; exit 1; fi
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
  echo "smoke_test: script errors in log — failing." >&2; exit 1
fi
modules_line="$(grep -oE "^modules=[0-9]+/[0-9]+" "$log" | tail -n1 || true)"
if [ -z "$modules_line" ]; then echo "smoke_test: no modules= line." >&2; exit 1; fi
loaded="${modules_line#modules=}"; total="${loaded#*/}"; loaded="${loaded%/*}"
if [ "$loaded" != "$total" ]; then
  echo "smoke_test: only $loaded of $total world modules loaded — failing." >&2; exit 1
fi
grep -q "^RESULT=PASS" "$log" || { echo "smoke_test: no RESULT=PASS line." >&2; exit 1; }
exit "$status"
