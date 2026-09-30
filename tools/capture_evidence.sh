#!/usr/bin/env bash
# Captures evidence screenshots of every demo phase and every mode from the real
# game (see src/core/automation.gd CAPTURES, or CAPTURES_GENESIS with --scenario=genesis).
#   tools/capture_evidence.sh docs/evidence/loop-02 [--quality=<low|medium|high|ultra|auto>]
#                                                   [--capture-only=<prefix>]
#                                                   [--resolution=WxH] [--timeout=<s>]
#                                                   [--scenario=<origin_chamber|genesis>]
# --scenario=<id>: play that scenario (passed to the game) and expect its capture list.
# Style frames (GENESIS, 1920x1080, HUD hidden) have their own script: tools/style_frames.sh.
# Quality: HIGH unless --quality= is given (evidence judges the target profile — a desktop with a
# discrete GPU; AUTO would pick LOW under Xvfb + llvmpipe); --quality=auto keeps the detection.
# Each "[capture]" log line names the level used.
# --resolution=WxH: window (and Xvfb screen) size, default 1600x900 (e.g. 1280x720).
# Total time limit: --timeout=<s> or CAPTURE_TIMEOUT (default 900 s).
# Exit 0 = every expected PNG (CAPTURES, filtered by --capture-only) was written by this run —
# even if the engine hung on exit and had to be killed ("forced exit after captures" on
# stderr). Exit 1 = some PNG is missing. The game's whole process session (godot,
# xvfb-run, Xvfb) is always killed at the end: nothing is left running.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/_proc.sh
dir="${1:-docs/evidence/latest}"; shift || true
timeout_s="${CAPTURE_TIMEOUT:-900}"
grace_s="${CAPTURE_GRACE:-15}"
only=""
resolution="1600x900"
list="CAPTURES"
quality="high"
game_args=()
for a in "$@"; do
  case "$a" in
    --scenario=genesis) list="CAPTURES_GENESIS"; game_args+=("$a") ;;
    --scenario=*) game_args+=("$a") ;;
    --timeout=*) timeout_s="${a#--timeout=}" ;;
    --resolution=*) resolution="${a#--resolution=}" ;;
    --capture-only=*) only="${a#--capture-only=}"; game_args+=("$a") ;;
    --quality=*) quality="${a#--quality=}" ;;
    *) game_args+=("$a") ;;
  esac
done
# HIGH unless asked otherwise (see the header); "auto" keeps the GPU detection.
game_args+=("--quality=${quality}")
if ! [[ "$resolution" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
  echo "capture_evidence: --resolution must be WxH (e.g. 1280x720), got '$resolution'." >&2; exit 2
fi
mkdir -p "$dir"

# Expected files: names of the scenario's list in src/core/automation.gd (CAPTURES or
# CAPTURES_GENESIS), same prefix filter as the game.
expected=()
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ -z "$only" ] || [[ "$name" == "$only"* ]]; then expected+=("$dir/$name.png"); fi
done < <(awk -v head="const ${list}: Array = [" '$0 == head {f=1; next} f && /^\]/{exit} f' src/core/automation.gd \
  | sed -nE 's/^[[:space:]]*\["([^"]+)".*/\1/p')
if [ "${#expected[@]}" -eq 0 ]; then
  echo "capture_evidence: no capture matches --capture-only='$only'." >&2; exit 1
fi

work="$(mktemp -d)"
stamp="$work/stamp"; log="$work/godot.log"
PROC_ON_EXIT='rm -rf "$work"'
touch "$stamp"
sleep 1  # PNGs of this run must be strictly newer than the stamp (1 s mtime granularity safe)

## True when every expected PNG exists, is non-empty and was written by this run.
all_written() {
  local f
  for f in "${expected[@]}"; do
    [ -s "$f" ] && [ "$f" -nt "$stamp" ] || return 1
  done
}

timeout -k 10 300 tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
proc_start "$log" env SCREEN="${SCREEN:-${resolution}x24}" tools/_display.sh \
  tools/godot.sh "${GODOT_AUDIO_FLAGS[@]}" --path . --resolution "$resolution" -- "--capture=$dir" "${game_args[@]}"
proc_supervise "$timeout_s" "$grace_s" all_written

missing=()
for f in "${expected[@]}"; do
  { [ -s "$f" ] && [ "$f" -nt "$stamp" ]; } || missing+=("$f")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "capture_evidence: ${#missing[@]} of ${#expected[@]} captures missing (${PROC_OUTCOME}, status ${PROC_STATUS}):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi
case "$PROC_OUTCOME" in
  forced) echo "capture_evidence: forced exit after captures (engine did not quit ${grace_s}s after the last one)." >&2 ;;
  timeout) echo "capture_evidence: forced exit after captures (total timeout ${timeout_s}s)." >&2 ;;
  *) [ "$PROC_STATUS" -eq 0 ] || echo "capture_evidence: engine exited with status $PROC_STATUS after all captures." >&2 ;;
esac
echo "capture_evidence: ${#expected[@]}/${#expected[@]} captures in $dir (${resolution})"
ls -la "${expected[@]}"
