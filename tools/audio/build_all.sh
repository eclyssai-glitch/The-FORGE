#!/usr/bin/env bash
# Regenerates every audio asset of KORIUM UNIVERSE from code (see docs/AUDIO.md):
#   offline synthesis (Python + numpy/scipy, fixed seeds) -> 32-bit float WAV in build/audio/wav
#   -> OGG Vorbis (libvorbis q5, 48 kHz, stereo) in assets/audio -> ebur128 level table.
# No samples, no network, no services.
#   tools/audio/build_all.sh           build everything
#   tools/audio/build_all.sh --check   rebuild the WAVs only and compare with tools/audio/wav.sha256
#                                      (the synthesis is bit-reproducible; the OGG bytes may differ
#                                      between libvorbis/ffmpeg builds, so they are not hashed)
#   tools/audio/build_all.sh --update-hashes   build everything and rewrite wav.sha256
# Python: $KORIUM_PY or /opt/korium-py/bin/python (venv with numpy + scipy, see ADR-013).
set -euo pipefail
cd "$(dirname "$0")/../.."
PY="${KORIUM_PY:-/opt/korium-py/bin/python}"
mode="${1:-build}"
wav="build/audio/wav"
out="assets/audio"
mkdir -p "$wav" "$out"
touch build/audio/.gdignore  # keep Godot from importing the intermediate WAVs
export PYTHONDONTWRITEBYTECODE=1

"$PY" tools/audio/synth_ambience.py "$wav/amb_cosmos_loop.wav"
"$PY" tools/audio/synth_sfx.py "$wav"

if [ "$mode" = "--check" ]; then
  (cd "$wav" && sha256sum -c ../../../tools/audio/wav.sha256)
  exit $?
fi
if [ "$mode" = "--update-hashes" ]; then
  (cd "$wav" && sha256sum ./*.wav | sed 's# \./# #') > tools/audio/wav.sha256
fi

for f in "$wav"/*.wav; do
  name="$(basename "$f" .wav)"
  ffmpeg -hide_banner -loglevel error -y -i "$f" -map_metadata -1 -fflags +bitexact \
    -flags:a +bitexact -c:a libvorbis -q:a 5 -ar 48000 -ac 2 "$out/$name.ogg"
done

"$PY" tools/audio/measure.py "$out"/*.ogg
du -ch "$out"/*.ogg | tail -n1
