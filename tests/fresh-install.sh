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
trap 'status=$?; printf "::error title=Fresh install failure::line %s: %s (exit %s)\\n" "${BASH_LINENO[0]:-unknown}" "$BASH_COMMAND" "$status" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-install-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TEST_HOME="$WORK/home"
FAKE_BIN="$WORK/bin"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat >"$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
state="${FAKE_SYSTEMD_STATE:?}"
unit="${!#:-}"
active_file="$state/active-$unit"
enabled_file="$state/enabled-$unit"
enabled_runtime_file="$state/enabled-runtime-$unit"
masked_file="$state/masked-$unit"
[ "$unit" = "nbshell.service" ] && active_file="$state/active"
case " $* " in
    *" is-active "*) test -f "$active_file" ;;
    *" is-enabled "*)
        if [ -f "$masked_file" ]; then
            echo masked
            exit 1
        elif [ -f "$enabled_runtime_file" ]; then
            echo enabled-runtime
        elif [ -f "$enabled_file" ]; then
            echo enabled
        else
            echo disabled
            exit 1
        fi
        ;;
    *" cat "*) exit 1 ;;
    *" disable "*)
        rm -f "$enabled_file" "$enabled_runtime_file"
        case " $* " in *" --now "*) rm -f "$active_file" ;; esac
        ;;
    *" enable "*)
        [ ! -f "$masked_file" ] || exit 1
        case " $* " in
            *" --runtime "*) touch "$enabled_runtime_file" ;;
            *) touch "$enabled_file" ;;
        esac
        case " $* " in *" --now "*) touch "$active_file" ;; esac
        ;;
    *" unmask "*) rm -f "$masked_file" ;;
    *" mask "*)
        rm -f "$enabled_file" "$active_file"
        touch "$masked_file"
        ;;
    *" stop "*)
        # systemctl accepts multiple units in one stop call. Model each one so
        # stale watchdog timer/service races can be exercised faithfully.
        for target in "$@"; do
            case "$target" in
                --user|stop) continue ;;
            esac
            target_active_file="$state/active-$target"
            [ "$target" = "nbshell.service" ] && target_active_file="$state/active"
            rm -f "$target_active_file"
        done
        ;;
    *" start "*)
        if [ "$unit" = "nbshell.service" ] \
                && [ -f "$state/fail-next-nbshell-start" ]; then
            rm -f "$state/fail-next-nbshell-start"
            exit 1
        elif [ -f "$state/fail-next-start" ]; then
            rm -f "$state/fail-next-start"
            exit 1
        fi
        touch "$active_file"
        ;;
    *" restart "*) touch "$active_file" ;;
    *) exit 0 ;;
esac
EOF

cat >"$FAKE_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${FAKE_SYSTEMD_STATE:?}/last-systemd-run"
[ ! -f "${FAKE_SYSTEMD_STATE:?}/fail-systemd-run" ] || {
    rm -f "$FAKE_SYSTEMD_STATE/fail-systemd-run"
    exit 1
}
exit 0
EOF

cat >"$FAKE_BIN/qs" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "list" ] && exit 0
exit 0
EOF

cat >"$FAKE_BIN/aether" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/systemd-run" "$FAKE_BIN/qs" "$FAKE_BIN/aether"

export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$TEST_HOME/.config"
export XDG_DATA_HOME="$TEST_HOME/.local/share"
export XDG_CACHE_HOME="$TEST_HOME/.cache"
export XDG_BIN_HOME="$TEST_HOME/.local/bin"
export FAKE_SYSTEMD_STATE="$WORK/systemd-state"
# Tests run inside the developer's real nbshell.service cgroup; force the normal
# restart path except for the dedicated deferred-restart case below.
export NBSHELL_INSTALL_DEFER_RESTART=0
export PATH="$FAKE_BIN:/usr/bin:/bin"
mkdir -p "$FAKE_SYSTEMD_STATE"
mkdir -p "$XDG_CONFIG_HOME/omarchy-gmail" "$XDG_CACHE_HOME/omarchy-gmail"
printf 'legacy-config\n' >"$XDG_CONFIG_HOME/omarchy-gmail/credentials.json"
printf 'legacy-cache\n' >"$XDG_CACHE_HOME/omarchy-gmail/inbox.json"

assert_no_reservations() {
    test -z "$(find "$XDG_CONFIG_HOME/quickshell" -maxdepth 1 -type d \
        \( -name '.nbshell-stage.*' -o -name '.nbshell-rollback.*' \) \
        -print -quit 2>/dev/null)"
    test -z "$(find "$XDG_CONFIG_HOME" -maxdepth 1 -type d \
        -name '.nbshell-install-rollback.*' -print -quit 2>/dev/null)"
}

