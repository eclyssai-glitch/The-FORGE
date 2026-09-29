#!/usr/bin/env bash
# Imports the project (builds the class cache) and runs every GUT test headless.
# Fails when any test fails OR when any script fails to load: GUT alone only
# warns about test scripts it cannot parse, which would hide broken suites.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
set +e
tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if grep -qE "Parse Error|Failed to load script|does not extend GutTest|SCRIPT ERROR" "$log"; then
  echo "run_tests: script load/parse errors detected — failing." >&2
  exit 1
fi
exit "$status"
