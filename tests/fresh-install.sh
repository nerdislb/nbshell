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
grid_watch_pid=""
trap '[ -z "${grid_watch_pid:-}" ] || kill "$grid_watch_pid" 2>/dev/null || true; rm -rf "$WORK"' EXIT

TEST_HOME="$WORK/home"
FAKE_BIN="$WORK/bin"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat >"$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
state="${FAKE_SYSTEMD_STATE:?}"
unit="${!#:-}"
printf '%s\n' "$*" >>"$state/systemctl.log"
active_file="$state/active-$unit"
enabled_file="$state/enabled-$unit"
enabled_runtime_file="$state/enabled-runtime-$unit"
linked_file="$state/linked-$unit"
linked_runtime_file="$state/linked-runtime-$unit"
masked_file="$state/masked-$unit"
masked_runtime_file="$state/masked-runtime-$unit"
[ "$unit" = "nbshell.service" ] && active_file="$state/active"
case " $* " in
    *" is-active "*) test -f "$active_file" ;;
    *" is-enabled "*)
        if [ -f "$masked_runtime_file" ]; then
            echo masked-runtime
            exit 1
        elif [ -f "$masked_file" ]; then
            echo masked
            exit 1
        elif [ -f "$enabled_runtime_file" ]; then
            echo enabled-runtime
        elif [ -f "$linked_runtime_file" ]; then
            echo linked-runtime
        elif [ -f "$linked_file" ]; then
            echo linked
        elif [ -f "$enabled_file" ]; then
            echo enabled
        else
            echo disabled
            exit 1
        fi
        ;;
    *" show "*)
        [ -f "$state/fragment-$unit" ] && cat "$state/fragment-$unit"
        ;;
    *" disable "*)
        rm -f "$enabled_file" "$enabled_runtime_file" "$linked_file" "$linked_runtime_file"
        [ ! -L "$XDG_CONFIG_HOME/systemd/user/$unit" ] \
            || rm -f "$XDG_CONFIG_HOME/systemd/user/$unit"
        case " $* " in *" --now "*) rm -f "$active_file" ;; esac
        ;;
    *" enable "*)
        [ ! -f "$masked_file" ] || exit 1
        [ -e "$XDG_CONFIG_HOME/systemd/user/$unit" ] \
            || [ -L "$XDG_CONFIG_HOME/systemd/user/$unit" ] \
            || exit 1
        case " $* " in
            *" --runtime "*) touch "$enabled_runtime_file" ;;
            *) touch "$enabled_file" ;;
        esac
        case " $* " in *" --now "*) touch "$active_file" ;; esac
        ;;
    *" unmask "*) rm -f "$masked_file" "$masked_runtime_file" ;;
    *" mask "*)
        rm -f "$enabled_file" "$enabled_runtime_file"
        case " $* " in
            *" --runtime "*) touch "$masked_runtime_file" ;;
            *) touch "$masked_file" ;;
        esac
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
        if [ -f "$masked_file" ] || [ -f "$masked_runtime_file" ]; then
            exit 1
        elif [ "$unit" = "nbshell.service" ] \
                && [ -f "$state/fail-next-nbshell-start" ]; then
            rm -f "$state/fail-next-nbshell-start"
            exit 1
        elif [ -f "$state/fail-next-start" ]; then
            rm -f "$state/fail-next-start"
            exit 1
        fi
        touch "$active_file"
        ;;
    *" link "*)
        fragment="$unit"
        linked_unit="$(basename "$fragment")"
        printf '%s\n' "$fragment" >"$state/fragment-$linked_unit"
        case " $* " in
            *" --runtime "*) touch "$state/linked-runtime-$linked_unit" ;;
            *) touch "$state/linked-$linked_unit" ;;
        esac
        ;;
    *" restart "*) touch "$active_file" ;;
    *) exit 0 ;;
esac
EOF

