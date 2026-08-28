#!/usr/bin/env bash
set -euo pipefail
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
export XDG_BIN_HOME="$TEST_HOME/.local/bin"
export FAKE_SYSTEMD_STATE="$WORK/systemd-state"
# Tests run inside the developer's real nbshell.service cgroup; force the normal
# restart path except for the dedicated deferred-restart case below.
export NBSHELL_INSTALL_DEFER_RESTART=0
export PATH="$FAKE_BIN:/usr/bin:/bin"
mkdir -p "$FAKE_SYSTEMD_STATE"

"$ROOT/install.sh" >/dev/null

test -f "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml"
test -f "$XDG_CONFIG_HOME/quickshell/nbshell/integrations/omawhatsapp/manifest.json"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/VERSION")" = "$(cat "$ROOT/VERSION")"
test -f "$XDG_CONFIG_HOME/nbshell/config.json"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
grep -Fq 'MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000' "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
grep -Fq 'Slice=session.slice' "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
grep -Fq 'Slice=session.slice' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
grep -Fq 'Restart=on-failure' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
! grep -Fq 'PartOf=nbshell.service' "$XDG_CONFIG_HOME/systemd/user/nbshell-lock.service"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell-umbriel-resume-guard.service"
grep -Fq 'Slice=session.slice' "$XDG_CONFIG_HOME/systemd/user/nbshell-umbriel-resume-guard.service"
test ! -e "$XDG_CONFIG_HOME/systemd/user/nbshell-agent-host.service"
test -f "$XDG_CONFIG_HOME/niri/config.kdl"
test -f "$XDG_CONFIG_HOME/niri/nbshell-takeover.kdl"
test -f "$XDG_CONFIG_HOME/niri/nbshell-outputs.kdl"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-motion.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-colors.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-nested.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-outputs.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-cursor.toml"
test -f "$XDG_CONFIG_HOME/umbriel/nbshell-overview.toml"
test -f "$XDG_CONFIG_HOME/umbriel/config.toml"
test -f "$XDG_DATA_HOME/nbshell/native/umbriel-workspaces.c"
grep -Fq 'bubblewrap' "$ROOT/setup.sh"
test -x "$XDG_DATA_HOME/nbshell/bin/umbriel-workspaces"
test -x "$XDG_BIN_HOME/nbshell"
test -x "$XDG_BIN_HOME/nbshell-install-recover"
test -x "$XDG_DATA_HOME/nbshell/setup-greeter.sh"
test -x "$XDG_DATA_HOME/nbshell/setup-locker.sh"
test -f "$XDG_DATA_HOME/nbshell/locker/nbshell-lock.pam"
cmp -s "$XDG_DATA_HOME/nbshell/locker/nbshell-lock.pam" "$ROOT/shell/lock/nbshell-lock.pam"
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

# The recovery frontend must remain activatable through the installed payload,
# not only from a source checkout. Run the integration where its compositor
# dependencies are available; minimal CI still verifies the exact payload.
if command -v niri >/dev/null && command -v regreet >/dev/null; then
    GREETER_ROOT="$WORK/installed-greeter-root"
    mkdir -p "$GREETER_ROOT/etc/greetd" "$GREETER_ROOT/etc/pam.d"
    printf 'original config\n' >"$GREETER_ROOT/etc/greetd/config.toml"
    printf 'original pam\n' >"$GREETER_ROOT/etc/pam.d/greetd"
    NBSHELL_GREETER_TEST_ROOT="$GREETER_ROOT" \
    NBSHELL_GREETER_WALLPAPER="$ROOT/docs/screenshots/01-menu-grid.png" \
        "$XDG_BIN_HOME/nbshell" greeter install regreet >/dev/null
    grep -Fq '/usr/bin/regreet' "$GREETER_ROOT/etc/greetd/nbshell-greeter.kdl"
    ! grep -Fq '[initial_session]' "$GREETER_ROOT/etc/greetd/config.toml"
    cmp -s "$GREETER_ROOT/etc/pam.d/nbshell-greetd" "$ROOT/greeter/nbshell-greetd.pam"
    cmp -s "$GREETER_ROOT/etc/pam.d/greetd" <(printf 'original pam\n')
fi

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
printf '%s\n' broken >"$XDG_CONFIG_HOME/quickshell/nbshell/rollback-sentinel"
rm -f "$FAKE_SYSTEMD_STATE/active"
touch "$FAKE_SYSTEMD_STATE/fail-next-start"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$XDG_CONFIG_HOME/quickshell/nbshell" "$RECOVERY_BACKUP"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/rollback-sentinel")" = watchdog
test -f "$FAKE_SYSTEMD_STATE/active"

# Deferred recovery never restarts the parent service; it only closes the
# two-rename interruption window by restoring a missing runtime path.
DEFERRED_PARENT="$WORK/deferred/quickshell"
DEFERRED_RUNTIME="$DEFERRED_PARENT/nbshell"
DEFERRED_BACKUP="$DEFERRED_PARENT/.nbshell-rollback.deferred-test"
mkdir -p "$DEFERRED_BACKUP"
printf '%s\n' deferred-watchdog >"$DEFERRED_BACKUP/rollback-sentinel"
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$DEFERRED_RUNTIME" "$DEFERRED_BACKUP" deferred
test "$(cat "$DEFERRED_RUNTIME/rollback-sentinel")" = deferred-watchdog

echo "Fresh install and update preservation: OK"