# A failed first install must leave no new payload behind. The install lock's
# state directory may remain, but runtime, units, commands, integrations, and
# migrated user state all roll back to their original absence or location.
if NBSHELL_INSTALL_TEST_FAULT=post-payload "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "First install unexpectedly succeeded at the post-payload fault" >&2
    exit 1
fi
test ! -e "$XDG_CONFIG_HOME/quickshell/nbshell"
test ! -e "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
test ! -e "$XDG_CONFIG_HOME/nbshell/themes"
test ! -e "$XDG_CONFIG_HOME/nbshell/config.json"
test ! -e "$XDG_CONFIG_HOME/nbshell/plugins/beispiel"
test ! -e "$XDG_CONFIG_HOME/umbriel/nbshell.toml"
test ! -e "$XDG_CONFIG_HOME/aether/custom/nbshell"
test ! -e "$XDG_DATA_HOME/nbshell"
test ! -e "$XDG_DATA_HOME/applications/dev.nerdi.nbshell.desktop"
test ! -e "$XDG_BIN_HOME/nbshell"
test ! -e "$XDG_BIN_HOME/nbshell-install-recover"
test ! -e "$HOME/.agents/skills/nbshell"
test -f "$XDG_CONFIG_HOME/omarchy-gmail/credentials.json"
test -f "$XDG_CACHE_HOME/omarchy-gmail/inbox.json"
test ! -e "$XDG_CONFIG_HOME/omamail"
test ! -e "$XDG_CACHE_HOME/omamail"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-upstream-audit.timer"
test ! -e "$FAKE_SYSTEMD_STATE/active-nbshell-upstream-audit.timer"
assert_no_reservations

"$ROOT/install.sh" >/dev/null

grep -Fq "flock $HOME/.local/state/nbshell/install.lock" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
test -f "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml"
assert_no_reservations
test -f "$XDG_CONFIG_HOME/quickshell/nbshell/integrations/omawhatsapp/manifest.json"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/VERSION")" = "$(cat "$ROOT/VERSION")"
test -f "$XDG_CONFIG_HOME/nbshell/config.json"
test -f "$XDG_CONFIG_HOME/omamail/credentials.json"
test -f "$XDG_CACHE_HOME/omamail/inbox.json"
test ! -e "$XDG_CONFIG_HOME/omarchy-gmail"
test ! -e "$XDG_CACHE_HOME/omarchy-gmail"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
grep -Fq 'MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000' "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
grep -Fq 'Slice=session.slice' "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
grep -Fq 'Slice=session.slice' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
grep -Fq 'Restart=on-failure' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
grep -Fq 'ExecStopPost=/usr/bin/rm -f %t/nbshell-lock-ready' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
assert_not_grep -Fq 'PartOf=nbshell.service' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell-sleep-lock.service"
grep -Fq 'sleep_lock_inhibitor.py' "$XDG_CONFIG_HOME/systemd/user/nbshell-sleep-lock.service"
grep -Fq 'WantedBy=graphical-session.target' "$XDG_CONFIG_HOME/systemd/user/nbshell-sleep-lock.service"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell-umbriel-resume-guard.service"
grep -Fq 'Slice=session.slice' "$XDG_CONFIG_HOME/systemd/user/nbshell-umbriel-resume-guard.service"
test ! -e "$XDG_CONFIG_HOME/systemd/user/nbshell-agent-host.service"
test ! -e "$XDG_CONFIG_HOME/niri"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-motion.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-colors.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-nested.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-outputs.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-cursor.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-overview.toml"
test -f "$XDG_CONFIG_HOME/umbriel/config.toml"
grep -Fq 'bubblewrap' "$ROOT/setup.sh"
test -x "$XDG_BIN_HOME/nbshell"
test -x "$XDG_BIN_HOME/nbshell-install-recover"
test -x "$XDG_DATA_HOME/nbshell/setup-greeter.sh"
test -x "$XDG_DATA_HOME/nbshell/setup-locker.sh"
test -f "$XDG_DATA_HOME/nbshell/locker/nbshell-lock.pam"
cmp -s "$XDG_DATA_HOME/nbshell/locker/nbshell-lock.pam" "$ROOT/shell/lock/nbshell-lock.pam"
LOCKER_ROOT="$WORK/installed-locker-root"
NBSHELL_LOCK_TEST_ROOT="$LOCKER_ROOT" "$XDG_DATA_HOME/nbshell/setup-locker.sh" >/dev/null
cmp -s "$LOCKER_ROOT/etc/pam.d/nbshell-lock" "$ROOT/shell/lock/nbshell-lock.pam"
test -f "$XDG_DATA_HOME/nbshell/greeter/nbshell-greetd.pam"
cmp -s "$XDG_DATA_HOME/nbshell/greeter/nbshell-greetd.pam" "$ROOT/greeter/nbshell-greetd.pam"
test -f "$XDG_DATA_HOME/applications/dev.nerdi.nbshell.desktop"
test -f "$XDG_DATA_HOME/applications/dev.nerdi.nbshell.Calculator.desktop"
grep -Fq 'Exec=nbshell calculator open' "$XDG_DATA_HOME/applications/dev.nerdi.nbshell.Calculator.desktop"
test "$(find "$XDG_CONFIG_HOME/nbshell/themes" -name colors.toml | wc -l)" -eq "$(find "$ROOT/themes" -name colors.toml | wc -l)"
test "$(find "$XDG_CONFIG_HOME/nbshell/plugins" -name manifest.json | wc -l)" -eq "$(find "$ROOT/plugins" -name manifest.json | wc -l)"

