#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME_SHELL="$CONFIG_HOME/quickshell/nbshell"
UMBRIEL_DIR="$CONFIG_HOME/umbriel"

if ! command -v umbriel >/dev/null 2>&1; then
    echo "Umbriel is not installed. Build or install it first:" >&2
    echo "  https://github.com/noctalia-dev/umbriel" >&2
    exit 1
fi
if [ ! -f "$UMBRIEL_DIR/nbshell-nested.toml" ] || [ ! -f "$RUNTIME_SHELL/shell.qml" ]; then
    echo "nbshell Umbriel assets are missing; run ./install.sh first." >&2
    exit 1
fi

QS="$(command -v qs || command -v quickshell)"
SPIKE_DIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/nbshell-umbriel.XXXXXX")"
trap 'rm -rf -- "$SPIKE_DIR"' EXIT
cp -a "$RUNTIME_SHELL/." "$SPIKE_DIR/"

# A copied Quickshell path has its own instance identity, so the nested shell
# cannot collide with the daily nbshell process running on the parent display.
shell_command="env NBSHELL_COMPOSITOR=umbriel $QS -p $SPIKE_DIR/shell.qml"
exec umbriel -c "$UMBRIEL_DIR/nbshell-nested.toml" -s "$shell_command"
