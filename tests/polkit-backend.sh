#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${1:?Pass an absolute quickshell binary path}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp "$root/tests/polkit/regression.py" "$root/tests/polkit/backend-shell.qml" "$scratch/"
gcc -shared -fPIC "$root/tests/polkit/backend-mock.c" -o "$scratch/mock.so" $(pkg-config --cflags --libs gobject-2.0)
dbus-run-session -- python "$scratch/regression.py" "$binary"