jq -e '
    .theme == "tokyo-night" and
    .mode == "bar" and
    .font == "JetBrainsMono Nerd Font" and
    .fontSize == 14 and
    .radius == 2 and
    .motionProfile == "standard" and
    .widgetStyle == "plain" and
    .enabledPlugins == []
' "$XDG_CONFIG_HOME/nbshell/config.json" >/dev/null

test "$("$XDG_BIN_HOME/nbshell" --version)" = "nbshell $(cat "$ROOT/VERSION")"

for skill_link in \
    "$TEST_HOME/.agents/skills/nbshell" \
    "$TEST_HOME/.claude/skills/nbshell" \
    "$TEST_HOME/.codex/skills/nbshell" \
    "$TEST_HOME/.pi/agent/skills/nbshell"; do
    test -L "$skill_link"
    test "$(readlink -f "$skill_link")" = "$XDG_CONFIG_HOME/quickshell/nbshell/skills/nbshell"
done
"$XDG_BIN_HOME/nbshell" agent skills --json | jq -e '
    .skills | length == 4 and all(.ready == true)
' >/dev/null


# User configuration and custom plugins must survive an update.
jq '.testMarker = "keep"' "$XDG_CONFIG_HOME/nbshell/config.json" >"$WORK/config.json"
mv "$WORK/config.json" "$XDG_CONFIG_HOME/nbshell/config.json"
mkdir -p "$XDG_CONFIG_HOME/nbshell/plugins/custom"
printf '%s\n' keep >"$XDG_CONFIG_HOME/nbshell/plugins/custom/marker"

"$ROOT/install.sh" >/dev/null
jq -e '.testMarker == "keep"' "$XDG_CONFIG_HOME/nbshell/config.json" >/dev/null
test "$(cat "$XDG_CONFIG_HOME/nbshell/plugins/custom/marker")" = keep
test -f "$XDG_CONFIG_HOME/umbriel/nbshell.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-motion.toml"

# The package-free setup path must remain a valid equivalent entry point.
"$ROOT/setup.sh" --no-packages --yes >/dev/null
jq -e '.testMarker == "keep"' "$XDG_CONFIG_HOME/nbshell/config.json" >/dev/null

# Validation/pre-swap failure removes both private reservations and leaves the
# live runtime untouched.
printf '%s\n' pre-swap >"$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel"
if NBSHELL_INSTALL_TEST_FAULT=pre-swap "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the pre-swap fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = pre-swap
assert_no_reservations

# A kill after staging but before watchdog arming leaves no payload mutation.
# The next installer owns the lock and clears that durable stale transaction
# before creating its own reservations.
printf '%s\n' pre-watchdog-kill \
    >"$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel"
if python3 - "$ROOT/install.sh" <<'PY' >/dev/null 2>&1
import os
import subprocess
import sys

environment = os.environ.copy()
environment["NBSHELL_INSTALL_TEST_FAULT"] = "pre-watchdog-kill"
result = subprocess.run(
    [sys.argv[1]], env=environment, stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL, check=False,
)
raise SystemExit(0 if result.returncode == 0 else 1)
PY
then
    echo "Install unexpectedly survived the pre-watchdog kill" >&2
    exit 1
fi
find "$XDG_CONFIG_HOME/quickshell" -maxdepth 1 \
    -type d -name '.nbshell-stage.*' -print -quit | grep -q .
find "$XDG_CONFIG_HOME" -maxdepth 1 \
    -type d -name '.nbshell-install-rollback.*' -print -quit | grep -q .
