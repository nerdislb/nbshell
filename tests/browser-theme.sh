#!/usr/bin/env bash
set -euo pipefail

assert_not_grep() {
    local status
    if grep "$@"; then
        printf 'Unexpected grep match: %s\n' "$*" >&2
        return 1
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            printf 'grep failed with status %s: %s\n' "$status" "$*" >&2
            return "$status"
        fi
    fi
}

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

# Omazen remains a separate optional program. nbshell provides its palette,
# invokes external-provider mode, and removes only its own legacy CSS import
# after live setup succeeds.
FAKE_BIN="$TEST_DIR/bin"
FAKE_OMAZEN_PROGRAM="$TEST_DIR/zen-program"
OMAZEN_LOG="$TEST_DIR/omazen.log"
mkdir -p "$FAKE_BIN" "$FAKE_OMAZEN_PROGRAM/defaults/pref" "$PROFILE/chrome/JS"
touch "$FAKE_OMAZEN_PROGRAM/defaults/pref/omazen-prefs.js" "$PROFILE/chrome/JS/omazen-bridge.uc.js"
cat >"$FAKE_BIN/omazen" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$OMAZEN_SKIP_THEME_HOOK" "$OMAZEN_ACTIVE_COLORS" "$*" >>"$OMAZEN_TEST_LOG"
if [[ $* == doctor && ${OMAZEN_TEST_FAIL_DOCTOR:-0} == 1 ]]; then exit 1; fi
EOF
chmod +x "$FAKE_BIN/omazen"
export PATH="$FAKE_BIN:$PATH"
export OMAZEN_TEST_LOG="$OMAZEN_LOG"
export NBSHELL_OMAZEN_PROGRAM_DIR="$FAKE_OMAZEN_PROGRAM"
bash "$ROOT/shell/scripts/browser-theme.sh" apply
grep -Fq '1|' "$OMAZEN_LOG"
grep -Fq '|sync' "$OMAZEN_LOG"
grep -Fq 'mode = "dark"' "$XDG_CONFIG_HOME/nbshell/omazen-colors.toml"
grep -Fq 'accent = "#42a5f5"' "$XDG_CONFIG_HOME/nbshell/omazen-colors.toml"
if OMAZEN_TEST_FAIL_DOCTOR=1 bash "$ROOT/shell/scripts/browser-theme.sh" setup-zen-live >/dev/null 2>&1; then
    echo "setup-zen-live accepted a failed post-install doctor" >&2
    exit 1
fi
grep -Fq 'managed by nbshell' "$PROFILE/chrome/userChrome.css"
bash "$ROOT/shell/scripts/browser-theme.sh" setup-zen-live >/dev/null
grep -Fq '|setup' "$OMAZEN_LOG"
grep -Fq '|doctor' "$OMAZEN_LOG"
assert_not_grep -Fq 'managed by nbshell' "$PROFILE/chrome/userChrome.css"

# Brave follows the theme's explicit mode through the Arch launcher flags.
POLICY="$TEST_DIR/brave-policy.json"
touch "$POLICY"
printf '%s\n' '--ozone-platform=wayland' > "$XDG_CONFIG_HOME/brave-flags.conf"
NBSHELL_BRAVE_POLICY="$POLICY" bash "$ROOT/shell/scripts/browser-theme.sh" apply
grep -Fxq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fxq -- '--ozone-platform=wayland' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fq '"BrowserThemeColor":"#101820"' "$POLICY"
assert_not_grep -Fq 'BrowserColorScheme' "$POLICY"
sed -i "s/NB_MODE='dark'/NB_MODE='light'/" "$XDG_CONFIG_HOME/nbshell/palette.sh"
NBSHELL_BRAVE_POLICY="$POLICY" bash "$ROOT/shell/scripts/browser-theme.sh" apply
assert_not_grep -Fq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fxq -- '--ozone-platform=wayland' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fq '"BrowserThemeColor":"#263746"' "$POLICY"

echo "Browser theme validation: OK"
