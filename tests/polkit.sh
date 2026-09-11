#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/shell"
for module in Common Widgets Polkit; do ln -s "$root/shell/$module" "$scratch/shell/$module"; done
cp "$root/tests/polkit/authdialog-probe.qml" "$scratch/shell/shell.qml"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_CONFIG_HOME="$scratch/config" \
    timeout 15 qs -p "$scratch/shell/shell.qml" > "$scratch/result" 2>&1 || { cat "$scratch/result"; exit 1; }
cat "$scratch/result"
rg -q 'POLKIT_DIALOG_TESTS_PASS 8' "$scratch/result"
! rg -q 'POLKIT_DIALOG_TESTS_FAIL|Failed to load configuration' "$scratch/result"
