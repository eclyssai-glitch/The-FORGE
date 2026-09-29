#!/usr/bin/env bash
# Installs Godot 4.7.2-stable (Linux editor) and the Windows/Linux x86_64 export
# templates, verifying the official SHA512 sums. Idempotent.
#   GODOT_HOME   install dir for the editor (default /opt/godot)
set -euo pipefail
VERSION="4.7.2-stable"
TPL_VERSION="4.7.2.stable"
BASE="https://github.com/godotengine/godot-builds/releases/download/${VERSION}"
GODOT_HOME="${GODOT_HOME:-/opt/godot}"
EDITOR_ZIP="Godot_v${VERSION}_linux.x86_64.zip"
TPZ="Godot_v${VERSION}_export_templates.tpz"
TPL_DIR="${HOME}/.local/share/godot/export_templates/${TPL_VERSION}"

mkdir -p "$GODOT_HOME" "$TPL_DIR"
cd "$GODOT_HOME"

fetch() { [ -s "$1" ] || { curl -fsSL --retry 4 -o "$1.part" "$BASE/$1" && mv "$1.part" "$1"; }; }
verify() { grep " $1\$" SHA512-SUMS.txt | sha512sum -c --quiet - || { mv "$1" "$1.bad"; echo "SHA512 mismatch: $1" >&2; exit 1; }; }

fetch SHA512-SUMS.txt
if [ ! -x "Godot_v${VERSION}_linux.x86_64" ]; then
  fetch "$EDITOR_ZIP" && verify "$EDITOR_ZIP"
  unzip -o -q "$EDITOR_ZIP"
fi
ln -sf "$GODOT_HOME/Godot_v${VERSION}_linux.x86_64" /usr/local/bin/godot 2>/dev/null || true

if [ ! -f "$TPL_DIR/windows_release_x86_64.exe" ]; then
  fetch "$TPZ" && verify "$TPZ"
  unzip -o -q -j "$TPZ" 'templates/version.txt' 'templates/windows_*_x86_64*' \
    'templates/linux_*.x86_64' -d "$TPL_DIR"
fi

# Offline class reference (signatures, members, enums — including built-in types)
# of this exact version. Descriptions are not included by this binary: read them
# at https://docs.godotengine.org/en/4.7/.
if [ ! -f "$GODOT_HOME/doc/doc/classes/String.xml" ]; then
  mkdir -p "$GODOT_HOME/doc"
  ( cd "$GODOT_HOME/doc" && "$GODOT_HOME/Godot_v${VERSION}_linux.x86_64" --headless --doctool . >/dev/null 2>&1 || true )
fi
echo "Godot $("$GODOT_HOME/Godot_v${VERSION}_linux.x86_64" --version) ready; templates in $TPL_DIR"