if NBSHELL_INSTALL_TEST_FAULT=pre-swap "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded after stale transaction recovery" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = pre-watchdog-kill
assert_no_reservations
printf '%s\n' pre-swap \
    >"$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel"

# Refuse to stop or swap an active shell unless independent recovery is armed.
printf '%s\n' watchdog-arm-before >"$XDG_CONFIG_HOME/quickshell/nbshell/watchdog-arm-sentinel"
touch "$FAKE_SYSTEMD_STATE/active" "$FAKE_SYSTEMD_STATE/fail-systemd-run"
if "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly continued without an independent watchdog" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/watchdog-arm-sentinel")" = watchdog-arm-before
test -f "$FAKE_SYSTEMD_STATE/active"
test ! -e "$FAKE_SYSTEMD_STATE/fail-systemd-run"
assert_no_reservations

# A fault on the instruction immediately after the first mv must recognize the
# occupied rollback by its runtime contents and restore it flat.
if NBSHELL_INSTALL_TEST_FAULT=post-first-rename "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-first-rename fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = pre-swap
test -f "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml"
test ! -d "$XDG_CONFIG_HOME/quickshell/nbshell/nbshell"
assert_no_reservations

# Config creation, managed plugins, and Umbriel integration participate in the
# same rollback contract as the runtime swap.
mv "$XDG_CONFIG_HOME/nbshell/config.json" "$WORK/config.saved"
if NBSHELL_INSTALL_TEST_FAULT=post-config "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-config fault" >&2
    exit 1
fi
test ! -e "$XDG_CONFIG_HOME/nbshell/config.json"
mv "$WORK/config.saved" "$XDG_CONFIG_HOME/nbshell/config.json"
assert_no_reservations

printf '%s\n' plugin-before >"$XDG_CONFIG_HOME/nbshell/plugins/beispiel/transaction-sentinel"
if NBSHELL_INSTALL_TEST_FAULT=post-plugin "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-plugin fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/nbshell/plugins/beispiel/transaction-sentinel")" = plugin-before
assert_no_reservations

config_before_umbriel_fault="$(sha256sum "$XDG_CONFIG_HOME/nbshell/config.json" | cut -d' ' -f1)"
printf '%s\n' umbriel-before >"$XDG_CONFIG_HOME/umbriel/nbshell.toml"
if NBSHELL_INSTALL_TEST_FAULT=post-umbriel "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-umbriel fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/umbriel/nbshell.toml")" = umbriel-before
test "$(cat "$XDG_CONFIG_HOME/nbshell/plugins/beispiel/transaction-sentinel")" = plugin-before
test "$(sha256sum "$XDG_CONFIG_HOME/nbshell/config.json" | cut -d' ' -f1)" = "$config_before_umbriel_fault"
assert_no_reservations

# A late failure must restore every installer-owned payload, retired artifact,
# migration input, and user-unit state—not only the shell/config/plugin paths.
cp -a "$XDG_BIN_HOME/nbshell" "$WORK/nbshell.saved"
cp -a "$XDG_BIN_HOME/nbshell-install-recover" "$WORK/nbshell-install-recover.saved"
printf '%s\n' command-before >"$XDG_BIN_HOME/nbshell"
printf '%s\n' recovery-command-before >"$XDG_BIN_HOME/nbshell-install-recover"
chmod +x "$XDG_BIN_HOME/nbshell" "$XDG_BIN_HOME/nbshell-install-recover"
printf '%s\n' manager-before >"$XDG_DATA_HOME/nbshell/hermes-jobs/manager.py"
printf '%s\n' greeter-before >"$XDG_DATA_HOME/nbshell/greeter/nbshell-greetd.pam"
printf '%s\n' app-before >"$XDG_DATA_HOME/applications/dev.nerdi.nbshell.desktop"
printf '%s\n' theme-before >"$XDG_CONFIG_HOME/nbshell/themes/tokyo-night/colors.toml"
printf '%s\n' wallpaper-before >"$XDG_DATA_HOME/nbshell/wallpapers/osaka-jade/6.webp"
printf '%s\n' aether-before >"$XDG_CONFIG_HOME/aether/custom/nbshell/config.json"

custom_skill="$WORK/custom-skill"
mkdir -p "$custom_skill" "$HOME/.gemini/skills"
ln -sfn "$custom_skill" "$HOME/.agents/skills/nbshell"
ln -sfn "$XDG_CONFIG_HOME/quickshell/nbshell/skills/nbshell" "$HOME/.gemini/skills/nbshell"

