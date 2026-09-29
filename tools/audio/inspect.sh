#!/usr/bin/env bash
# Renders one spectrogram + waveform sheet per sound for visual inspection (not versioned):
#   tools/audio/inspect.sh [SRC_DIR] [OUT_DIR]
# SRC_DIR defaults to build/audio/wav (the WAVs from build_all.sh); OUT_DIR to build/audio/inspect.
set -euo pipefail
cd "$(dirname "$0")/../.."
src="${1:-build/audio/wav}"
out="${2:-build/audio/inspect}"
mkdir -p "$out"
shopt -s nullglob
for f in "$src"/*.wav "$src"/*.ogg; do
  name="$(basename "${f%.*}")"
  ffmpeg -hide_banner -loglevel error -y -i "$f" -filter_complex \
    "[0:a]asplit[a][b];[a]showspectrumpic=s=900x320:legend=0:scale=log:fscale=log:start=30:stop=16000[s];[b]showwavespic=s=900x120:split_channels=1:scale=sqrt:colors=0xd9b36c|0x9fb8e8[w];[s][w]vstack" \
    "$out/$name.png"
  echo "$out/$name.png"
done
