#!/usr/bin/env bash
# SPIKE: records the native-character demo with the Movie Maker (Forward+, xvfb/llvmpipe on Linux),
# converts to MP4 and builds a contact sheet.
# Usage: tools/research/native_character/record.sh OUT_DIR [seconds] [demo user args, e.g. --strip=modifiers]
# (the project maximizes the window, so frames come out at the Xvfb screen size, 1600x900)
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:-docs/research/evidence/native-character}"
secs="${2:-12}"
shift 2 || true
extra=("$@")
mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
timeout 1500 tools/_display.sh tools/godot.sh --audio-driver Dummy --path . --resolution 1280x720 \
  --write-movie "$tmp/demo.avi" --fixed-fps 30 res://tools/research/native_character/nc_demo.tscn -- --seconds="$secs" "${extra[@]}" \
  2>&1 | grep -E "MEASURE|ERROR|SCRIPT" | grep -v "ALSA\|ERR_CANT_OPEN" || true
ffmpeg -y -loglevel error -i "$tmp/demo.avi" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$out/native_character_demo.mp4"
# contact sheet: one frame every 0.5 s (24 tiles), with timestamps
ffmpeg -y -loglevel error -i "$tmp/demo.avi" -vf "fps=2,scale=426:-1,drawtext=text='%{pts\:hms}':x=8:y=8:fontcolor=white:fontsize=16:box=1:boxcolor=black@0.5,tile=4x6" -frames:v 1 "$out/contact_sheet.png"
# key frames at full size
for s in 1.0 2.0 2.9 3.3 5.0 6.25 6.5 7.0 7.6 8.3 9.2 11.0; do
  ffmpeg -y -loglevel error -ss "$s" -i "$tmp/demo.avi" -frames:v 1 "$out/frame_${s}s.png"
done
ls -la "$out"