cat >"$FAKE_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
state="${FAKE_SYSTEMD_STATE:?}"
printf '%s\n' "$*" >"$state/last-systemd-run"
if [ -f "$FAKE_SYSTEMD_STATE/require-stale-watchdog-stopped" ]; then
    IFS= read -r stale_unit <"$FAKE_SYSTEMD_STATE/require-stale-watchdog-stopped"
    [ ! -e "$FAKE_SYSTEMD_STATE/active-$stale_unit.timer" ] \
        && [ ! -e "$FAKE_SYSTEMD_STATE/active-$stale_unit.service" ] \
        || exit 2
    printf '%s\n' "$stale_unit" >"$FAKE_SYSTEMD_STATE/stale-watchdog-stopped-before-run"
    rm -f "$FAKE_SYSTEMD_STATE/require-stale-watchdog-stopped"
fi
[ ! -f "$state/fail-systemd-run" ] || {
    rm -f "$state/fail-systemd-run"
    exit 1
}
command=()
environment=()
record_command=0
for argument in "$@"; do
    if [[ $argument = --setenv=* ]]; then
        environment+=("${argument#--setenv=}")
    elif [ $record_command -eq 1 ]; then
        command+=("$argument")
    elif [ "$argument" = flock ]; then
        record_command=1
        command+=("$argument")
    fi
done
if [ ${#command[@]} -gt 1 ]; then
    if flock -n "${command[1]}" true 2>/dev/null; then
        touch "$state/queued-observed-lock-free"
    else
        touch "$state/queued-observed-lock-held"
    fi
fi
run_queued() {
    local label=$1 installer_pid=${2:-} status=0
    if [ -n "$installer_pid" ]; then
        while kill -0 "$installer_pid" 2>/dev/null; do sleep 0.01; done
    fi
    exec 9>&-
    env -u HOME -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME \
        -u XDG_STATE_HOME -u XDG_BIN_HOME "${environment[@]}" \
        "${command[@]}" >"$state/$label.log" 2>&1 || status=$?
    printf '%s\n' "$status" >"$state/$label.status"
    touch "$state/$label.done"
}
case " $* " in
    *" --on-active=1s "*) run_queued queued-recovery & ;;
    *)
        if [ -f "$state/run-watchdog-after-installer-exit" ]; then
            rm -f "$state/run-watchdog-after-installer-exit"
            run_queued watchdog "$PPID" &
        fi
        ;;
esac
exit 0
EOF

cat >"$FAKE_BIN/qs" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ]; then
    [ ! -f "$FAKE_SYSTEMD_STATE/manual-running" ] \
        || printf '%s\n' "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml"
    exit 0
fi
if [ "${1:-}" = "-c" ] && [ "${3:-}" = "kill" ]; then
    rm -f "$FAKE_SYSTEMD_STATE/manual-running"
    touch "$FAKE_SYSTEMD_STATE/manual-stopped"
elif [ "${1:-}" = "-c" ] && [ "${3:-}" = "-d" ]; then
    touch "$FAKE_SYSTEMD_STATE/manual-running" "$FAKE_SYSTEMD_STATE/manual-started"
fi
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
export XDG_STATE_HOME="$TEST_HOME/.local/state"
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

# Aether setup and failed theme application must preserve the private mode of
# the shared nbshell state directory rather than resetting it to install(1)'s
# default 0755.
chmod 700 "$XDG_STATE_HOME/nbshell"
bash "$XDG_CONFIG_HOME/quickshell/nbshell/scripts/aether.sh" install-hook >/dev/null
test "$(stat -Lc '%a' "$XDG_STATE_HOME/nbshell")" = 700
if bash "$XDG_CONFIG_HOME/quickshell/nbshell/scripts/aether.sh" apply >/dev/null 2>&1; then
    echo "Aether apply unexpectedly succeeded without a generated theme" >&2
    exit 1
fi
test "$(stat -Lc '%a' "$XDG_STATE_HOME/nbshell")" = 700

grep -Fq "flock $HOME/.local/state/nbshell/install.lock" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_CONFIG_HOME=$XDG_CONFIG_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_DATA_HOME=$XDG_DATA_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_CACHE_HOME=$XDG_CACHE_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_STATE_HOME=$XDG_STATE_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_BIN_HOME=$XDG_BIN_HOME" \
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
grep -Fq 'NBSHELL_DISABLE_HOT_RELOAD=1' "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
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