unit_dir="$XDG_CONFIG_HOME/systemd/user"
printf '%s\n' timer-before >"$unit_dir/nbshell-upstream-audit.timer"
printf '%s\n' retired-agent-before >"$unit_dir/nbshell-agent-host.service"
printf '%s\n' retired-whatsapp-before >"$unit_dir/nbshell-whatsapp.service"
touch "$FAKE_SYSTEMD_STATE/enabled-nbshell-agent-host.service" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-agent-host.service" \
    "$FAKE_SYSTEMD_STATE/enabled-nbshell-whatsapp.service" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-whatsapp.service" \
    "$FAKE_SYSTEMD_STATE/masked-nbshell-umbriel-resume-guard.service" \
    "$FAKE_SYSTEMD_STATE/enabled-runtime-nbshell-sleep-lock.service"
rm -f "$FAKE_SYSTEMD_STATE/enabled-nbshell-upstream-audit.timer" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-upstream-audit.timer" \
    "$FAKE_SYSTEMD_STATE/enabled-nbshell-umbriel-resume-guard.service" \
    "$FAKE_SYSTEMD_STATE/enabled-nbshell-sleep-lock.service"

mkdir -p "$XDG_CONFIG_HOME/niri" "$unit_dir/niri.service.d" \
    "$HOME/.local/lib/nbshell" "$XDG_CONFIG_HOME/nbshell/state"
printf '%s\n' 'include "nbshell-takeover.kdl"' 'user-line' >"$XDG_CONFIG_HOME/niri/config.kdl"
printf '%s\n' niri-backup-before >"$XDG_CONFIG_HOME/niri/config.kdl.before-nbshell-umbriel-only"
for name in takeover outputs cursor colors; do
    printf 'niri-%s-before\n' "$name" >"$XDG_CONFIG_HOME/niri/nbshell-$name.kdl"
done
printf '%s\n' niri-unit-before >"$unit_dir/niri.service.d/nbshell.conf"
printf '%s\n' niri-grid-unit-before >"$unit_dir/niri.service.d/nbshell-grid-atomic.conf"
printf '%s\n' niri-atomic-before >"$HOME/.local/lib/nbshell/niri-atomic"
for name in grid-layout.json grid-layout.lock grid-layout.pid grid-layout-backend; do
    printf 'grid-%s-before\n' "$name" >"$XDG_CONFIG_HOME/nbshell/state/$name"
done
mkdir -p "$XDG_DATA_HOME/nbshell/bin" "$XDG_DATA_HOME/nbshell/native"
printf '%s\n' native-bin-before >"$XDG_DATA_HOME/nbshell/bin/umbriel-workspaces"
printf '%s\n' native-source-before >"$XDG_DATA_HOME/nbshell/native/umbriel-workspaces.c"

mv "$XDG_CONFIG_HOME/omamail" "$WORK/omamail-config.saved"
mv "$XDG_CACHE_HOME/omamail" "$WORK/omamail-cache.saved"
mkdir -p "$XDG_CONFIG_HOME/omarchy-gmail" "$XDG_CACHE_HOME/omarchy-gmail"
printf '%s\n' old-mail-config-before >"$XDG_CONFIG_HOME/omarchy-gmail/marker"
printf '%s\n' old-mail-cache-before >"$XDG_CACHE_HOME/omarchy-gmail/marker"

