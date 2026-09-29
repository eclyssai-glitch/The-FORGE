#!/usr/bin/env bash
# Records the v0.1.0 video review (docs/contracts/review-video.md): the scripted tour
# res://tools/review/review_tour.tscn plays the real game (real renderer, real HUD input) under
# the Movie Maker (fixed 30 fps, game time), then ffmpeg encodes H.264.
#   tools/record_review.sh                          full review, 1600x900
#       -> build/review/korium_review.avi -> build/review/korium_universe_review_v0.1.0.mp4
#   tools/record_review.sh --until=15 --resolution=960x540   short validation recording
#       -> build/review/korium_review_preview.avi / korium_universe_review_v0.1.0_preview.mp4
# Options: --until=<s> (game seconds; passed to the tour as --review-until), --resolution=WxH
# (default 1600x900), --timeout=<s> (default REVIEW_TIMEOUT or 5400: software rendering takes
# ~0.4 s or more per frame, the full review is ~4000 frames). After the tour prints
# "[review] done" the engine gets REVIEW_GRACE s (default 120) to finish the AVI and exit.
# The game's whole process session (godot, xvfb-run, Xvfb) is always killed at the end.
# Engine log: build/review/record.log (or record_preview.log). Needs ffmpeg/ffprobe on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/_proc.sh
resolution="1600x900"
until_s=""
timeout_s="${REVIEW_TIMEOUT:-5400}"
grace_s="${REVIEW_GRACE:-120}"
for a in "$@"; do
  case "$a" in
    --until=*) until_s="${a#--until=}" ;;
    --resolution=*) resolution="${a#--resolution=}" ;;
    --timeout=*) timeout_s="${a#--timeout=}" ;;
    *) echo "record_review: unknown option '$a'." >&2; exit 2 ;;
  esac
done
if ! [[ "$resolution" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
  echo "record_review: --resolution must be WxH (e.g. 1600x900), got '$resolution'." >&2; exit 2
fi
if [ -n "$until_s" ] && ! [[ "$until_s" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "record_review: --until must be seconds, got '$until_s'." >&2; exit 2
fi
for tool in ffmpeg ffprobe; do
  command -v "$tool" >/dev/null || { echo "record_review: $tool not found." >&2; exit 127; }
done

out="$PWD/build/review"
mkdir -p "$out"
tour_args=()
if [ -n "$until_s" ]; then
  avi="$out/korium_review_preview.avi"
  mp4="$out/korium_universe_review_v0.1.0_preview.mp4"
  log="$out/record_preview.log"
  tour_args+=("--review-until=$until_s")
else
  avi="$out/korium_review.avi"
  mp4="$out/korium_universe_review_v0.1.0.mp4"
  log="$out/record.log"
fi
rm -f "$avi" "$mp4"

tour_done() { grep -q "^\[review\] done" "$log"; }

timeout -k 10 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
started="$(date +%s)"
proc_start "$log" env SCREEN="${resolution}x24" tools/_display.sh \
  tools/godot.sh --path . --write-movie "$avi" --fixed-fps 30 --resolution "$resolution" \
  res://tools/review/review_tour.tscn -- "${tour_args[@]}"
proc_supervise "$timeout_s" "$grace_s" tour_done
elapsed=$(( $(date +%s) - started ))

if [ "$PROC_OUTCOME" = "timeout" ]; then
  echo "record_review: TIMEOUT after ${timeout_s}s (see $log)." >&2; exit 1
fi
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
  echo "record_review: script errors in $log — failing." >&2; exit 1
fi
tour_done || { echo "record_review: the tour did not finish (no '[review] done' in $log)." >&2; exit 1; }
[ "$PROC_OUTCOME" = "forced" ] && echo "record_review: forced exit after the tour (engine did not quit ${grace_s}s after done)." >&2
[ -s "$avi" ] || { echo "record_review: $avi was not written." >&2; exit 1; }

# The Movie Maker writes frames at the project window size (1600x900) whatever --resolution is;
# the MP4 is scaled to the requested resolution (a no-op for the full review).
ffmpeg -y -v error -i "$avi" -an -vf "scale=${resolution/x/:}:flags=lanczos" -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  -movflags +faststart "$mp4"

duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$mp4")"
frames="$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets \
  -of default=nw=1:nk=1 "$mp4")"
size_b="$(stat -c %s "$mp4")"
echo "record_review: recorded in ${elapsed}s ($PROC_OUTCOME) · $(grep "^\[review\] done" "$log" | tail -n1)"
echo "record_review: $avi ($(du -h "$avi" | cut -f1))"
dims="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$mp4")"
printf 'record_review: %s — %s, %.1f s, %s frames, %.1f MB\n' "$mp4" "$dims" "$duration" "$frames" \
  "$(echo "$size_b" | awk '{print $1 / 1048576}')"