# SIGKILL immediately after reserving the versioned transaction leaves no
# metadata to trust. The next installer derives and clears its sibling
# reservations without touching the live runtime.
printf '%s\n' earliest-kill \
    >"$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel"
if python3 - "$ROOT/install.sh" <<'PY' >/dev/null 2>&1
import os
import subprocess
import sys

environment = os.environ.copy()
environment["NBSHELL_INSTALL_TEST_FAULT"] = "post-transaction-reservation-kill"
result = subprocess.run(
    [sys.argv[1]], env=environment, stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL, check=False,
)
raise SystemExit(0 if result.returncode == 0 else 1)
PY
then
    echo "Install unexpectedly survived the earliest SIGKILL fault" >&2
    exit 1
fi
find "$XDG_CONFIG_HOME" -maxdepth 1 \
    -type d -name '.nbshell-install-rollback.v2.*' -print -quit | grep -q .
if NBSHELL_INSTALL_TEST_FAULT=pre-swap "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded after earliest stale cleanup" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = earliest-kill
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

# A failed update restores a shell that was running directly through
# Quickshell, not only one owned by nbshell.service.
rm -f "$FAKE_SYSTEMD_STATE/active" "$FAKE_SYSTEMD_STATE/manual-started" \
    "$FAKE_SYSTEMD_STATE/manual-stopped"
touch "$FAKE_SYSTEMD_STATE/manual-running"
printf '%s\n' manual-before >"$XDG_CONFIG_HOME/quickshell/nbshell/manual-sentinel"
if NBSHELL_INSTALL_TEST_FAULT=post-payload "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Manual-shell update unexpectedly survived the rollback fault" >&2
    exit 1
fi
test -f "$FAKE_SYSTEMD_STATE/manual-stopped"
test -f "$FAKE_SYSTEMD_STATE/manual-started"
test -f "$FAKE_SYSTEMD_STATE/manual-running"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/manual-sentinel")" = manual-before
rm -f "$FAKE_SYSTEMD_STATE/manual-running" "$FAKE_SYSTEMD_STATE/manual-started" \
    "$FAKE_SYSTEMD_STATE/manual-stopped"
touch "$FAKE_SYSTEMD_STATE/active"
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

# SIGKILL in the same pre-exchange window bypasses EXIT. Exercise the actual
# watchdog command captured by fake systemd-run; it must observe the live
# installer lock, wait for process death, then discard the staged-new rollback
# without replacing the still-original runtime.
printf '%s\n' pre-exchange-kill \
    >"$XDG_CONFIG_HOME/quickshell/nbshell/pre-exchange-kill-sentinel"
rm -f "$FAKE_SYSTEMD_STATE/watchdog.done" \
    "$FAKE_SYSTEMD_STATE/watchdog.status" \
    "$FAKE_SYSTEMD_STATE/queued-observed-lock-held"
touch "$FAKE_SYSTEMD_STATE/active" \
    "$FAKE_SYSTEMD_STATE/run-watchdog-after-installer-exit"
if python3 - "$ROOT/install.sh" <<'PY' >/dev/null 2>&1
import os
import subprocess
import sys

environment = os.environ.copy()
environment["NBSHELL_INSTALL_TEST_FAULT"] = "post-first-rename-kill"
result = subprocess.run(
    [sys.argv[1]], env=environment, stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL, check=False,
)
raise SystemExit(0 if result.returncode == 0 else 1)
PY
then
    echo "Install unexpectedly survived the pre-exchange SIGKILL fault" >&2
    exit 1
fi
for _ in {1..200}; do
    [ -f "$FAKE_SYSTEMD_STATE/watchdog.done" ] && break
    sleep 0.01
done
test -f "$FAKE_SYSTEMD_STATE/queued-observed-lock-held"
test "$(cat "$FAKE_SYSTEMD_STATE/watchdog.status")" = 0
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/pre-exchange-kill-sentinel")" \
    = pre-exchange-kill
assert_no_reservations

