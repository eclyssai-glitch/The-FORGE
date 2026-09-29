#!/usr/bin/env bash
# Captures evidence screenshots of every demo phase and every mode from the real
# game (see src/core/automation.gd CAPTURES).
#   tools/capture_evidence.sh docs/evidence/loop-02 [--quality=high]
set -euo pipefail
cd "$(dirname "$0")/.."
dir="${1:-docs/evidence/latest}"; shift || true
mkdir -p "$dir"
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
SCREEN="${SCREEN:-1600x900x24}" tools/_display.sh tools/godot.sh --path . --resolution 1600x900 -- "--capture=$dir" "$@"
ls -la "$dir"
