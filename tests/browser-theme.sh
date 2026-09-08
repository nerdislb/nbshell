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

# Fixture paths are injected into a private copy; production exposes no overrides.
CALLER="$TEST_DIR/browser-theme.sh"
POLICY="$TEST_DIR/brave-policy.json"
export TEST_BRAVE_HELPER="$TEST_DIR/brave-helper"
cp "$ROOT/shell/scripts/browser-theme.sh" "$CALLER"
python3 - "$CALLER" <<'PYISOLATE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text();base=p.parent
s=s.replace('BRAVE_POLICY=/etc/brave/policies/managed/nbshell-color.json', 'BRAVE_POLICY="'+str(base/'brave-policy.json')+'"')
s=s.replace('BRAVE_HELPER=/usr/lib/nbshell/brave-theme-policy', 'BRAVE_HELPER="'+str(base/'brave-helper')+'"')
s=s.replace('BRAVE_ACTION=/usr/share/polkit-1/actions/org.nbshell.brave-theme.policy', 'BRAVE_ACTION="'+str(base/'brave-action')+'"')
s=s.replace('/usr/bin/pkexec', str(base/'bin/pkexec'))
a=s.index('brave_health() {');b=s.index('\nbrave_configured()',a)
s=s[:a]+"brave_health() { printf '%s\\n' \"${TEST_BRAVE_HEALTH:-secure}\"; }\n"+s[b:]
p.write_text(s)
PYISOLATE

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

bash "$CALLER" setup-zen >/dev/null

grep -Fq 'managed by nbshell' "$PROFILE/chrome/userChrome.css"
grep -Fq 'toolkit.legacyUserProfileCustomizations.stylesheets' "$PROFILE/user.js"
grep -Fq -- '--zen-primary-color: #42a5f5' "$PROFILE/chrome/nbshell-theme.css"
grep -Fq -- '--toolbar-bgcolor: #101820' "$PROFILE/chrome/nbshell-theme.css"

# Repeated setup must not duplicate the managed import or preference.
bash "$CALLER" setup-zen >/dev/null
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
bash "$CALLER" apply
grep -Fq '1|' "$OMAZEN_LOG"
grep -Fq '|sync' "$OMAZEN_LOG"
grep -Fq 'mode = "dark"' "$XDG_CONFIG_HOME/nbshell/omazen-colors.toml"
grep -Fq 'accent = "#42a5f5"' "$XDG_CONFIG_HOME/nbshell/omazen-colors.toml"
if OMAZEN_TEST_FAIL_DOCTOR=1 bash "$CALLER" setup-zen-live >/dev/null 2>&1; then
    echo "setup-zen-live accepted a failed post-install doctor" >&2
    exit 1
fi
grep -Fq 'managed by nbshell' "$PROFILE/chrome/userChrome.css"
bash "$CALLER" setup-zen-live >/dev/null
grep -Fq '|setup' "$OMAZEN_LOG"
grep -Fq '|doctor' "$OMAZEN_LOG"
assert_not_grep -Fq 'managed by nbshell' "$PROFILE/chrome/userChrome.css"

# Exercise the real composed configured predicate and all status branches.
bash "$CALLER" status > "$TEST_DIR/status"
grep -Eq '^Brave +setup required' "$TEST_DIR/status"
touch "$POLICY" "$TEST_DIR/brave-action" "$TEST_BRAVE_HELPER"
chmod +x "$TEST_BRAVE_HELPER"
bash "$CALLER" status > "$TEST_DIR/status"
grep -Eq '^Brave +configured' "$TEST_DIR/status"
TEST_BRAVE_HEALTH=insecure bash "$CALLER" status > "$TEST_DIR/status"
grep -Eq '^Brave +INSECURE.*setup-brave' "$TEST_DIR/status"
chmod -x "$TEST_BRAVE_HELPER"
bash "$CALLER" status > "$TEST_DIR/status"
grep -Eq '^Brave +setup required' "$TEST_DIR/status"
chmod +x "$TEST_BRAVE_HELPER"
mv "$POLICY" "$POLICY.real"
ln -s "$POLICY.real" "$POLICY"
bash "$CALLER" status > "$TEST_DIR/status"
grep -Eq '^Brave +setup required' "$TEST_DIR/status"
rm "$POLICY"
mv "$POLICY.real" "$POLICY"
rm "$TEST_DIR/brave-action"
bash "$CALLER" status > "$TEST_DIR/status"
grep -Eq '^Brave +setup required' "$TEST_DIR/status"
touch "$TEST_DIR/brave-action"
cat > "$FAKE_BIN/pkexec" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${TEST_PKEXEC_DENY:-0} == 0 ]] || exit 126
[[ $# == 3 && $1 == --disable-internal-agent && $2 == "$TEST_BRAVE_HELPER" ]]
[[ $3 =~ ^#[[:xdigit:]]{6}$ ]]
printf '{"BrowserThemeColor":"%s"}\n' "$3" > "$TEST_BRAVE_POLICY"
EOF
chmod +x "$FAKE_BIN/pkexec"
export TEST_BRAVE_POLICY="$POLICY"
printf '%s\n' '--ozone-platform=wayland' > "$XDG_CONFIG_HOME/brave-flags.conf"
bash "$CALLER" apply
grep -Fxq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fxq -- '--ozone-platform=wayland' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fq '"BrowserThemeColor":"#101820"' "$POLICY"
assert_not_grep -Fq 'BrowserColorScheme' "$POLICY"
sed -i "s/NB_MODE='dark'/NB_MODE='light'/" "$XDG_CONFIG_HOME/nbshell/palette.sh"
bash "$CALLER" apply
assert_not_grep -Fq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fxq -- '--ozone-platform=wayland' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fq '"BrowserThemeColor":"#263746"' "$POLICY"
# An inactive-session policy denial still updates the user's launcher mode.
sed -i "s/NB_MODE='light'/NB_MODE='dark'/" "$XDG_CONFIG_HOME/nbshell/palette.sh"
TEST_PKEXEC_DENY=1 bash "$CALLER" apply 2>"$TEST_DIR/denied.log"
grep -Fxq -- '--force-dark-mode' "$XDG_CONFIG_HOME/brave-flags.conf"
grep -Fq 'active local session' "$TEST_DIR/denied.log"
sed -i "s/NB_MODE='dark'/NB_MODE='light'/" "$XDG_CONFIG_HOME/nbshell/palette.sh"
sed -i "s/NB_BG_LIGHT='#263746'/NB_BG_LIGHT='invalid'/" "$XDG_CONFIG_HOME/nbshell/palette.sh"
if bash "$CALLER" apply >/dev/null 2>&1; then
    echo "Invalid color accepted" >&2; exit 1
fi
grep -Fq '"BrowserThemeColor":"#263746"' "$POLICY"
echo "Browser theme validation: OK"
