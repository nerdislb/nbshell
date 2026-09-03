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
case " $* " in
    *" is-active "*) test -f "$state/active" ;;
    *" is-enabled "*|*" cat "*) exit 1 ;;
    *" stop nbshell.service "*) rm -f "$state/active" ;;
    *" start nbshell.service "*)
        if [ -f "$state/fail-next-start" ]; then
            rm -f "$state/fail-next-start"
            exit 1
        fi
        touch "$state/active"
        ;;
    *) exit 0 ;;
esac
EOF

cat >"$FAKE_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$FAKE_BIN/qs" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "list" ] && exit 0
exit 0
EOF

chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/systemd-run" "$FAKE_BIN/qs"

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

"$ROOT/install.sh" >/dev/null

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

# A failure after commands, greeter data, desktop metadata, and skills are
# installed must still restore the previous runtime and backed-up user state.
if NBSHELL_INSTALL_TEST_FAULT=post-payload "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-payload fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = pre-swap
test "$(cat "$XDG_CONFIG_HOME/umbriel/nbshell.toml")" = umbriel-before
test "$(cat "$XDG_CONFIG_HOME/nbshell/plugins/beispiel/transaction-sentinel")" = plugin-before
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
test -f "$DEFERRED_INSTALL_BACKUP/shell.qml"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$XDG_CONFIG_HOME/quickshell/nbshell" "$DEFERRED_INSTALL_BACKUP"
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

assert_no_reservations

echo "Fresh install and update preservation: OK"
