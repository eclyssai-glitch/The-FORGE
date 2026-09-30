#!/usr/bin/env bash
# Saves the GENESIS style frames (src/core/style_frames.gd: the CameraDirector's
# style_frame_poses() or StyleFrames.DEFAULT_POSES; >= 6 frames, HUD hidden, 1920x1080) from the
# real game into <dir>.
#   tools/style_frames.sh docs/evidence/loop-04/style_frames [--quality=high] [--timeout=<s>]
# Total time limit: --timeout=<s> or STYLE_TIMEOUT (default 600 s).
# Exit 0 = the manifest (style_frames.txt) and every PNG it lists were written by this run, there
# are at least 6 of them and each is 1920x1080. The game's whole process session (godot,
# xvfb-run, Xvfb) is always killed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/_proc.sh
dir="${1:-docs/evidence/latest/style_frames}"; shift || true
timeout_s="${STYLE_TIMEOUT:-600}"
grace_s="${STYLE_GRACE:-15}"
min_frames=6
width=1920; height=1080
game_args=()
for a in "$@"; do
  case "$a" in
    --timeout=*) timeout_s="${a#--timeout=}" ;;
    *) game_args+=("$a") ;;
  esac
done
mkdir -p "$dir"
manifest="$dir/style_frames.txt"

work="$(mktemp -d)"
stamp="$work/stamp"; log="$work/godot.log"
PROC_ON_EXIT='rm -rf "$work"'
touch "$stamp"
sleep 1  # files of this run must be strictly newer than the stamp

manifest_written() { [ -s "$manifest" ] && [ "$manifest" -nt "$stamp" ]; }

## Width and height of a PNG (IHDR, big-endian) as "W H".
png_size() {
  od -An -tu1 -j16 -N8 "$1" | awk '{print $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8}'
}

timeout -k 10 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
proc_start "$log" env SCREEN="${SCREEN:-${width}x${height}x24}" tools/_display.sh \
  tools/godot.sh "${GODOT_AUDIO_FLAGS[@]}" --path . --resolution "${width}x${height}" -- --scenario=genesis "--style-frames=$dir" "${game_args[@]}"
proc_supervise "$timeout_s" "$grace_s" manifest_written

if ! manifest_written; then
  echo "style_frames: no manifest written by this run (${PROC_OUTCOME}, status ${PROC_STATUS})." >&2
  exit 1
fi
count=0; bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  p="$dir/$f"
  if ! { [ -s "$p" ] && [ "$p" -nt "$stamp" ]; }; then
    echo "style_frames: missing $p" >&2; bad=1; continue
  fi
  size="$(png_size "$p")"
  if [ "$size" != "$width $height" ]; then
    echo "style_frames: $p is ${size/ /x}, expected ${width}x${height}" >&2; bad=1
  fi
  count=$((count + 1))
done < "$manifest"
if [ "$count" -lt "$min_frames" ]; then
  echo "style_frames: only $count frames (minimum $min_frames)." >&2; bad=1
fi
[ "$bad" -eq 0 ] || exit 1
case "$PROC_OUTCOME" in
  forced|timeout) echo "style_frames: forced exit after the frames (engine did not quit by itself)." >&2 ;;
esac
echo "style_frames: $count frames (${width}x${height}) in $dir"
ls -la "$dir"
