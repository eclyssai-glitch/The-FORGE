#!/usr/bin/env bash
# Exports the Windows x86_64 build to build/windows/ and zips it with a checksum.
# Requires Godot 4.7.2 export templates (Editor > Manage Export Templates, or
# ~/.local/share/godot/export_templates/4.7.2.stable/windows_*_x86_64*.exe).
#   tools/export_windows.sh            release build
#   tools/export_windows.sh --debug    debug build (with console wrapper)
set -euo pipefail
cd "$(dirname "$0")/.."
mode="--export-release"
[ "${1:-}" = "--debug" ] && mode="--export-debug"
out="build/windows"
mkdir -p "$out"
tools/godot.sh --headless --import --path . >/dev/null 2>&1 || true
tools/godot.sh --headless --path . "$mode" "Windows Desktop" "$out/KoriumUniverse.exe"
test -s "$out/KoriumUniverse.exe"
cp licenses/*.txt "$out/"
version="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
zip_name="KoriumUniverse-${version}-windows-x86_64.zip"
( cd build && rm -f "$zip_name" && zip -q -r -9 "$zip_name" windows && sha256sum "$zip_name" > "$zip_name.sha256" )
ls -la "$out" build/*.zip*
