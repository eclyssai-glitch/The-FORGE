#!/usr/bin/env bash
# Records the real game playing the GENESIS scene with sound (Loop 4 r1): the tour
# res://tools/review/genesis_tour.tscn runs the game with --scenario=genesis, the cinematic camera
# and the forced quality (HIGH by default) from T+0 to the end (56 s) + 4 s of breath, under the
# Movie Maker (fixed 30 fps, game time; the engine's audio mix is written into the AVI). ffmpeg
# then encodes MP4 H.264 + AAC in build/review/ and the script prints duration, size, streams and
# the EBU R128 loudness of the recorded audio.
#   tools/record_genesis.sh                                  full take, 1920x1080, HUD on
#   tools/record_genesis.sh --hud=off                        clean take (the DEMO badge stays)
#   tools/record_genesis.sh --until=12 --resolution=960x540  short preview
# Options:
#   --hud=on|off         HUD visible (default on); the DEMO MODE badge is always visible
#   --resolution=WxH     window, Xvfb screen and video size (default 1920x1080)
#   --until=<s>          stop after <s> tour seconds (the demo starts at 0.5 s); output *_preview
#   --from=<s>           seek the demo to T+<s> before it starts (inspect a stretch); output *_from<s>
#   --quality=<level>    low|medium|high|ultra (default high)
#   --crf=<n>            x264 quality (default 18)
#   --timeout=<s>        total limit (default GENESIS_TIMEOUT or 5400: software rendering takes
#                        ~1 s or more per 1080p frame; the full take is ~1800 frames)
# Output: build/review/genesis_<W>x<H>_hud-<on|off>[_preview].{avi,mp4,log}.
# After the tour prints "[genesis] done" the engine gets GENESIS_GRACE s (default 120) to finish
# the AVI and exit. The game's whole process session (godot, xvfb-run, Xvfb) is always killed at
# the end. Needs ffmpeg/ffprobe on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/_proc.sh
resolution="1920x1080"
until_s=""
from_s=""
hud="on"
quality="high"
crf="18"
timeout_s="${GENESIS_TIMEOUT:-5400}"
grace_s="${GENESIS_GRACE:-120}"
for a in "$@"; do
  case "$a" in
    --until=*) until_s="${a#--until=}" ;;
    --from=*) from_s="${a#--from=}" ;;
    --resolution=*) resolution="${a#--resolution=}" ;;
    --hud=*) hud="${a#--hud=}" ;;
    --quality=*) quality="${a#--quality=}" ;;
    --crf=*) crf="${a#--crf=}" ;;
    --timeout=*) timeout_s="${a#--timeout=}" ;;
    *) echo "record_genesis: unknown option '$a'." >&2; exit 2 ;;
  esac
