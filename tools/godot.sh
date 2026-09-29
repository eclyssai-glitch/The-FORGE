#!/usr/bin/env bash
# Resolves the Godot 4.7 binary: $GODOT, then `godot` on PATH.
set -euo pipefail
GODOT_BIN="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT_BIN" ]; then
  echo "Godot 4.7 not found. Set GODOT=/path/to/Godot_v4.7.2-stable binary." >&2
  exit 127
fi
exec "$GODOT_BIN" "$@"
