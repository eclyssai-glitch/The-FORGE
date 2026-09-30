#!/usr/bin/env bash
# Renders the sculpture previews in the real Godot renderer (Forward+, xvfb when headless):
# clay albedo x baked vertex AO, warm key with shadow + cold rim (studio), soft lateral light
# (*_soft) and hard frontal light (*_hard). Never part of the game: this folder has its own
# throwaway Godot project and is ignored by the main one (.gdignore).
#   tools/sculpt/preview/render_previews.sh [MESH_DIR] [OUT_DIR]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$ROOT/tools/sculpt/preview"
MESH="${1:-$ROOT/assets/meshes}"
OUT="${2:-$ROOT/tools/sculpt/previews}"
PY=/opt/korium-py/bin/python
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
"$PY" "$HERE/views.py" "$TMP"
for pair in "miku_body:miku" "hand_left:left" "hand_right:right"; do
  obj="${pair%%:*}"; views="${pair##*:}"
  "$ROOT/tools/_display.sh" "$ROOT/tools/godot.sh" --path "$HERE" --script preview.gd -- \
    "--obj=$MESH/$obj.obj" "--out=$OUT" "--views=$TMP/views_final_$views.json" 2>&1 \
    | grep -E "^saved|SCRIPT ERROR" || true
done