done
if ! [[ "$resolution" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
  echo "record_genesis: --resolution must be WxH (e.g. 1920x1080), got '$resolution'." >&2; exit 2
fi
if [ -n "$until_s" ] && ! [[ "$until_s" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "record_genesis: --until must be seconds, got '$until_s'." >&2; exit 2
fi
if [ -n "$from_s" ] && ! [[ "$from_s" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "record_genesis: --from must be seconds, got '$from_s'." >&2; exit 2
fi
case "$hud" in on|off) ;; *) echo "record_genesis: --hud must be on or off, got '$hud'." >&2; exit 2 ;; esac
case "$quality" in low|medium|high|ultra) ;; *)
  echo "record_genesis: --quality must be low|medium|high|ultra, got '$quality'." >&2; exit 2 ;; esac
[[ "$crf" =~ ^[0-9]+$ ]] || { echo "record_genesis: --crf must be an integer, got '$crf'." >&2; exit 2; }
for tool in ffmpeg ffprobe; do
  command -v "$tool" >/dev/null || { echo "record_genesis: $tool not found." >&2; exit 127; }
done

out="$PWD/build/review"
mkdir -p "$out"
base="$out/genesis_${resolution}_hud-${hud}"
tour_args=(--scenario=genesis "--hud=$hud" "--quality=$quality" "--size=$resolution")
if [ -n "$from_s" ]; then
  base="${base}_from${from_s}"
  tour_args+=("--genesis-from=$from_s")
fi
if [ -n "$until_s" ]; then
  base="${base}_preview"
  tour_args+=("--genesis-until=$until_s")
fi
avi="$base.avi"; mp4="$base.mp4"; log="$base.log"
rm -f "$avi" "$mp4"

tour_done() { grep -q "^\[genesis\] done" "$log"; }

timeout -k 10 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true

# The Movie Maker sizes the AVI from display/window/size/viewport_width/height: it ignores
# --resolution and later window resizes (frames get rescaled to the project's 1600x900). A Godot
# override.cfg in the project root sets the size for this run only; it is read once at startup and
# removed as soon as the engine has started (and by the exit trap in any case). An existing
# override.cfg is never touched: the script refuses to run.
override="$PWD/override.cfg"
if [ -e "$override" ]; then
  echo "record_genesis: $override already exists (another recording running?) — refusing to overwrite it." >&2
  exit 1
fi
trap 'rm -f "$override"' EXIT
printf '; Written by tools/record_genesis.sh for one recording; removed once the engine has started.\n[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/size/mode=0\n' \
  "${resolution%x*}" "${resolution#*x}" > "$override"
PROC_ON_EXIT='rm -f "$override"'
movie_started() { grep -qE '^(Movie Maker mode enabled|\[genesis\] start)' "$log"; }
started="$(date +%s)"
# The Movie Maker always mixes audio through the engine's Dummy driver (no sound card needed).
proc_start "$log" env SCREEN="${resolution}x24" tools/_display.sh \
  tools/godot.sh --path . --write-movie "$avi" --fixed-fps 30 --resolution "$resolution" \
  res://tools/review/genesis_tour.tscn -- "${tour_args[@]}"
for _ in $(seq 1 180); do
  movie_started && break
  sleep 1
done
rm -f "$override"
proc_supervise "$timeout_s" "$grace_s" tour_done
movie_line="$(grep -m1 '^Movie Maker mode enabled' "$log" || true)"
if [[ "$movie_line" != *" ${resolution/x/×} "* ]]; then
  echo "record_genesis: the Movie Maker did not record at ${resolution} (${movie_line:-no Movie Maker line})." >&2
  exit 1
fi
elapsed=$(( $(date +%s) - started ))

if [ "$PROC_OUTCOME" = "timeout" ]; then
  echo "record_genesis: TIMEOUT after ${timeout_s}s (see $log)." >&2; exit 1
fi
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
  echo "record_genesis: script errors in $log — failing." >&2; exit 1
fi
tour_done || { echo "record_genesis: the tour did not finish (no '[genesis] done' in $log)." >&2; exit 1; }
[ "$PROC_OUTCOME" = "forced" ] && echo "record_genesis: forced exit after the tour (engine did not quit ${grace_s}s after done)." >&2
[ -s "$avi" ] || { echo "record_genesis: $avi was not written." >&2; exit 1; }
astreams="$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$avi" | wc -l)"
[ "$astreams" -ge 1 ] || { echo "record_genesis: $avi has no audio stream." >&2; exit 1; }

# The scale is a no-op when the Movie Maker already recorded at the requested size.
ffmpeg -y -v error -i "$avi" -vf "scale=${resolution/x/:}:flags=lanczos" \
  -c:v libx264 -preset slow -crf "$crf" -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$mp4"

vinfo="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate \
  -of csv=p=0 "$mp4")"
ainfo="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels \
  -of csv=p=0 "$mp4")"
[ -n "$ainfo" ] || { echo "record_genesis: $mp4 has no audio stream." >&2; exit 1; }
duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$mp4")"
frames="$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets \
  -of default=nw=1:nk=1 "$mp4")"
size_b="$(stat -c %s "$mp4")"
loud="$(ffmpeg -hide_banner -nostats -i "$mp4" -vn -af ebur128=peak=true -f null - 2>&1 \
  | awk '/Summary:/{s=1} s && /I:|LRA:|Peak:/{gsub(/^ +/,""); printf "%s  ", $0}')"

echo "record_genesis: recorded in ${elapsed}s ($PROC_OUTCOME) · $(grep "^\[genesis\] done" "$log" | tail -n1)"
echo "record_genesis: $avi ($(du -h "$avi" | cut -f1))"
printf 'record_genesis: %s — %.2f s, %s frames, %.1f MB\n' "$mp4" "$duration" "$frames" \
  "$(echo "$size_b" | awk '{print $1 / 1048576}')"
echo "record_genesis: video $vinfo · audio $ainfo"
echo "record_genesis: audio ebur128 $loud"
