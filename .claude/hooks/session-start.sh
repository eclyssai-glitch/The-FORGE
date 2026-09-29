#!/bin/bash
# SessionStart hook (Claude Code on the web only): installs Godot 4.7.2 + export
# templates and the software-rendering stack so tests, smoke runs, evidence
# captures and the Windows export all work in the cloud container.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi
cd "$CLAUDE_PROJECT_DIR"
if ! command -v xvfb-run >/dev/null || ! dpkg -s mesa-vulkan-drivers >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb xauth mesa-vulkan-drivers libgl1-mesa-dri libvulkan1 zip >/dev/null 2>&1 \
    || { apt-get update -qq >/dev/null 2>&1 || true; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb xauth mesa-vulkan-drivers libgl1-mesa-dri libvulkan1 zip >/dev/null; }
fi
tools/setup_godot.sh
# Offline asset tooling (ADR-013): sculpt bake + audio synthesis. Not needed by the game itself.
if [ ! -x /opt/korium-py/bin/python ] || ! /opt/korium-py/bin/python -c 'import numpy, scipy, skimage' >/dev/null 2>&1; then
  python3 -m venv /opt/korium-py >/dev/null 2>&1 \
    && /opt/korium-py/bin/pip install -q numpy scipy scikit-image >/dev/null 2>&1 \
    || echo "warning: /opt/korium-py tooling venv unavailable (only needed to regenerate assets)" >&2
fi
godot --headless --import --path . >/dev/null 2>&1 || true
