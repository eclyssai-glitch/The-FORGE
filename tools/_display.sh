#!/usr/bin/env bash
# Runs a command with a display: directly if $DISPLAY is set (or on Windows/macOS),
# otherwise through xvfb-run (software rendering via Mesa llvmpipe/lavapipe).
set -euo pipefail
if [ -n "${DISPLAY:-}" ] || [ "$(uname -s)" != "Linux" ]; then
  exec "$@"
fi
if ! command -v xvfb-run >/dev/null; then
  echo "No DISPLAY and xvfb-run not installed (apt-get install xvfb)." >&2
  exit 127
fi
exec xvfb-run -a -s "-screen 0 ${SCREEN:-1600x900x24}" "$@"
