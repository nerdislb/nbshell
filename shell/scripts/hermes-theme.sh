#!/usr/bin/env bash
# Generate one Hermes skin from nbshell's normalized palette and activate it.
set -uo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PALETTE="${NBSHELL_PALETTE:-$CONFIG_HOME/nbshell/palette.sh}"
HERMES_BIN="${NBSHELL_HERMES_BIN:-}"

[ -r "$PALETTE" ] || {
    printf 'nbshell Hermes theme: palette not found: %s\n' "$PALETTE" >&2
    exit 1
}
# shellcheck source=/dev/null
. "$PALETTE"

if [ -z "$HERMES_BIN" ]; then
    HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
fi
[ -n "$HERMES_BIN" ] && [ -x "$HERMES_BIN" ] || {
    printf 'nbshell Hermes theme: hermes command not found\n' >&2
    exit 1
}

# Theme files are data, but validate every interpolated value before emitting
# YAML so a malformed custom palette can never become configuration syntax.
hex_color() {
    local name="$1" value="${!1:-}"
    if [[ ! "$value" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        printf 'nbshell Hermes theme: invalid %s color: %s\n' "$name" "$value" >&2
        exit 1
    fi
}

for color in \
    NB_BG NB_BG_DARK NB_BG_LIGHT NB_FG NB_FG_DIM NB_FG_BRIGHT \
    NB_ACCENT NB_MUTED NB_SELECTION NB_RED NB_GREEN NB_YELLOW NB_BLUE \
    NB_MAGENTA NB_CYAN NB_BRIGHT_RED NB_BRIGHT_YELLOW; do
    hex_color "$color"
done

HERMES_ROOT="${HERMES_HOME:-$HOME/.hermes}"
SKIN_DIR="$HERMES_ROOT/skins"
SKIN_PATH="$SKIN_DIR/nbshell.yaml"
mkdir -p "$SKIN_DIR"
tmp="$(mktemp "$SKIN_DIR/.nbshell.yaml.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

cat >"$tmp" <<EOF
name: nbshell
description: Generated from the active nbshell theme

colors:
  background: "$NB_BG"
  ui_accent: "$NB_ACCENT"
  banner_accent: "$NB_ACCENT"
  banner_title: "$NB_FG_BRIGHT"
  banner_text: "$NB_FG"
  ui_text: "$NB_FG"
  ui_label: "$NB_ACCENT"
  banner_dim: "$NB_FG_DIM"
  banner_border: "$NB_MUTED"
  ui_border: "$NB_MUTED"
  ui_tool: "$NB_ACCENT"
  ui_thinking: "$NB_FG_DIM"
  ui_ok: "$NB_GREEN"
  ui_warn: "$NB_YELLOW"
  ui_error: "$NB_RED"
  diff_added: "$NB_BG_LIGHT"
  diff_removed: "$NB_BG_LIGHT"
  diff_added_word: "$NB_GREEN"
  diff_removed_word: "$NB_RED"
  syntax_string: "$NB_GREEN"
  syntax_number: "$NB_CYAN"
  syntax_keyword: "$NB_MAGENTA"
  syntax_comment: "$NB_FG_DIM"
  prompt: "$NB_FG"
  input_rule: "$NB_ACCENT"
  response_border: "$NB_ACCENT"
  status_bar_bg: "$NB_BG_DARK"
  status_bar_text: "$NB_FG"
  status_bar_strong: "$NB_FG_BRIGHT"
  status_bar_dim: "$NB_FG_DIM"
  status_bar_good: "$NB_GREEN"
  status_bar_warn: "$NB_YELLOW"
  status_bar_bad: "$NB_BRIGHT_YELLOW"
  status_bar_critical: "$NB_BRIGHT_RED"
  session_label: "$NB_ACCENT"
  session_border: "$NB_MUTED"
  voice_status_bg: "$NB_BG_DARK"
  selection_bg: "$NB_SELECTION"
  completion_menu_bg: "$NB_BG_DARK"
  completion_menu_current_bg: "$NB_SELECTION"
  completion_menu_meta_bg: "$NB_BG_DARK"
  completion_menu_meta_current_bg: "$NB_SELECTION"

branding:
  agent_name: Hermes Agent
  prompt_symbol: "❯"

tool_prefix: "┊"
EOF
chmod 644 "$tmp"
mv -f -- "$tmp" "$SKIN_PATH"
trap - EXIT

# A changed active skin is watched live. Only touch config when nbshell is not
# active yet; this keeps subsequent theme changes free of redundant rewrites.
active="$($HERMES_BIN config get display.skin 2>/dev/null || true)"
if [ "$active" != "nbshell" ]; then
    "$HERMES_BIN" config set display.skin nbshell >/dev/null
fi
