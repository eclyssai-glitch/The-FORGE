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
godot --headless --import --path . >/dev/null 2>&1 || true
