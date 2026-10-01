#!/usr/bin/env bash
# Turns a Movie Maker recording (the AVI carries the game's audio) into the audible proof:
#   tools/audio/render_proof.sh RECORDING.avi [OUT_DIR]
# OUT_DIR (default tools/audio/proof) receives genesis_mix_spectrogram.png (1600x600),
# genesis_mix_waveform.png, genesis_mix.ogg (q2, small) and prints the ebur128 levels plus the
# band analysis (ebur128 below / above 300 Hz, band energy per GENESIS moment; tools/audio/bands.py).
set -euo pipefail
cd "$(dirname "$0")/../.."
avi="$1"
out="${2:-tools/audio/proof}"
PY="${KORIUM_PY:-/opt/korium-py/bin/python}"
mkdir -p "$out" build/audio
touch build/audio/.gdignore
wav="build/audio/genesis_mix.wav"
ffmpeg -hide_banner -loglevel error -y -i "$avi" -vn -c:a pcm_f32le "$wav"
ffmpeg -hide_banner -loglevel error -y -i "$wav" -lavfi \
  "showspectrumpic=s=1600x600:legend=1:scale=log:fscale=log:start=30:stop=16000" \
  "$out/genesis_mix_spectrogram.png"
ffmpeg -hide_banner -loglevel error -y -i "$wav" -lavfi \
  "showwavespic=s=1600x400:split_channels=1:colors=0xd9b36c|0x9fb8e8" \
  "$out/genesis_mix_waveform.png"
ffmpeg -hide_banner -loglevel error -y -i "$wav" -map_metadata -1 -fflags +bitexact \
  -flags:a +bitexact -c:a libvorbis -q:a 2 "$out/genesis_mix.ogg"
"$PY" tools/audio/measure.py "$wav"
PYTHONDONTWRITEBYTECODE=1 "$PY" tools/audio/bands.py "$wav"
du -h "$out/genesis_mix.ogg"