touch "$FAKE_SYSTEMD_STATE/active"
if NBSHELL_INSTALL_TEST_FAULT=post-payload "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-payload fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = pre-swap
test "$(cat "$XDG_CONFIG_HOME/umbriel/nbshell.toml")" = umbriel-before
test "$(cat "$XDG_CONFIG_HOME/nbshell/plugins/beispiel/transaction-sentinel")" = plugin-before
test "$(cat "$XDG_BIN_HOME/nbshell")" = command-before
test "$(cat "$XDG_BIN_HOME/nbshell-install-recover")" = recovery-command-before
test "$(cat "$XDG_DATA_HOME/nbshell/hermes-jobs/manager.py")" = manager-before
test "$(cat "$XDG_DATA_HOME/nbshell/greeter/nbshell-greetd.pam")" = greeter-before
test "$(cat "$XDG_DATA_HOME/applications/dev.nerdi.nbshell.desktop")" = app-before
test "$(cat "$XDG_CONFIG_HOME/nbshell/themes/tokyo-night/colors.toml")" = theme-before
test "$(cat "$XDG_DATA_HOME/nbshell/wallpapers/osaka-jade/6.webp")" = wallpaper-before
test "$(cat "$XDG_CONFIG_HOME/aether/custom/nbshell/config.json")" = aether-before
test "$(readlink -f "$HOME/.agents/skills/nbshell")" = "$custom_skill"
test -L "$HOME/.gemini/skills/nbshell"
test "$(cat "$unit_dir/nbshell-upstream-audit.timer")" = timer-before
test "$(cat "$unit_dir/nbshell-agent-host.service")" = retired-agent-before
test "$(cat "$unit_dir/nbshell-whatsapp.service")" = retired-whatsapp-before
test -f "$FAKE_SYSTEMD_STATE/enabled-nbshell-agent-host.service"
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-agent-host.service"
test -f "$FAKE_SYSTEMD_STATE/enabled-nbshell-whatsapp.service"
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-whatsapp.service"
test -f "$FAKE_SYSTEMD_STATE/masked-nbshell-umbriel-resume-guard.service"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-umbriel-resume-guard.service"
test -f "$FAKE_SYSTEMD_STATE/enabled-runtime-nbshell-sleep-lock.service"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-sleep-lock.service"
test -f "$FAKE_SYSTEMD_STATE/active"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-upstream-audit.timer"
test ! -e "$FAKE_SYSTEMD_STATE/active-nbshell-upstream-audit.timer"
grep -Fxq 'include "nbshell-takeover.kdl"' "$XDG_CONFIG_HOME/niri/config.kdl"
grep -Fxq user-line "$XDG_CONFIG_HOME/niri/config.kdl"
test "$(cat "$XDG_CONFIG_HOME/niri/config.kdl.before-nbshell-umbriel-only")" = niri-backup-before
for name in takeover outputs cursor colors; do
    test "$(cat "$XDG_CONFIG_HOME/niri/nbshell-$name.kdl")" = "niri-$name-before"
done
test "$(cat "$unit_dir/niri.service.d/nbshell.conf")" = niri-unit-before
test "$(cat "$unit_dir/niri.service.d/nbshell-grid-atomic.conf")" = niri-grid-unit-before
test "$(cat "$HOME/.local/lib/nbshell/niri-atomic")" = niri-atomic-before
for name in grid-layout.json grid-layout.lock grid-layout.pid grid-layout-backend; do
    test "$(cat "$XDG_CONFIG_HOME/nbshell/state/$name")" = "grid-$name-before"
done
test "$(cat "$XDG_DATA_HOME/nbshell/bin/umbriel-workspaces")" = native-bin-before
test "$(cat "$XDG_DATA_HOME/nbshell/native/umbriel-workspaces.c")" = native-source-before
test "$(cat "$XDG_CONFIG_HOME/omarchy-gmail/marker")" = old-mail-config-before
test "$(cat "$XDG_CACHE_HOME/omarchy-gmail/marker")" = old-mail-cache-before
test ! -e "$XDG_CONFIG_HOME/omamail"
test ! -e "$XDG_CACHE_HOME/omamail"
assert_no_reservations

cp -a "$WORK/nbshell.saved" "$XDG_BIN_HOME/nbshell"
cp -a "$WORK/nbshell-install-recover.saved" "$XDG_BIN_HOME/nbshell-install-recover"
rm -rf "$XDG_CONFIG_HOME/omarchy-gmail" "$XDG_CACHE_HOME/omarchy-gmail"
mv "$WORK/omamail-config.saved" "$XDG_CONFIG_HOME/omamail"
mv "$WORK/omamail-cache.saved" "$XDG_CACHE_HOME/omamail"

# SIGKILL bypasses the EXIT trap. The durable manifest lets the independent
# watchdog—or a lock-owning retry—resolve the interrupted payload safely.
printf '%s\n' killed-runtime-before >"$XDG_CONFIG_HOME/quickshell/nbshell/kill-sentinel"
printf '%s\n' killed-manager-before >"$XDG_DATA_HOME/nbshell/hermes-jobs/manager.py"
printf '%s\n' killed-unit-before >"$XDG_CONFIG_HOME/systemd/user/nbshell-upstream-audit.timer"
touch "$FAKE_SYSTEMD_STATE/active"
if python3 - "$ROOT/install.sh" <<'PY'
import os
import subprocess
import sys

environment = os.environ.copy()
environment["NBSHELL_INSTALL_TEST_FAULT"] = "post-first-rename-kill"
environment["NBSHELL_INSTALL_DEFER_RESTART"] = "1"
result = subprocess.run(
    [sys.argv[1]],
    env=environment,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=False,
)
raise SystemExit(0 if result.returncode == 0 else 1)
PY
then
    echo "Install unexpectedly survived the SIGKILL fault" >&2
    exit 1
fi
killed_transaction="$(find "$XDG_CONFIG_HOME" -maxdepth 1 -type d \
    -name '.nbshell-install-rollback.*' -print -quit)"