# A catchable exit immediately after RENAME_EXCHANGE must use the persisted
# runtime identity rather than process-local flags to restore the old tree.
if NBSHELL_INSTALL_TEST_FAULT=post-runtime-exchange-exit "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Install unexpectedly succeeded at the post-runtime-exchange-exit fault" >&2
    exit 1
fi
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/transaction-sentinel")" = pre-swap
test -f "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml"
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
runtime_link_fragment="$WORK/nbshell-upstream-audit.service"
printf '%s\n' runtime-linked-before >"$runtime_link_fragment"
rm -f "$unit_dir/nbshell-upstream-audit.service"
printf '%s\n' retired-agent-before >"$WORK/linked-agent-host.service"
ln -s "$WORK/linked-agent-host.service" "$unit_dir/nbshell-agent-host.service"
printf '%s\n' retired-whatsapp-before >"$unit_dir/nbshell-whatsapp.service"
touch "$FAKE_SYSTEMD_STATE/enabled-nbshell-agent-host.service" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-agent-host.service" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-whatsapp.service" \
    "$FAKE_SYSTEMD_STATE/masked-nbshell-whatsapp.service" \
    "$FAKE_SYSTEMD_STATE/masked-nbshell-umbriel-resume-guard.service" \
    "$FAKE_SYSTEMD_STATE/enabled-runtime-nbshell-sleep-lock.service" \
    "$FAKE_SYSTEMD_STATE/masked-runtime-nbshell-lock.service" \
    "$FAKE_SYSTEMD_STATE/linked-runtime-nbshell-upstream-audit.service"
printf '%s\n' "$runtime_link_fragment" \
    >"$FAKE_SYSTEMD_STATE/fragment-nbshell-upstream-audit.service"
rm -f "$FAKE_SYSTEMD_STATE/enabled-nbshell-upstream-audit.timer" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-upstream-audit.timer" \
    "$FAKE_SYSTEMD_STATE/enabled-nbshell-umbriel-resume-guard.service" \
    "$FAKE_SYSTEMD_STATE/enabled-nbshell-sleep-lock.service"

mkdir -p "$XDG_CONFIG_HOME/niri" "$unit_dir/niri.service.d" \
    "$HOME/.local/lib/nbshell" "$XDG_STATE_HOME/nbshell"
printf '%s\n' 'include "nbshell-takeover.kdl"' 'user-line' >"$XDG_CONFIG_HOME/niri/config.kdl"
printf '%s\n' niri-backup-before >"$XDG_CONFIG_HOME/niri/config.kdl.before-nbshell-umbriel-only"
for name in takeover outputs cursor colors; do
    printf 'niri-%s-before\n' "$name" >"$XDG_CONFIG_HOME/niri/nbshell-$name.kdl"
done
printf '%s\n' niri-unit-before >"$unit_dir/niri.service.d/nbshell.conf"
printf '%s\n' niri-grid-unit-before >"$unit_dir/niri.service.d/nbshell-grid-atomic.conf"
printf '%s\n' niri-atomic-before >"$HOME/.local/lib/nbshell/niri-atomic"
for name in grid-layout.json grid-layout.lock grid-layout-backend; do
    printf 'grid-%s-before\n' "$name" >"$XDG_STATE_HOME/nbshell/$name"
done
bash -c 'exec -a "python grid-layout.py watch" sleep 300' &
grid_watch_pid=$!
printf '%s\n' "$grid_watch_pid" >"$XDG_STATE_HOME/nbshell/grid-layout.pid"
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
test "$(readlink "$unit_dir/nbshell-agent-host.service")" \
    = "$WORK/linked-agent-host.service"
