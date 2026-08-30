#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export HERMES_HOME="$HOME/.hermes-test"
mkdir -p "$XDG_CONFIG_HOME/nbshell" "$TEST_DIR/bin"

cat >"$XDG_CONFIG_HOME/nbshell/palette.sh" <<'EOF'
NB_THEME='test-theme'
NB_MODE='dark'
NB_BG='#101820'
NB_BG_DARK='#081018'
NB_BG_LIGHT='#263746'
NB_FG='#f0f4f8'
NB_FG_DIM='#8b9aaa'
NB_FG_BRIGHT='#ffffff'
NB_ACCENT='#42a5f5'
NB_MUTED='#607080'
NB_SELECTION='#30475a'
NB_RED='#ef5350'
NB_GREEN='#66bb6a'
NB_YELLOW='#ffca28'
NB_BLUE='#42a5f5'
NB_MAGENTA='#ab47bc'
NB_CYAN='#26c6da'
NB_BRIGHT_RED='#ff6b6b'
NB_BRIGHT_YELLOW='#ffe082'
EOF

cat >"$TEST_DIR/bin/hermes" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2 $3" = "config get display.skin" ]; then
    printf '%s\n' "${FAKE_ACTIVE_SKIN:-default}"
elif [ "$1 $2 $3 $4" = "config set display.skin nbshell" ]; then
    printf '%s\n' "$*" >>"$FAKE_HERMES_LOG"
else
    exit 2
fi
EOF
chmod +x "$TEST_DIR/bin/hermes"
export NBSHELL_HERMES_BIN="$TEST_DIR/bin/hermes"
export FAKE_HERMES_LOG="$TEST_DIR/hermes.log"

bash "$ROOT/shell/scripts/hermes-theme.sh"
SKIN="$HERMES_HOME/skins/nbshell.yaml"
test -f "$SKIN"
grep -Fq 'background: "#101820"' "$SKIN"
grep -Fq 'ui_accent: "#42a5f5"' "$SKIN"
grep -Fq 'ui_ok: "#66bb6a"' "$SKIN"
grep -Fq 'completion_menu_current_bg: "#30475a"' "$SKIN"
grep -Fxq 'config set display.skin nbshell' "$FAKE_HERMES_LOG"

# Once active, updating the generated skin must not rewrite Hermes config.
: >"$FAKE_HERMES_LOG"
export FAKE_ACTIVE_SKIN=nbshell
bash "$ROOT/shell/scripts/hermes-theme.sh"
test ! -s "$FAKE_HERMES_LOG"

# Reject malformed custom palette values before replacing the valid skin.
cp "$SKIN" "$TEST_DIR/skin.before"
printf "NB_ACCENT='not-a-color'\n" >>"$XDG_CONFIG_HOME/nbshell/palette.sh"
if bash "$ROOT/shell/scripts/hermes-theme.sh" >/dev/null 2>&1; then
    echo "invalid palette unexpectedly accepted" >&2
    exit 1
fi
cmp -s "$TEST_DIR/skin.before" "$SKIN"

echo "Hermes theme validation: OK"
