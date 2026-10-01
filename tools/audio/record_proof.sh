#!/usr/bin/env bash
# Records the audible proof of the GENESIS mix and renders it (spectrogram, waveform, levels):
#   tools/audio/record_proof.sh [OUT_DIR]        (default tools/audio/proof)
# The rig res://tools/audio/proof_rig/genesis_audio_proof.tscn runs the real Simulation (GENESIS
# from 0) and the real AudioDirector under the Movie Maker (--fixed-fps 30, 62 s of game time;
# the AVI carries the engine's own audio mix, 48 kHz). The picture is a bare camera at 320x180:
# the proof is the sound (the game's own recording with picture is tools/record_genesis.sh).
# Then tools/audio/render_proof.sh turns the AVI into the proof files.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:-tools/audio/proof}"
frames="${PROOF_FRAMES:-1860}"
mkdir -p build/audio
touch build/audio/.gdignore
avi="$PWD/build/audio/genesis_proof.avi"
log="build/audio/record_proof.log"
rm -f "$avi"
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
tools/_display.sh tools/godot.sh --path . --resolution 320x180 --write-movie "$avi" \
  --fixed-fps 30 --quit-after "$frames" res://tools/audio/proof_rig/genesis_audio_proof.tscn \
  > "$log" 2>&1 || true
if ! grep -q "\[audio-proof\] GENESIS started" "$log"; then
  echo "record_proof: the rig did not start (see $log)." >&2
  exit 1
fi
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  echo "record_proof: script errors during the recording (see $log)." >&2
  exit 1
fi
[ -s "$avi" ] || { echo "record_proof: no AVI written." >&2; exit 1; }
tools/audio/render_proof.sh "$avi" "$out"