test "$(cat "$unit_dir/nbshell-whatsapp.service")" = retired-whatsapp-before
test -f "$FAKE_SYSTEMD_STATE/enabled-nbshell-agent-host.service"
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-agent-host.service"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-whatsapp.service"
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-whatsapp.service"
test -f "$FAKE_SYSTEMD_STATE/masked-nbshell-whatsapp.service"
test -f "$FAKE_SYSTEMD_STATE/masked-nbshell-umbriel-resume-guard.service"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-umbriel-resume-guard.service"
test -f "$FAKE_SYSTEMD_STATE/enabled-runtime-nbshell-sleep-lock.service"
test ! -e "$FAKE_SYSTEMD_STATE/enabled-nbshell-sleep-lock.service"
test -f "$FAKE_SYSTEMD_STATE/masked-runtime-nbshell-lock.service"
test -f "$FAKE_SYSTEMD_STATE/linked-runtime-nbshell-upstream-audit.service"
test "$(cat "$FAKE_SYSTEMD_STATE/fragment-nbshell-upstream-audit.service")" \
    = "$runtime_link_fragment"
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
for name in grid-layout.json grid-layout.lock grid-layout-backend; do
    test "$(cat "$XDG_STATE_HOME/nbshell/$name")" = "grid-$name-before"
done
test "$(cat "$XDG_STATE_HOME/nbshell/grid-layout.pid")" = "$grid_watch_pid"
kill -0 "$grid_watch_pid"
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
rm -f "$FAKE_SYSTEMD_STATE/masked-nbshell-whatsapp.service"
touch "$FAKE_SYSTEMD_STATE/active" \
    "$FAKE_SYSTEMD_STATE/active-nbshell-whatsapp.service" \
    "$FAKE_SYSTEMD_STATE/masked-runtime-nbshell-whatsapp.service"
if python3 - "$ROOT/install.sh" <<'PY'
import os
import subprocess
import sys

environment = os.environ.copy()
environment["NBSHELL_INSTALL_TEST_FAULT"] = "post-runtime-exchange-kill"
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
test "$(cat "$killed_transaction/mode")" = deferred
# Model the original timer having fired while its service waits for the install
# lock. The retry must cancel both before queuing restart-mode recovery.
touch "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.timer" \
    "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.service"
printf '%s\n' "$killed_recovery_unit" \
    >"$FAKE_SYSTEMD_STATE/require-stale-watchdog-stopped"
# A retry owned by nbshell.service must not stop or replace its own live shell.
# It queues stale recovery behind the lock and exits; the helper runs only after
# that retry has left the service cgroup.
rm -f "$FAKE_SYSTEMD_STATE/queued-recovery.done" \
    "$FAKE_SYSTEMD_STATE/queued-recovery.status" \
    "$FAKE_SYSTEMD_STATE/queued-observed-lock-held"
if NBSHELL_INSTALL_TEST_IN_SERVICE=1 \
        "$ROOT/install.sh" >/dev/null 2>&1; then
    echo "Service-hosted retry unexpectedly continued past stale recovery" >&2
    exit 1
fi
for _ in {1..200}; do
    [ -f "$FAKE_SYSTEMD_STATE/queued-recovery.done" ] && break
    sleep 0.01
done
test -f "$FAKE_SYSTEMD_STATE/queued-observed-lock-held"
test "$(cat "$FAKE_SYSTEMD_STATE/queued-recovery.status")" = 0
test ! -d "$killed_transaction"
test ! -d "$killed_rollback"
test -f "$FAKE_SYSTEMD_STATE/active"
test ! -e "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.timer"
test ! -e "$FAKE_SYSTEMD_STATE/active-$killed_recovery_unit.service"
test "$(cat "$FAKE_SYSTEMD_STATE/stale-watchdog-stopped-before-run")" \
    = "$killed_recovery_unit"
grep -Fq "flock $HOME/.local/state/nbshell/install.lock" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_CONFIG_HOME=$XDG_CONFIG_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_DATA_HOME=$XDG_DATA_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_CACHE_HOME=$XDG_CACHE_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_STATE_HOME=$XDG_STATE_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq -- "--setenv=XDG_BIN_HOME=$XDG_BIN_HOME" \
    "$FAKE_SYSTEMD_STATE/last-systemd-run"
grep -Fq ' restart ' "$FAKE_SYSTEMD_STATE/last-systemd-run"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/kill-sentinel")" = killed-runtime-before
test "$(cat "$XDG_DATA_HOME/nbshell/hermes-jobs/manager.py")" = killed-manager-before
test "$(cat "$XDG_CONFIG_HOME/systemd/user/nbshell-upstream-audit.timer")" = killed-unit-before
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-whatsapp.service"
test -f "$FAKE_SYSTEMD_STATE/masked-runtime-nbshell-whatsapp.service"
test "$(readlink "$unit_dir/nbshell-agent-host.service")" \
    = "$WORK/linked-agent-host.service"
