#!/usr/bin/env bash
# DEV ONLY — Loop 5 r2 native migration: records the SAME MIKU sequence (r2_compare.tscn) with the
# legacy and the native body (Movie Maker, --fixed-fps 30, Forward+ on Xvfb/llvmpipe), with dev
# inspector dumps of both, then builds the side-by-side video (OLD left | NEW right, ffmpeg hstack)
# and contact sheets.
# Usage: tools/research/native_character/r2_record.sh OUT_DIR [seconds=42] [view=torso|full] [WxH=960x540]
set -euo pipefail
cd "$(dirname "$0")/../../.."
out="${1:?OUT_DIR}"
secs="${2:-42}"
view="${3:-torso}"
res="${4:-960x540}"
w="${res%x*}"
h="${res#*x}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
timeout 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
for body in legacy native; do
  rm -rf "$out/inspect_${view}_$body"
  SCREEN="${res}x24" timeout 7000 tools/_display.sh tools/godot.sh --audio-driver Dummy --path . --resolution "$res" \
    --write-movie "$tmp/$body.avi" --fixed-fps 30 res://tools/research/native_character/r2_compare.tscn -- \
    --body="$body" --seconds="$secs" --view="$view" --inspect="$out/inspect_${view}_$body" --inspect-every=2 \
    > "$tmp/$body.log" 2>&1 || true
  grep -E "^\[r2\]|SCRIPT ERROR" "$tmp/$body.log" | tee "$out/run_${view}_$body.txt"
  grep -q "^\[r2\] done" "$tmp/$body.log" || { echo "r2_record: $body did not finish" >&2; tail -30 "$tmp/$body.log" >&2; exit 1; }
done
label() { echo "drawtext=text='$1':x=w-tw-14:y=h-th-12:fontcolor=white:fontsize=22:box=1:boxcolor=black@0.55:boxborderw=6"; }
ffmpeg -y -loglevel error -i "$tmp/legacy.avi" -i "$tmp/native.avi" -filter_complex \
  "[0:v]scale=${w}:${h},$(label 'OLD  legacy')[a];[1:v]scale=${w}:${h},$(label 'NEW  native AnimationTree')[b];[a][b]hstack=inputs=2[v]" \
  -map "[v]" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart "$out/step1_${view}_side_by_side.mp4"
for body in legacy native; do
  ffmpeg -y -loglevel error -i "$tmp/$body.avi" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart \
    "$out/step1_${view}_$body.mp4"
done
# contact sheet of the side-by-side: one frame every 2 s
ffmpeg -y -loglevel error -i "$out/step1_${view}_side_by_side.mp4" -vf \
  "fps=0.5,scale=640:-1,drawtext=text='%{pts\:hms}':x=8:y=8:fontcolor=white:fontsize=16:box=1:boxcolor=black@0.5,tile=3x7" \
  -frames:v 1 -q:v 4 "$out/step1_${view}_contact.jpg"
ls -la "$out"