killed_rollback="$(find "$XDG_CONFIG_HOME/quickshell" -maxdepth 1 -type d \
    -name '.nbshell-rollback.*' -print -quit)"
test -n "$killed_transaction"
test -n "$killed_rollback"
IFS= read -r killed_recovery_unit <"$killed_transaction/recovery-unit"
# Model the original timer having fired while its service waits for the install
# lock. The retry must cancel both before queuing restart-mode recovery.
touch "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.timer" \
    "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.service"
# A retry owned by nbshell.service must not stop or replace its own live shell.
# It queues stale recovery behind the lock and exits; the helper runs only after
# that retry has left the service cgroup.
touch "$FAKE_SYSTEMD_STATE/fail-next-nbshell-start"
if NBSHELL_INSTALL_TEST_IN_SERVICE=1 \
        "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Service-hosted retry unexpectedly continued past stale recovery" >&2
    exit 1
fi
test -d "$killed_transaction"
test -d "$killed_rollback"
test "$(cat "$killed_transaction/mode")" = deferred
test -f "$FAKE_SYSTEMD_STATE/active"
test -f "$FAKE_SYSTEMD_STATE/fail-next-nbshell-start"
test ! -e "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.timer"
test ! -e "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.service"
grep -Fq "flock $HOME/.local/state/nbshell/install.lock" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq ' restart ' "$FAKE_SYSTEMD_STATE/last-systemd-run"
rm -f "$FAKE_SYSTEMD_STATE/fail-next-nbshell-start"
IFS= read -r killed_shell <"$killed_transaction/shell-path"
IFS= read -r killed_command <"$killed_transaction/command-path"
IFS= read -r killed_staged <"$killed_transaction/staged-path"
"$killed_transaction/recover" \
    "$killed_shell" "$killed_rollback" restart \
    "$killed_transaction" "$killed_command" "$killed_staged"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/kill-sentinel")" = killed-runtime-before
test "$(cat "$XDG_DATA_HOME/nbshell/hermes-jobs/manager.py")" = killed-manager-before
test "$(cat "$XDG_CONFIG_HOME/systemd/user/nbshell-upstream-audit.timer")" = killed-unit-before
test -f "$FAKE_SYSTEMD_STATE/active"
assert_no_reservations

# An installer launched from the shell's own service must atomically update the
# runtime without stopping its parent cgroup. The untouched failure sentinel
# proves that no restart was attempted.
printf '%s\n' deferred >"$XDG_CONFIG_HOME/quickshell/nbshell/deferred-sentinel"
touch "$FAKE_SYSTEMD_STATE/active" "$FAKE_SYSTEMD_STATE/fail-next-start"
NBSHELL_INSTALL_DEFER_RESTART=1 "$ROOT/install.sh" >/dev/null
test -f "$FAKE_SYSTEMD_STATE/active"
test -f "$FAKE_SYSTEMD_STATE/fail-next-start"
test ! -e "$XDG_CONFIG_HOME/quickshell/nbshell/deferred-sentinel"
rm -f "$FAKE_SYSTEMD_STATE/fail-next-start"
DEFERRED_INSTALL_BACKUP="$(find "$XDG_CONFIG_HOME/quickshell" -maxdepth 1 \
    -type d -name '.nbshell-rollback.*' -print -quit)"
DEFERRED_INSTALL_TRANSACTION="$(find "$XDG_CONFIG_HOME" -maxdepth 1 \
    -type d -name '.nbshell-install-rollback.*' -print -quit)"
test -f "$DEFERRED_INSTALL_BACKUP/shell.qml"
test -f "$DEFERRED_INSTALL_TRANSACTION/committed"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$XDG_CONFIG_HOME/quickshell/nbshell" "$DEFERRED_INSTALL_BACKUP" deferred \
    "$DEFERRED_INSTALL_TRANSACTION" "$XDG_BIN_HOME/nbshell"
assert_no_reservations

# A failed shell restart must restore the previous runtime and bring its unit
# back. The one-shot failure simulates a QML process that did not stay up.
printf '%s\n' previous >"$XDG_CONFIG_HOME/quickshell/nbshell/rollback-sentinel"
touch "$FAKE_SYSTEMD_STATE/active" "$FAKE_SYSTEMD_STATE/fail-next-start"
if "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded after a failed shell start" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/rollback-sentinel")" = previous
test -f "$FAKE_SYSTEMD_STATE/active"