test -f "$FAKE_SYSTEMD_STATE/enabled-nbshell-agent-host.service"
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
for _ in {1..100}; do
    ! kill -0 "$grid_watch_pid" 2>/dev/null && break
    sleep 0.01
done
! kill -0 "$grid_watch_pid" 2>/dev/null
grid_watch_pid=""
test ! -e "$XDG_STATE_HOME/nbshell/grid-layout.json"
test ! -e "$XDG_STATE_HOME/nbshell/grid-layout.lock"
test ! -e "$XDG_STATE_HOME/nbshell/grid-layout.pid"
test ! -e "$XDG_STATE_HOME/nbshell/grid-layout-backend"

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
PARTIAL_BLOCKED="$XDG_BIN_HOME/nbshell"
PARTIAL_GOOD="$XDG_CONFIG_HOME/nbshell/themes"
mkdir -p "$PARTIAL_RUNTIME" "$PARTIAL_BACKUP" "$PARTIAL_TRANSACTION" \
    "$PARTIAL_GOOD"
: >"$PARTIAL_TRANSACTION/units"
mkdir -p "$PARTIAL_TRANSACTION/themes"
printf '%s\n' previous >"$PARTIAL_TRANSACTION/themes/marker"
printf '%s\n' replacement >"$PARTIAL_GOOD/marker"
chmod 500 "$XDG_BIN_HOME"
python3 - "$PARTIAL_TRANSACTION/paths" "$PARTIAL_GOOD" "$PARTIAL_BLOCKED" <<'PY'
import sys

manifest, good, blocked = sys.argv[1:]
with open(manifest, "wb") as output:
    for record in (("present", "themes", good), ("missing", "command", blocked)):
        output.write("\0".join(record).encode() + b"\0")
PY
if "$XDG_BIN_HOME/nbshell-install-recover" \
        "$PARTIAL_RUNTIME" "$PARTIAL_BACKUP" inactive \
        "$PARTIAL_TRANSACTION" "$XDG_BIN_HOME/nbshell" >/dev/null 2>&1; then
    echo "partial recovery unexpectedly reported success" >&2
    exit 1
fi
test "$(cat "$PARTIAL_GOOD/marker")" = previous
test -d "$PARTIAL_TRANSACTION"
chmod 700 "$XDG_BIN_HOME"
rm -rf "$PARTIAL_PARENT" "$PARTIAL_TRANSACTION" "$PARTIAL_GOOD"

# A present record without its backup must preserve both the target and the
# transaction for a later retry.
MISSING_TRANSACTION="$XDG_CONFIG_HOME/.nbshell-install-rollback.missing-backup"
MISSING_BACKUP="$XDG_CONFIG_HOME/partial-quickshell/.nbshell-rollback.missing-backup"
mkdir -p "$PARTIAL_RUNTIME" "$MISSING_BACKUP" "$MISSING_TRANSACTION" "$PARTIAL_GOOD"
: >"$MISSING_TRANSACTION/units"
printf '%s\n' replacement >"$PARTIAL_GOOD/marker"
python3 - "$MISSING_TRANSACTION/paths" "$PARTIAL_GOOD" <<'PY'
import sys

with open(sys.argv[1], "wb") as output:
    output.write(("present\0themes\0" + sys.argv[2] + "\0").encode())
PY
if "$XDG_BIN_HOME/nbshell-install-recover" \
        "$PARTIAL_RUNTIME" "$MISSING_BACKUP" inactive \
        "$MISSING_TRANSACTION" "$XDG_BIN_HOME/nbshell" >/dev/null 2>&1; then
    echo "recovery unexpectedly accepted a missing backup" >&2
    exit 1
fi
test "$(cat "$PARTIAL_GOOD/marker")" = replacement
test -d "$MISSING_TRANSACTION"
rm -rf "$MISSING_TRANSACTION" "$MISSING_BACKUP" "$PARTIAL_GOOD"

