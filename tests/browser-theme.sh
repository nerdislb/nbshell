#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
PROFILE="$XDG_CONFIG_HOME/zen/test.default"
mkdir -p "$PROFILE" "$XDG_CONFIG_HOME/nbshell"
touch "$PROFILE/prefs.js"
cat > "$XDG_CONFIG_HOME/nbshell/palette.sh" <<'EOF'
NB_BG='#101820'
NB_MODE='dark'
NB_BG_LIGHT='#263746'
NB_FG='#f0f4f8'
NB_FG_DIM='#8b9aaa'
NB_ACCENT='#42a5f5'
NB_SELECTION='#30475a'
EOF

bash "$ROOT/shell/scripts/browser-theme.sh" setup-zen >/dev/null

grep -Fq 'managed by nbshell' "$PROFILE/chrome/userChrome.css"
grep -Fq 'toolkit.legacyUserProfileCustomizations.stylesheets' "$PROFILE/user.js"
grep -Fq -- '--zen-primary-color: #42a5f5' "$PROFILE/chrome/nbshell-theme.css"
grep -Fq -- '--toolbar-bgcolor: #101820' "$PROFILE/chrome/nbshell-theme.css"

# Repeated setup must not duplicate the managed import or preference.
bash "$ROOT/shell/scripts/browser-theme.sh" setup-zen >/dev/null
test "$(grep -Fc 'managed by nbshell' "$PROFILE/chrome/userChrome.css")" -eq 1
test "$(grep -Fc 'toolkit.legacyUserProfileCustomizations.stylesheets' "$PROFILE/user.js")" -eq 1

# Brave follows the theme's explicit mode through the Arch launcher flags.
POLICY="$TEST_DIR/brave-policy.json"
touch "$POLICY"
printf '%s\n' '--ozone-platform=wayland' > "$XDG_CONFIG_HOME/brave-flags.conf"
NBSHELL_BRAVE_POLICY="$POLICY" bash "$ROOT/shell/scripts/browser-theme.sh" apply
grep -Fxq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fxq -- '--ozone-platform=wayland' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fq '"BrowserThemeColor":"#42a5f5"' "$POLICY"
! grep -Fq 'BrowserColorScheme' "$POLICY"
sed -i "s/NB_MODE='dark'/NB_MODE='light'/" "$XDG_CONFIG_HOME/nbshell/palette.sh"
NBSHELL_BRAVE_POLICY="$POLICY" bash "$ROOT/shell/scripts/browser-theme.sh" apply
! grep -Fq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fxq -- '--ozone-platform=wayland' "$XDG_CONFIG_HOME/brave-flags.conf"

echo "Browser theme validation: OK"
