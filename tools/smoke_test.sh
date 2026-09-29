#!/usr/bin/env bash
# Runs the real game (real renderer) with --smoke-test: the ORIGIN CHAMBER demo is
# played at 8x, then pause and reset are exercised. Exit 0 = PASS.
#   tools/smoke_test.sh                         run from project sources
#   tools/smoke_test.sh --pack <exe|pck>        run the pack embedded in an export
#                                              (e.g. build/windows/KoriumUniverse.exe)
set -euo pipefail
cd "$(dirname "$0")/.."
pack=""
if [ "${1:-}" = "--pack" ]; then pack="$2"; shift 2; fi
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
if [ -n "$pack" ]; then
  tools/_display.sh tools/godot.sh --main-pack "$pack" -- --smoke-test "$@"
else
  tools/_display.sh tools/godot.sh --path . -- --smoke-test "$@"
fi
