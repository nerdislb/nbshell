#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT/native/umbriel-workspaces.c"
PROTOCOL="/usr/share/wayland-protocols/staging/ext-workspace/ext-workspace-v1.xml"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/bin/umbriel-workspaces"

if [ ! -f "$SOURCE" ]; then
    # Installed runtime: native sources live beside shell/ in the data store.
    SOURCE="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/native/umbriel-workspaces.c"
fi
for command in wayland-scanner cc pkg-config; do
    command -v "$command" >/dev/null || { echo "Skipping native workspace helper: $command is missing." >&2; exit 0; }
done
[ -f "$PROTOCOL" ] || { echo "Skipping native workspace helper: ext-workspace-v1.xml is missing." >&2; exit 0; }
[ -f "$SOURCE" ] || { echo "Skipping native workspace helper: source is missing." >&2; exit 0; }

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-native.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
wayland-scanner client-header "$PROTOCOL" "$BUILD_DIR/ext-workspace-v1-client-protocol.h"
wayland-scanner private-code "$PROTOCOL" "$BUILD_DIR/ext-workspace-v1-protocol.c"
cc -std=c17 -O2 -Wall -Wextra -Werror -I"$BUILD_DIR" \
    "$SOURCE" "$BUILD_DIR/ext-workspace-v1-protocol.c" \
    $(pkg-config --cflags --libs wayland-client) -o "$BUILD_DIR/umbriel-workspaces"
mkdir -p "$(dirname "$DEST")"
install -m 755 "$BUILD_DIR/umbriel-workspaces" "$DEST"
echo "Workspace helper -> $DEST"