# The independent watchdog must also recover after the installer itself is no
# longer alive (including SIGKILL between the two runtime renames).
RECOVERY_BACKUP="$XDG_CONFIG_HOME/quickshell/.nbshell-rollback.recovery-test"
mkdir -p "$RECOVERY_BACKUP"
printf '%s\n' watchdog >"$RECOVERY_BACKUP/rollback-sentinel"
printf '%s\n' backup-runtime >"$RECOVERY_BACKUP/shell.qml"
printf '%s\n' broken >"$XDG_CONFIG_HOME/quickshell/nbshell/rollback-sentinel"
rm -f "$FAKE_SYSTEMD_STATE/active"
touch "$FAKE_SYSTEMD_STATE/fail-next-start"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$XDG_CONFIG_HOME/quickshell/nbshell" "$RECOVERY_BACKUP"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/rollback-sentinel")" = watchdog
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml")" = backup-runtime
test ! -d "$XDG_CONFIG_HOME/quickshell/nbshell/nbshell"
test -f "$FAKE_SYSTEMD_STATE/active"

# An empty reserved rollback is not a runtime and is removed, not restored.
EMPTY_PARENT="$WORK/empty/quickshell"
EMPTY_RUNTIME="$EMPTY_PARENT/nbshell"
EMPTY_BACKUP="$EMPTY_PARENT/.nbshell-rollback.empty-test"
mkdir -p "$EMPTY_BACKUP"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$EMPTY_RUNTIME" "$EMPTY_BACKUP" deferred
test ! -e "$EMPTY_BACKUP"
test ! -e "$EMPTY_RUNTIME"

# Deferred recovery never restarts the parent service; it only closes the
# two-rename interruption window by restoring a missing runtime path.
DEFERRED_PARENT="$WORK/deferred/quickshell"
DEFERRED_RUNTIME="$DEFERRED_PARENT/nbshell"
DEFERRED_BACKUP="$DEFERRED_PARENT/.nbshell-rollback.deferred-test"
mkdir -p "$DEFERRED_BACKUP"
printf '%s\n' deferred-watchdog >"$DEFERRED_BACKUP/rollback-sentinel"
printf '%s\n' deferred-runtime >"$DEFERRED_BACKUP/shell.qml"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$DEFERRED_RUNTIME" "$DEFERRED_BACKUP" deferred
test "$(cat "$DEFERRED_RUNTIME/rollback-sentinel")" = deferred-watchdog
test -f "$DEFERRED_RUNTIME/shell.qml"
test ! -d "$DEFERRED_RUNTIME/nbshell"

# Recovery continues past an independent path failure and preserves the
# transaction backup for a later retry instead of discarding the evidence.
PARTIAL_PARENT="$XDG_CONFIG_HOME/partial-quickshell"
PARTIAL_RUNTIME="$PARTIAL_PARENT/nbshell"
PARTIAL_BACKUP="$PARTIAL_PARENT/.nbshell-rollback.partial-test"
PARTIAL_TRANSACTION="$XDG_CONFIG_HOME/.nbshell-install-rollback.partial-test"
PARTIAL_BLOCKED="$WORK/partial-blocked"
PARTIAL_GOOD="$WORK/partial-good"
mkdir -p "$PARTIAL_RUNTIME" "$PARTIAL_BACKUP" "$PARTIAL_TRANSACTION" \
    "$PARTIAL_BLOCKED"
: >"$PARTIAL_TRANSACTION/units"
printf '%s\n' previous >"$PARTIAL_TRANSACTION/good"
printf '%s\n' replacement >"$PARTIAL_GOOD"
printf '%s\n' keep >"$PARTIAL_BLOCKED/keep"
chmod 500 "$PARTIAL_BLOCKED"
python3 - "$PARTIAL_TRANSACTION/paths" "$PARTIAL_GOOD" \
    "$PARTIAL_BLOCKED/keep" <<'PY'
import sys

manifest, good, blocked = sys.argv[1:]
with open(manifest, "wb") as output:
    for record in (("present", "good", good), ("missing", "blocked", blocked)):
        output.write("\0".join(record).encode() + b"\0")
PY
if "$XDG_BIN_HOME/nbshell-install-recover" \
        "$PARTIAL_RUNTIME" "$PARTIAL_BACKUP" inactive \
        "$PARTIAL_TRANSACTION" "$XDG_BIN_HOME/nbshell" >/dev/null 2>&1; then
    echo "partial recovery unexpectedly reported success" >&2
    exit 1
fi
test "$(cat "$PARTIAL_GOOD")" = previous
test -d "$PARTIAL_TRANSACTION"
chmod 700 "$PARTIAL_BLOCKED"
rm -rf "$PARTIAL_PARENT" "$PARTIAL_TRANSACTION" "$PARTIAL_BLOCKED" "$PARTIAL_GOOD"

assert_no_reservations

echo "Fresh install and update preservation: OK"