# A retained or corrupted manifest cannot redirect deletion outside the exact
# installer-owned destination associated with its key.
UNSAFE_TRANSACTION="$XDG_CONFIG_HOME/.nbshell-install-rollback.unsafe-path"
UNSAFE_BACKUP="$XDG_CONFIG_HOME/partial-quickshell/.nbshell-rollback.unsafe-path"
UNRELATED_PATH="$WORK/unrelated-user-data"
mkdir -p "$PARTIAL_RUNTIME" "$UNSAFE_BACKUP" "$UNSAFE_TRANSACTION" "$UNRELATED_PATH"
: >"$UNSAFE_TRANSACTION/units"
printf '%s\n' keep >"$UNRELATED_PATH/marker"
python3 - "$UNSAFE_TRANSACTION/paths" "$UNRELATED_PATH" <<'PY'
import sys

with open(sys.argv[1], "wb") as output:
    output.write(("missing\0themes\0" + sys.argv[2] + "\0").encode())
PY
if "$XDG_BIN_HOME/nbshell-install-recover" \
        "$PARTIAL_RUNTIME" "$UNSAFE_BACKUP" inactive \
        "$UNSAFE_TRANSACTION" "$XDG_BIN_HOME/nbshell" >/dev/null 2>&1; then
    echo "recovery unexpectedly accepted an unsafe manifest path" >&2
    exit 1
fi
test "$(cat "$UNRELATED_PATH/marker")" = keep
test -d "$UNSAFE_TRANSACTION"
rm -rf "$PARTIAL_PARENT" "$UNSAFE_TRANSACTION" "$UNSAFE_BACKUP" "$UNRELATED_PATH"

# Definition-derived systemd states must not fall through to disable, because
# disabling an indirect unit can mutate other units named by Also=. Activity is
# restored independently, including for a not-found snapshot.
UNIT_STATE_TRANSACTION="$XDG_CONFIG_HOME/.nbshell-install-rollback.unit-states"
UNIT_STATE_BACKUP="$XDG_CONFIG_HOME/partial-quickshell/.nbshell-rollback.unit-states"
mkdir -p "$PARTIAL_RUNTIME" "$UNIT_STATE_BACKUP" "$UNIT_STATE_TRANSACTION"
: >"$UNIT_STATE_TRANSACTION/paths"
: >"$FAKE_SYSTEMD_STATE/systemctl.log"
python3 - "$UNIT_STATE_TRANSACTION/units" "$XDG_CONFIG_HOME/systemd/user" <<'PY'
import sys

manifest, unit_dir = sys.argv[1:]
records = (
    ("nbshell-state-static.service", "static", "1"),
    ("nbshell-state-indirect.service", "indirect", "0"),
    ("nbshell-state-generated.service", "generated", "0"),
    ("nbshell-state-transient.service", "transient", "0"),
    ("nbshell-state-not-found.service", "not-found", "1"),
)
with open(manifest, "wb") as output:
    for unit, state, active in records:
        record = (unit, state, active, "", f"{unit_dir}/{unit}")
        output.write("\0".join(record).encode() + b"\0")
PY
"$XDG_BIN_HOME/nbshell-install-recover" \
    "$PARTIAL_RUNTIME" "$UNIT_STATE_BACKUP" inactive \
    "$UNIT_STATE_TRANSACTION" "$XDG_BIN_HOME/nbshell" >/dev/null 2>&1
assert_not_grep -E ' disable nbshell-state-|^--user disable nbshell-state-' \
    "$FAKE_SYSTEMD_STATE/systemctl.log"
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-state-static.service"
test -f "$FAKE_SYSTEMD_STATE/active-nbshell-state-not-found.service"
test ! -e "$FAKE_SYSTEMD_STATE/active-nbshell-state-indirect.service"
test ! -e "$FAKE_SYSTEMD_STATE/active-nbshell-state-generated.service"
test ! -e "$FAKE_SYSTEMD_STATE/active-nbshell-state-transient.service"
rm -rf "$PARTIAL_PARENT"

assert_no_reservations

echo "Fresh install and update preservation: OK"
