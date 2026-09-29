#!/usr/bin/env bash
# Exports the Windows x86_64 build to build/windows/ and zips it with a checksum.
# Requires Godot 4.7.2 export templates (tools/setup_godot.sh, or Editor > Manage
# Export Templates). The output folder is recreated on every run, and the zip is
# reproducible (fixed timestamps = last commit time, no extra attributes).
#   tools/export_windows.sh            release build
#   tools/export_windows.sh --debug    debug build (with console wrapper)
set -euo pipefail
cd "$(dirname "$0")/.."
mode="--export-release"
[ "${1:-}" = "--debug" ] && mode="--export-debug"
out="build/windows"
rm -rf "$out"
mkdir -p "$out"
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
tools/godot.sh --headless --path . "$mode" "Windows Desktop" "$out/KoriumUniverse.exe"
test -s "$out/KoriumUniverse.exe"
cp licenses/*.txt "$out/"
epoch="$(git log -1 --format=%ct 2>/dev/null || date +%s)"
find "$out" -exec touch -h -d "@$epoch" {} +
version="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
zip_name="KoriumUniverse-${version}-windows-x86_64.zip"
( cd build && rm -f "$zip_name" "$zip_name.sha256" \
  && find windows -type f | LC_ALL=C sort | zip -q -X -9 "$zip_name" -@ \
  && sha256sum "$zip_name" > "$zip_name.sha256" )
ls -la "$out" build/*.zip*
cat "build/$zip_name.sha256"
