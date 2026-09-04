#!/usr/bin/env bash
# Installiert nbshell.
#
# Target: one command on an Umbriel-based Arch system. Missing dependencies are
# gemeldet statt heimlich nachinstalliert -- Pakete gehoeren in die Hand des
# Benutzers.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_DIR="$CONFIG_HOME/quickshell/nbshell"   # von `qs -c nbshell` gesucht
DATA_DIR="$CONFIG_HOME/nbshell"               # Config und Themes
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nbshell"
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
UNIT_DIR="$CONFIG_HOME/systemd/user"
INSTALL_LOCK="$STATE_DIR/install.lock"

QS_BIN="$(command -v qs || command -v quickshell || true)"

green() { printf '\033[32m%s\033[0m\n' "$1"; }
warn()  { printf '\033[33m%s\033[0m\n' "$1"; }

# Serialize installs started by terminals, the dashboard, or agent sessions.
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
exec 9>"$INSTALL_LOCK"
if ! flock -n 9; then
    warn "Another nbshell installation is already running."
    exit 1
fi

# ── Voraussetzungen ──────────────────────────────────────────────────────
missing=()
command -v quickshell >/dev/null 2>&1 || command -v qs >/dev/null 2>&1 || missing+=("quickshell")
command -v umbriel >/dev/null 2>&1 || missing+=("umbriel")
command -v start-umbriel >/dev/null 2>&1 || missing+=("start-umbriel")

if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing: ${missing[*]}"
    echo "  sudo pacman -S ${missing[*]}"
    echo
fi

# `grep -c` statt `grep -q`: -q steigt beim ersten Treffer aus, das schickt
# fc-list ein SIGPIPE -- und unter `set -o pipefail` gilt die ganze Kette dann
# als gescheitert, obwohl die Schrift da ist.
fc-list 2>/dev/null | grep -ci "JetBrainsMono.*Nerd Font" >/dev/null || \
    warn "Note: 'JetBrainsMono Nerd Font' was not found. Install: ttf-jetbrains-mono-nerd"

# Was ohne ein Programm still bleibt. Dieses Skript installiert bewusst nichts
# -- Pakete gehoeren in die Hand des Benutzers. Wer sie in einem Rutsch will,
# nimmt setup.sh; das holt alles und ruft danach dieses hier auf.
optional_check() {
    command -v "$1" >/dev/null 2>&1 || printf '  %-16s %s (%s)\n' "$1" "$2" "$3"
}

echo
echo "Optional features disabled by missing programs (setup.sh installs them):"
missing_optional="$(
    optional_check wl-paste      "clipboard history"          "wl-clipboard"
    optional_check hyprlock      "fallback screen locking"    "hyprlock"
    optional_check fakeroot      "update checks"              "fakeroot"
    optional_check paru          "AUR updates"                "paru or yay"
    optional_check tuned-adm     "power profiles"             "tuned"
    optional_check notify-send   "script notifications"       "libnotify"
    optional_check git           "installing themes"          "git"
    optional_check khal          "calendar"                   "khal"
    optional_check curl          "weather plugin"             "curl"
    optional_check vdirsyncer    "calendar sync"              "vdirsyncer"
    optional_check wf-recorder   "screen recording"           "wf-recorder"
    optional_check obs           "live streaming"             "obs-studio"
    optional_check slurp         "region selection"           "slurp"
    optional_check satty         "screenshot editing"         "satty"
    optional_check tesseract     "OCR"                        "tesseract tesseract-data-eng"
    optional_check swappy        "screenshot editing"         "swappy"
    optional_check omacut        "video trimming"              "github.com/nerdislb/omacut"
    optional_check checkupdates  "fast update checks"         "pacman-contrib"
    optional_check jq            "helper scripts"             "jq"
    optional_check syncthing     "task sync"                  "syncthing"
    optional_check headsetcontrol "headset battery"           "headsetcontrol"
    optional_check qrencode      "Wi-Fi and phone pairing QR codes" "qrencode"
    optional_check speedtest-cli "network speed tests"        "speedtest-cli"
    optional_check magick        "transparent-bar contrast"   "imagemagick"
    optional_check patch         "WhatsApp layout integration" "patch"
    if [ "$(bash "$SRC/shell/scripts/screensaver.sh" --renderer)" != "ttfx" ]; then
        printf '  %-16s %s (%s)\n' "ttfx >= 0.3.2" "fast Rust screen-saver effects" "github.com/omacom-io/ttfx"
    fi
    optional_check sqlite3       "finding Antigravity accounts" "sqlite"
    optional_check secret-tool   "reading the Antigravity keyring" "libsecret"
    optional_check adb           "Android connection"         "android-tools"
    optional_check scrcpy        "Android mirroring"          "scrcpy"
    optional_check nbphone       "phone mirror control"       "github.com/nerdislb/nbphone"
    optional_check opencode      "local/cloud agent frontend" "opencode"
    optional_check ollama        "local AI models"            "ollama (optional)"
    optional_check voxtype       "local voice dictation"      "voxtype-bin (AUR, optional)"
    optional_check mpv           "native YouTube Music playback" "mpv"
    optional_check yt-dlp        "native YouTube Music playback" "yt-dlp"
    optional_check socat         "Mail OAuth callback"         "socat"
    optional_check openssl       "Mail OAuth PKCE"              "openssl"
)"
if [ -n "$missing_optional" ]; then
    printf '%s\n' "$missing_optional"
else
    echo "  none — everything is available."
fi
echo

# Der Agent fuer Rechteabfragen laesst sich nicht ueber `command -v` finden:
# er liegt unter /usr/lib und wird als User-Unit gestartet, nicht aufgerufen.
# Fehlt er, merkt man es erst, wenn ein Programm nach Rechten fragt und
# scheinbar nichts passiert -- deshalb steht der Hinweis hier und nicht in der
# Liste oben.
polkit_found=""
for unit in hyprpolkitagent polkit-gnome-authentication-agent-1 lxqt-policykit-agent mate-polkit; do
    systemctl --user cat "$unit.service" >/dev/null 2>&1 && { polkit_found="$unit"; break; }
done
if [ -z "$polkit_found" ]; then
    warn "No Polkit agent is installed. Privileged actions may fail silently."
    echo "  Install one with: sudo pacman -S hyprpolkitagent"
    echo "  Then run: nbshell polkit on"
    echo
fi

unit_active=0
was_running=0
defer_service_restart=0
install_ready=0
ytmusic_active=0
recovery_armed=0
recovery_failed=0
shell_stopped=0
rollback_occupied=0
runtime_swapped=0
installer_in_nbshell_unit=0
if grep -Fq '/nbshell.service' /proc/$$/cgroup 2>/dev/null \
        || [ "${NBSHELL_INSTALL_TEST_IN_SERVICE:-0}" = 1 ]; then
    installer_in_nbshell_unit=1
fi
declare -a transaction_states=()
declare -a transaction_keys=()
declare -a transaction_paths=()
declare -a transaction_unit_names=()
declare -a transaction_unit_enabled=()
declare -a transaction_unit_active=()
declare -a transaction_unit_fragments=()
recover_command() {
    "$@" || recovery_failed=1
}
transaction_backup_path() {
    local path="$1" key="$2" state=missing
    if [ -e "$path" ] || [ -L "$path" ]; then
        cp -a --reflink=auto -- "$path" "$TRANSACTION_BACKUP/$key"
        state=present
    fi
    transaction_states+=("$state")
    transaction_keys+=("$key")
    transaction_paths+=("$path")
    printf '%s\0%s\0%s\0' "$state" "$key" "$path" >>"$TRANSACTION_PATHS_MANIFEST"
}
transaction_capture_unit() {
    local unit="$1" enabled fragment active=0
    enabled="$(systemctl --user is-enabled "$unit" 2>/dev/null || true)"
    [ -n "$enabled" ] || enabled=disabled
    if [ -L "$UNIT_DIR/$unit" ]; then
        [ "$enabled" != enabled ] || enabled=enabled-linked
        [ "$enabled" != enabled-runtime ] || enabled=enabled-runtime-linked
    fi
    fragment="$(systemctl --user show --property=FragmentPath --value "$unit" 2>/dev/null || true)"
    systemctl --user is-active --quiet "$unit" >/dev/null 2>&1 && active=1
    transaction_unit_names+=("$unit")
    transaction_unit_enabled+=("$enabled")
    transaction_unit_active+=("$active")
    transaction_unit_fragments+=("$fragment")
    printf '%s\0%s\0%s\0%s\0%s\0' "$unit" "$enabled" "$active" "$fragment" \
        "$UNIT_DIR/$unit" >>"$TRANSACTION_UNITS_MANIFEST"
}
rollback_transaction_paths() {
    local index state key path
    for ((index=${#transaction_paths[@]} - 1; index >= 0; index--)); do
        state="${transaction_states[$index]}"
        key="${transaction_keys[$index]}"
        path="${transaction_paths[$index]}"
        if ! rm -rf -- "$path"; then
            recovery_failed=1
            continue
        fi
        if [ "$state" = present ]; then
            recover_command mkdir -p -- "$(dirname "$path")"
            recover_command cp -a -- "$TRANSACTION_BACKUP/$key" "$path"
        fi
    done
}
rollback_transaction_units() {
    local index unit enabled active fragment unit_path unit_key mask_after
    recover_command systemctl --user daemon-reload >/dev/null 2>&1
    for ((index=${#transaction_unit_names[@]} - 1; index >= 0; index--)); do
        unit="${transaction_unit_names[$index]}"
        enabled="${transaction_unit_enabled[$index]}"
        active="${transaction_unit_active[$index]}"
        fragment="${transaction_unit_fragments[$index]}"
        unit_path="$UNIT_DIR/$unit"
        unit_key="unit-$unit"
        mask_after=""
        # Activity has to be restored while the unit is startable. Reapply a
        # captured mask only after start/stop so masked+active remains possible.
        recover_command systemctl --user unmask "$unit" >/dev/null 2>&1
        case "$enabled" in
            enabled|enabled-linked)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                if [ "$enabled" = enabled-linked ] \
                        || [ -L "$TRANSACTION_BACKUP/$unit_key" ]; then
                    recover_command rm -rf -- "$unit_path"
                    recover_command cp -a -- "$TRANSACTION_BACKUP/$unit_key" "$unit_path"
                    recover_command systemctl --user daemon-reload >/dev/null 2>&1
                fi
                recover_command systemctl --user enable "$unit" >/dev/null 2>&1
                ;;
            enabled-runtime|enabled-runtime-linked)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                if [ "$enabled" = enabled-runtime-linked ] \
                        || [ -L "$TRANSACTION_BACKUP/$unit_key" ]; then
                    recover_command rm -rf -- "$unit_path"
                    recover_command cp -a -- "$TRANSACTION_BACKUP/$unit_key" "$unit_path"
                    recover_command systemctl --user daemon-reload >/dev/null 2>&1
                fi
                recover_command systemctl --user enable --runtime "$unit" >/dev/null 2>&1
                ;;
            linked|alias)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                recover_command rm -rf -- "$unit_path"
                if [ -e "$TRANSACTION_BACKUP/$unit_key" ]                         || [ -L "$TRANSACTION_BACKUP/$unit_key" ]; then
                    recover_command cp -a -- "$TRANSACTION_BACKUP/$unit_key" "$unit_path"
                fi
                recover_command systemctl --user daemon-reload >/dev/null 2>&1
                ;;
            linked-runtime)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                [ -z "$fragment" ]                     || recover_command systemctl --user link --runtime "$fragment" >/dev/null 2>&1
                ;;
            masked)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                mask_after=persistent
                ;;
            masked-runtime)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                mask_after=runtime
                ;;
            disabled)
                recover_command systemctl --user disable "$unit" >/dev/null 2>&1
                ;;
            static|indirect|generated|transient|not-found)
                # These states come from the restored unit definition rather
                # than enablement links. Do not let disable mutate Also= units.
                ;;
            *) recovery_failed=1; continue ;;
        esac
        if [ "$active" -eq 1 ]; then
            recover_command systemctl --user start "$unit" >/dev/null 2>&1
        else
            recover_command systemctl --user stop "$unit" >/dev/null 2>&1
        fi
        case "$mask_after" in
            persistent) recover_command systemctl --user mask "$unit" >/dev/null 2>&1 ;;
            runtime) recover_command systemctl --user mask --runtime "$unit" >/dev/null 2>&1 ;;
        esac
    done
}
rollback_is_runtime() {
    [ -d "$ROLLBACK_SHELL" ] && [ -f "$ROLLBACK_SHELL/shell.qml" ]
}
runtime_identity() {
    stat -Lc '%d:%i' -- "$1" 2>/dev/null
}
runtime_matches_original() {
    local candidate=$1 expected
    [ -f "$TRANSACTION_BACKUP/original-runtime-identity" ] || return 1
    expected=$(cat "$TRANSACTION_BACKUP/original-runtime-identity" 2>/dev/null) || return 1
    [ -n "$expected" ] && [ "$(runtime_identity "$candidate")" = "$expected" ]
}
restore_runtime_from_backup() {
    if ! rm -rf -- "$STAGED_SHELL" \
            || ! cp -a -- "$ROLLBACK_SHELL" "$STAGED_SHELL"; then
        recovery_failed=1
        return 1
    fi
    if [ -e "$SHELL_DIR" ] || [ -L "$SHELL_DIR" ]; then
        if ! mv --exchange -T -- "$SHELL_DIR" "$STAGED_SHELL"; then
            recovery_failed=1
            return 1
        fi
        runtime_restored=1
        recover_command rm -rf -- "$STAGED_SHELL"
        return 0
    fi
    if mv -T -- "$STAGED_SHELL" "$SHELL_DIR"; then
        runtime_restored=1
        return 0
    fi
    recovery_failed=1
    return 1
}
recover_install() {
    result=$?
    local runtime_restored=0
    recovery_failed=0
    # Recovery continues across independent destinations. If any restoration
    # fails, keep the durable backup and watchdog available for a retry.
    set +e
    # RENAME_EXCHANGE is atomic, but a signal may reach Bash after the syscall
    # and before the process-local flags below are assigned. Reconcile those
    # flags from the identity persisted before any mutation so EXIT recovery
    # cannot discard the original runtime in that window.
    if [ $install_ready -ne 1 ] && [ -n "${TRANSACTION_BACKUP:-}" ]; then
        if runtime_matches_original "$ROLLBACK_SHELL"; then
            rollback_occupied=1
            runtime_swapped=1
        elif runtime_matches_original "$SHELL_DIR"; then
            rollback_occupied=0
            runtime_swapped=0
        fi
    fi
    if [ $install_ready -ne 1 ] && [ -n "${TRANSACTION_BACKUP:-}" ]; then
        rollback_transaction_paths
    fi
    if [ $install_ready -ne 1 ] \
            && { [ $runtime_swapped -eq 1 ] || [ $rollback_occupied -eq 1 ]; }; then
        if [ $defer_service_restart -ne 1 ]; then
            recover_command systemctl --user stop nbshell.service >/dev/null 2>&1
        fi
        if [ $rollback_occupied -eq 1 ]; then
            restore_runtime_from_backup || true
        elif [ $runtime_swapped -eq 1 ]; then
            recover_command rm -rf -- "${SHELL_DIR:?}"
        fi
    fi
    if [ $install_ready -ne 1 ] && [ -n "${TRANSACTION_BACKUP:-}" ]; then
        rollback_transaction_units
        if [ $ytmusic_active -eq 1 ]; then
            recover_command systemctl --user restart omarchy-ytmusic.service >/dev/null 2>&1
        fi
        if command -v update-desktop-database >/dev/null 2>&1; then
            recover_command update-desktop-database "$SHARE_DIR/applications" >/dev/null 2>&1
        fi
    fi
    [ ! -d "$STAGED_SHELL" ] || recover_command rm -rf -- "$STAGED_SHELL"
    if [ $unit_active -eq 1 ] && [ $defer_service_restart -ne 1 ] \
            && { [ $runtime_restored -eq 1 ] || [ -d "$SHELL_DIR" ]; }; then
        systemctl --user is-active --quiet nbshell.service 2>/dev/null \
            || recover_command systemctl --user start nbshell.service >/dev/null 2>&1
    elif [ $shell_stopped -eq 1 ] && [ -d "$SHELL_DIR" ]; then
        recover_command "$BIN_DIR/nbshell" start -d >/dev/null 2>&1
    fi
    if [ $install_ready -eq 1 ] && [ $defer_service_restart -eq 1 ] \
            && [ $recovery_failed -eq 0 ]; then
        # The committed transaction and rollback runtime stay available to the
        # already-armed helper, which closes the deferred recovery window.
        return "$result"
    fi
    if [ $recovery_failed -eq 0 ]; then
        if [ $install_ready -ne 1 ] || [ $defer_service_restart -ne 1 ]; then
            [ ! -d "$ROLLBACK_SHELL" ] || rm -rf -- "$ROLLBACK_SHELL"
        fi
        if [ "${recovery_armed:-0}" -eq 1 ]; then
            systemctl --user stop "$recovery_unit.timer" \
                "$recovery_unit.service" >/dev/null 2>&1 || true
        fi
        [ ! -d "${TRANSACTION_BACKUP:-}" ] || rm -rf -- "$TRANSACTION_BACKUP"
    elif [ -n "${TRANSACTION_BACKUP:-}" ]; then
        warn "Recovery was incomplete; backups remain in $TRANSACTION_BACKUP"
    fi
    return "$result"
}

# A killed installer releases the process lock but leaves a durable transaction
# for its watchdog. Recover it synchronously before a retry can touch the same
# destinations; the older timer then finds no transaction to replay.
for stale_transaction in "$CONFIG_HOME"/.nbshell-install-rollback.*; do
    [ -d "$stale_transaction" ] || continue
    if [[ $(basename "$stale_transaction") = .nbshell-install-rollback.v2.* ]] \
            && [ ! -f "$stale_transaction/mutation-started" ]; then
        # Version-2 transactions mark the first installed-state mutation.
        # Before that marker, no rollback is needed and even partially written
        # metadata must not permanently block future installs.
        stale_suffix="${stale_transaction##*.}"
        stale_staged="$CONFIG_HOME/quickshell/.nbshell-stage.$stale_suffix"
        stale_rollback="$CONFIG_HOME/quickshell/.nbshell-rollback.$stale_suffix"
        [ ! -d "$stale_staged" ] || rm -rf -- "$stale_staged"
        if [ -d "$stale_rollback" ] \
                && [ -z "$(find "$stale_rollback" -mindepth 1 -print -quit)" ]; then
            rmdir -- "$stale_rollback"
        fi
        for reservation_metadata in staged-path rollback-path; do
            [ -f "$stale_transaction/$reservation_metadata" ] || continue
            IFS= read -r stale_reservation <"$stale_transaction/$reservation_metadata"
            if [ "$(dirname "$stale_reservation")" = "$CONFIG_HOME/quickshell" ]; then
                case "$(basename "$stale_reservation")" in
                    .nbshell-stage.*)
                        rm -rf -- "$stale_reservation"
                        ;;
                    .nbshell-rollback.*)
                        if [ -d "$stale_reservation" ] \
                                && [ -z "$(find "$stale_reservation" -mindepth 1 -print -quit)" ]; then
                            rmdir -- "$stale_reservation"
                        fi
                        ;;
                esac
            fi
        done
        rm -rf -- "$stale_transaction"
        continue
    fi
    stale_metadata_ok=1
    for metadata_name in shell-path rollback-path staged-path mode command-path recovery-unit; do
        [ -f "$stale_transaction/$metadata_name" ] || stale_metadata_ok=0
    done
    if [ $stale_metadata_ok -ne 1 ] || [ ! -x "$stale_transaction/recover" ]; then
        warn "Incomplete prior install metadata remains in $stale_transaction"
        warn "Recovery cannot continue safely; keep that directory for inspection."
        exit 1
    fi
    IFS= read -r stale_shell <"$stale_transaction/shell-path"
    IFS= read -r stale_rollback <"$stale_transaction/rollback-path"
    IFS= read -r stale_staged <"$stale_transaction/staged-path"
    IFS= read -r stale_mode <"$stale_transaction/mode"
    IFS= read -r stale_command <"$stale_transaction/command-path"
    IFS= read -r stale_unit <"$stale_transaction/recovery-unit"
    case "$stale_unit" in
        nbshell-install-recovery-[A-Za-z0-9]*) ;;
        *)
            warn "Invalid recovery unit metadata in $stale_transaction"
            exit 1
            ;;
    esac
    systemctl --user stop "$stale_unit.timer" \
        "$stale_unit.service" >/dev/null 2>&1 || true
    if systemctl --user is-active --quiet "$stale_unit.timer" 2>/dev/null \
            || systemctl --user is-active --quiet "$stale_unit.service" 2>/dev/null; then
        warn "Could not stop the previous recovery watchdog."
        exit 1
    fi
    if [ $installer_in_nbshell_unit -eq 1 ]; then
        # Never let stale recovery stop or replace the service tree that owns
        # this retry. Queue it behind the lock, then exit so recovery runs only
        # after this process has left nbshell.service. The independent unit can
        # safely restart the service even when the interrupted installer had
        # deferred its own restart.
        retry_unit="${stale_unit}-retry-$$"
        queued_recovery_mode=restart
        if systemd-run --user --quiet --unit="$retry_unit" --on-active=1s \
                --timer-property=AccuracySec=1s \
                --setenv="HOME=$HOME" \
                --setenv="XDG_CONFIG_HOME=$CONFIG_HOME" \
                --setenv="XDG_DATA_HOME=$SHARE_DIR" \
                --setenv="XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}" \
                --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
                --setenv="XDG_BIN_HOME=$BIN_DIR" \
                flock "$INSTALL_LOCK" "$stale_transaction/recover" \
                "$stale_shell" "$stale_rollback" "$queued_recovery_mode" \
                "$stale_transaction" "$stale_command" "$stale_staged"; then
            warn "Interrupted installation recovery was queued; retry after nbshell restarts."
        else
            warn "Could not queue recovery of the interrupted installation."
        fi
        exit 1
    fi
    if ! "$stale_transaction/recover" "$stale_shell" "$stale_rollback" \
            "$stale_mode" "$stale_transaction" "$stale_command" "$stale_staged"; then
        warn "Recovery of the interrupted prior installation failed."
        exit 1
    fi
done

# Prepare and validate a complete runtime before stopping the bar. All three
# reservations share a transaction suffix, so an early SIGKILL can be cleaned
# without trusting metadata that may not have been written yet.
mkdir -p "$CONFIG_HOME/quickshell"
TRANSACTION_BACKUP="$(mktemp -d "$CONFIG_HOME/.nbshell-install-rollback.v2.XXXXXX")"
reservation_suffix="${TRANSACTION_BACKUP##*.}"
STAGED_SHELL="$CONFIG_HOME/quickshell/.nbshell-stage.$reservation_suffix"
ROLLBACK_SHELL="$CONFIG_HOME/quickshell/.nbshell-rollback.$reservation_suffix"
if [ "${NBSHELL_INSTALL_TEST_FAULT:-}" = "post-transaction-reservation-kill" ]; then
    kill -KILL "$$"
fi
if ! mkdir -- "$STAGED_SHELL" "$ROLLBACK_SHELL"; then
    rm -rf -- "$STAGED_SHELL"
    [ ! -d "$ROLLBACK_SHELL" ] || rmdir -- "$ROLLBACK_SHELL"
    rm -rf -- "$TRANSACTION_BACKUP"
    exit 1
fi
TRANSACTION_PATHS_MANIFEST="$TRANSACTION_BACKUP/paths"
TRANSACTION_UNITS_MANIFEST="$TRANSACTION_BACKUP/units"
recovery_unit="nbshell-install-recovery-${TRANSACTION_BACKUP##*.}"
# Arm cleanup immediately after all reservations. Manifest creation and every
# later backup or mutation are covered by this trap.
trap recover_install EXIT
: >"$TRANSACTION_PATHS_MANIFEST"
: >"$TRANSACTION_UNITS_MANIFEST"
[ ! -d "$SHELL_DIR" ] || touch "$TRANSACTION_BACKUP/original-runtime-present"
systemctl --user is-active --quiet omarchy-ytmusic.service 2>/dev/null \
    && touch "$TRANSACTION_BACKUP/ytmusic-active" || true
install -m 755 "$SRC/bin/nbshell-install-recover" "$TRANSACTION_BACKUP/recover"
printf '%s\n' "$SHELL_DIR" >"$TRANSACTION_BACKUP/shell-path"
printf '%s\n' "$ROLLBACK_SHELL" >"$TRANSACTION_BACKUP/rollback-path"
printf '%s\n' "$STAGED_SHELL" >"$TRANSACTION_BACKUP/staged-path"
printf '%s\n' inactive >"$TRANSACTION_BACKUP/mode"
printf '%s\n' "$BIN_DIR/nbshell" >"$TRANSACTION_BACKUP/command-path"
printf '%s\n' "$recovery_unit" >"$TRANSACTION_BACKUP/recovery-unit"

# Build and validate the complete runtime before changing any installed file or
# user-unit state. A malformed source tree therefore fails without even a
# temporary service interruption.
cp -a "$SRC/shell/." "$STAGED_SHELL/"
cp -a "$SRC/integrations" "$STAGED_SHELL/"
install -m 644 "$SRC/VERSION" "$STAGED_SHELL/VERSION"
bash -n "$SRC/install.sh"
bash -n "$SRC/bin/nbshell" "$SRC/bin/nbshell-install-recover"
while IFS= read -r -d '' script; do bash -n "$script"; done < <(find "$SRC/shell/scripts" -type f -name '*.sh' -print0)
python3 -c 'import ast, pathlib, sys; [ast.parse(pathlib.Path(name).read_text()) for name in sys.argv[1:]]' \
    "$STAGED_SHELL/scripts/agents.py" \
    "$STAGED_SHELL/scripts/config-migrations.py" \
    "$STAGED_SHELL/scripts/umbriel-contract.py"
QMLLINT_BIN="$(command -v qmllint || true)"
[ -n "$QMLLINT_BIN" ] || [ ! -x /usr/lib/qt6/bin/qmllint ] || QMLLINT_BIN=/usr/lib/qt6/bin/qmllint
if [ -n "$QMLLINT_BIN" ]; then
    "$QMLLINT_BIN" "$STAGED_SHELL/shell.qml" >/dev/null 2>&1
fi
if [ -f "$TRANSACTION_BACKUP/original-runtime-present" ]; then
    runtime_identity "$SHELL_DIR" >"$TRANSACTION_BACKUP/original-runtime-identity"
fi
if [ "${NBSHELL_INSTALL_TEST_FAULT:-}" = "pre-watchdog-kill" ]; then
    kill -KILL "$$"
fi
if [ "${NBSHELL_INSTALL_TEST_FAULT:-}" = "pre-swap" ]; then
    exit 97
fi

# Arm a user-manager watchdog before the first installed path or service state
# changes. The recovery executable lives inside the durable transaction so a
# first install is protected even before the command payload exists.
systemctl --user is-active --quiet nbshell.service 2>/dev/null && unit_active=1
if [ $unit_active -ne 1 ] && "$QS_BIN" list --all 2>/dev/null | grep -c "quickshell/nbshell/shell.qml" >/dev/null; then
    was_running=1
fi
restart_policy="${NBSHELL_INSTALL_DEFER_RESTART:-auto}"
if [ $unit_active -eq 1 ] && { [ "$restart_policy" = "1" ] \
        || { [ "$restart_policy" = "auto" ] \
            && [ $installer_in_nbshell_unit -eq 1 ]; }; }; then
    defer_service_restart=1
fi
recovery_mode=inactive
if [ $unit_active -eq 1 ]; then
    recovery_mode=restart
    [ $defer_service_restart -ne 1 ] || recovery_mode=deferred
elif [ $was_running -eq 1 ]; then
    recovery_mode=manual
fi
printf '%s\n' "$recovery_mode" >"$TRANSACTION_BACKUP/mode"
if systemd-run --user --quiet --unit="$recovery_unit" --on-active=120s \
        --timer-property=AccuracySec=1s \
        --setenv="HOME=$HOME" \
        --setenv="XDG_CONFIG_HOME=$CONFIG_HOME" \
        --setenv="XDG_DATA_HOME=$SHARE_DIR" \
        --setenv="XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}" \
        --setenv="XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
        --setenv="XDG_BIN_HOME=$BIN_DIR" \
        flock "$INSTALL_LOCK" "$TRANSACTION_BACKUP/recover" \
        "$SHELL_DIR" "$ROLLBACK_SHELL" "$recovery_mode" \
        "$TRANSACTION_BACKUP" "$BIN_DIR/nbshell" "$STAGED_SHELL"; then
    recovery_armed=1
else
    warn "Could not arm independent recovery; leaving installed state untouched."
    exit 1
fi

# Snapshot every destination owned or retired by the installer before the
# first payload or unit-state mutation. User configuration and plugin trees
# keep their narrower per-file backups below so unrelated content remains
# untouched.
transaction_backup_path "$SHARE_DIR/nbshell" share-nbshell
transaction_backup_path "$DATA_DIR/themes" themes
transaction_backup_path "$BIN_DIR/nbshell" command
transaction_backup_path "$BIN_DIR/nbshell-install-recover" recovery-command
transaction_backup_path "$CONFIG_HOME/aether/custom/nbshell" aether-hook
transaction_backup_path "$SHARE_DIR/applications/dev.nerdi.nbshell.desktop" app-shell
transaction_backup_path "$SHARE_DIR/applications/dev.nerdi.nbshell.Calculator.desktop" app-calculator
transaction_backup_path "$CONFIG_HOME/omarchy-gmail" old-mail-config
transaction_backup_path "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-gmail" old-mail-cache
transaction_backup_path "$CONFIG_HOME/omamail" mail-config
transaction_backup_path "${XDG_CACHE_HOME:-$HOME/.cache}/omamail" mail-cache
transaction_backup_path "$CONFIG_HOME/niri/config.kdl" niri-config
transaction_backup_path "$CONFIG_HOME/niri/config.kdl.before-nbshell-umbriel-only" niri-config-backup
transaction_backup_path "$CONFIG_HOME/niri/nbshell-takeover.kdl" niri-takeover
transaction_backup_path "$CONFIG_HOME/niri/nbshell-outputs.kdl" niri-outputs
transaction_backup_path "$CONFIG_HOME/niri/nbshell-cursor.kdl" niri-cursor
transaction_backup_path "$CONFIG_HOME/niri/nbshell-colors.kdl" niri-colors
transaction_backup_path "$UNIT_DIR/niri.service.d/nbshell.conf" niri-unit
transaction_backup_path "$UNIT_DIR/niri.service.d/nbshell-grid-atomic.conf" niri-grid-unit
transaction_backup_path "$HOME/.local/lib/nbshell/niri-atomic" niri-atomic
transaction_backup_path "$STATE_DIR/grid-layout.json" grid-json
transaction_backup_path "$STATE_DIR/grid-layout.lock" grid-lock
transaction_backup_path "$STATE_DIR/grid-layout.pid" grid-pid
transaction_backup_path "$STATE_DIR/grid-layout-backend" grid-backend
for skill_home in \
    "$HOME/.agents/skills" \
    "$HOME/.claude/skills" \
    "$HOME/.codex/skills" \
    "$HOME/.pi/agent/skills"; do
    transaction_backup_path "$skill_home/nbshell" "skill-$(basename "$(dirname "$skill_home")")"
done
transaction_backup_path "$HOME/.gemini/skills/nbshell" skill-gemini
for unit in \
    nbshell.service \
    nbshell-lock.service \
    nbshell-sleep-lock.service \
    nbshell-umbriel-resume-guard.service \
    nbshell-upstream-audit.service \
    nbshell-upstream-audit.timer \
    nbshell-agent-host.service \
    nbshell-whatsapp.service; do
    transaction_backup_path "$UNIT_DIR/$unit" "unit-$unit"
done
for unit in \
    nbshell-sleep-lock.service \
    nbshell-umbriel-resume-guard.service \
    nbshell-upstream-audit.service \
    nbshell-upstream-audit.timer \
    nbshell-agent-host.service \
    nbshell-whatsapp.service; do
    transaction_capture_unit "$unit"
done
touch "$TRANSACTION_BACKUP/mutation-started"

# ── Shell ────────────────────────────────────────────────────────────────
# Install the shell lifecycle unit before touching the running shell.
mkdir -p "$UNIT_DIR"
install -m 644 "$SRC/systemd/nbshell.service" "$UNIT_DIR/nbshell.service"
install -m 644 "$SRC/systemd/nbshell-lock.service" "$UNIT_DIR/nbshell-lock.service"
install -m 644 "$SRC/systemd/nbshell-sleep-lock.service" "$UNIT_DIR/nbshell-sleep-lock.service"
install -m 644 "$SRC/systemd/nbshell-umbriel-resume-guard.service" \
    "$UNIT_DIR/nbshell-umbriel-resume-guard.service"
install -m 644 "$SRC/systemd/nbshell-upstream-audit.service" "$UNIT_DIR/nbshell-upstream-audit.service"
install -m 644 "$SRC/systemd/nbshell-upstream-audit.timer" "$UNIT_DIR/nbshell-upstream-audit.timer"
install -Dm644 "$SRC/resources/hermes-pilot/AGENTS.md" \
    "$SHARE_DIR/nbshell/hermes-pilot/AGENTS.md"
install -Dm755 "$SRC/resources/hermes-broker/server.py" \
    "$SHARE_DIR/nbshell/hermes-broker/server.py"
install -Dm755 "$SRC/resources/hermes-jobs/manager.py" \
    "$SHARE_DIR/nbshell/hermes-jobs/manager.py"
install -Dm755 "$SRC/resources/hermes-team/manager.py" \
    "$SHARE_DIR/nbshell/hermes-team/manager.py"
install -Dm755 "$SRC/resources/hermes-brain/manager.py" \
    "$SHARE_DIR/nbshell/hermes-brain/manager.py"
# Remove the retired Agent Console host from installations that tested it.
systemctl --user disable --now nbshell-agent-host.service >/dev/null 2>&1 || true
rm -f "$UNIT_DIR/nbshell-agent-host.service"
# Remove the retired Node/Baileys WhatsApp bridge. Its user data is preserved;
# the supported providers are the local-first wacli client and PrettyZap.
systemctl --user disable --now nbshell-whatsapp.service >/dev/null 2>&1 || true
rm -f "$UNIT_DIR/nbshell-whatsapp.service"
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/nbshell-install-recover" "$BIN_DIR/nbshell-install-recover"
install -m 755 "$SRC/bin/nbshell" "$BIN_DIR/nbshell"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable nbshell-umbriel-resume-guard.service >/dev/null 2>&1 || true
systemctl --user enable --now nbshell-upstream-audit.timer >/dev/null 2>&1 || true

if [ $unit_active -eq 1 ] && [ $defer_service_restart -ne 1 ]; then
    systemctl --user stop nbshell.service
elif [ "$was_running" = "1" ]; then
    if "${SRC}/bin/nbshell" stop >/dev/null 2>&1; then
        shell_stopped=1
    else
        warn "Could not stop the running nbshell instance; installation aborted."
        exit 1
    fi
    sleep 0.3
fi

# A stopped shell cannot race the config snapshot. Service-hosted installs keep
# their already-loaded old QML process alive and defer migration to the next
# start, which is safe because the new CLI has already been installed above.
if [ $defer_service_restart -ne 1 ] && [ -f "$DATA_DIR/config.json" ]; then
    python3 "$SRC/shell/scripts/config-migrations.py" apply >/dev/null
fi

if [ -d "$SHELL_DIR" ]; then
    # Put the validated tree at the rollback name first, while the old runtime
    # remains live. The exchange then changes both names in one syscall, so a
    # service-hosted install can never observe SHELL_DIR missing.
    rmdir -- "$ROLLBACK_SHELL"
    mv -T -- "$STAGED_SHELL" "$ROLLBACK_SHELL"
    [ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-first-rename" ] || exit 98
    [ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-first-rename-kill" ] || kill -KILL "$$"
    mv --exchange -T -- "$SHELL_DIR" "$ROLLBACK_SHELL"
    [ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-runtime-exchange-exit" ] || exit 97
    [ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-runtime-exchange-kill" ] || kill -KILL "$$"
    rollback_occupied=1
    runtime_swapped=1
else
    # There is no old runtime to preserve on first install. Mark the rename
    # before executing it so EXIT recovery also covers interruption after the
    # syscall but before Bash observes its return.
    runtime_swapped=1
    mv -T -- "$STAGED_SHELL" "$SHELL_DIR"
fi

green "Shell   -> $SHELL_DIR"

# ── Themes ───────────────────────────────────────────────────────────────
# Mitgelieferte Farbdateien installieren. Vorhandene werden ueberschrieben,
# eigene daneben bleiben stehen.
mkdir -p "$DATA_DIR/themes"
cp -a "$SRC/themes/." "$DATA_DIR/themes/"
green "Themes  -> $DATA_DIR/themes ($(find "$DATA_DIR/themes" -name colors.toml | wc -l) installed)"

# Einmalige Migration der bisher gemeinsam benutzten Bilder. Ab jetzt liest
# nbshell nur noch seinen eigenen Datenbereich; das alte Verzeichnis kann
# danach samt DMS geloescht werden.
OLD_WALLPAPERS="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy2dms/wallpapers"
NEW_WALLPAPERS="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/wallpapers"
mkdir -p "$NEW_WALLPAPERS"
cp -a "$SRC/wallpapers/." "$NEW_WALLPAPERS/"
if [ -d "$OLD_WALLPAPERS" ]; then
    cp -an "$OLD_WALLPAPERS/." "$NEW_WALLPAPERS/"
fi
green "Images  -> $NEW_WALLPAPERS ($(find "$NEW_WALLPAPERS" -type f | wc -l) available)"

# ── Config ───────────────────────────────────────────────────────────────
# Nur anlegen, nie ueberschreiben: sie gehoert dem Benutzer.
if [ ! -f "$DATA_DIR/config.json" ]; then
    transaction_backup_path "$DATA_DIR/config.json" config.json
    cat > "$DATA_DIR/config.json" <<'JSON'
{
  "schemaVersion": 1,
  "theme": "tokyo-night",
  "mode": "bar",
  "edge": "top",
  "font": "JetBrainsMono Nerd Font",
  "fontSize": 14,
  "gap": 6,
  "radius": 2,
  "borderWidth": 1,
  "opacity": 1.0,
  "motionProfile": "standard",
  "wallpaper": true,
  "widgetStyle": "plain",
  "enabledPlugins": [],
  "collapsedWidgets": ["clock"],
  "leftWidgets": ["workspaces", "sep", "window"],
  "centerWidgets": ["clock"],
  "rightWidgets": ["sys", "sep", "tray", "notifications", "volume", "control", "themes", "battery"],
  "rightSectionExpanded": true
}
JSON
    green "Config  -> $DATA_DIR/config.json (created)"
else
    echo "Config  -> $DATA_DIR/config.json (existing file kept)"
fi
[ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-config" ] || exit 99

# Fresh installs reach this point without a prior config. Non-deferred installs
# also record the baseline ledger here; deferred service-hosted updates migrate
# on their next start, before the new QML process launches.
if [ $defer_service_restart -ne 1 ]; then
    python3 "$SHELL_DIR/scripts/config-migrations.py" apply >/dev/null
fi

# ── Plugins ──────────────────────────────────────────────────────────────
# Nur das Verzeichnis anlegen und die Vorlage hineinlegen, falls sie fehlt.
# Was hier drin liegt, gehoert dem Benutzer -- es wird nie ueberschrieben.
mkdir -p "$DATA_DIR/plugins"
added=()
for plugin in "$SRC"/plugins/*/; do
    [ -d "$plugin" ] || continue
    "$SRC/shell/scripts/plugins.sh" validate "$plugin" >/dev/null ||
        die "Bundled plugin failed validation: $(basename "$plugin")"
    "$SRC/shell/scripts/plugins.sh" design-check "$plugin" --strict >/dev/null ||
        die "Bundled plugin failed the strict design contract: $(basename "$plugin")"
    name="$(basename "$plugin")"
    if [ -f "$plugin/.nbshell-managed" ] && [ -f "$DATA_DIR/plugins/$name/.nbshell-managed" ]; then
        transaction_backup_path "$DATA_DIR/plugins/$name" "plugin-$name"
        rm -rf "$DATA_DIR/plugins/$name"
        cp -a "$plugin" "$DATA_DIR/plugins/"
        added+=("$name updated")
        continue
    fi
    [ -d "$DATA_DIR/plugins/$name" ] && continue
    transaction_backup_path "$DATA_DIR/plugins/$name" "plugin-$name"
    cp -a "$plugin" "$DATA_DIR/plugins/"
    added+=("$name")
done
[ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-plugin" ] || exit 100
if [ ${#added[@]} -gt 0 ]; then
    green "Plugins -> $DATA_DIR/plugins (added: ${added[*]})"
else
    echo "Plugins -> $DATA_DIR/plugins ($(find "$DATA_DIR/plugins" -maxdepth 2 -name manifest.json 2>/dev/null | wc -l) installed, existing files kept)"
fi

# Mail owns a one-time migration from its pre-0.2 `omarchy-gmail` state. Run
# the installed, reviewed helper on both fresh and update paths; it is
# idempotent and never touches current `omamail` state.
if [ -x "$DATA_DIR/plugins/omamail/scripts/migrate-storage.sh" ]; then
    "$DATA_DIR/plugins/omamail/scripts/migrate-storage.sh"
fi

# Managed plugin updates must also refresh an already installed backend copy.
# The YouTube Music service deliberately runs outside the plugin tree, so merely
# replacing its QML/plugin files would otherwise leave old authentication and
# playback code active indefinitely.
YTMUSIC_RUNTIME="$HOME/.local/lib/omarchy-ytmusic"
YTMUSIC_VENV="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-ytmusic/venv/bin/python"
if [ -d "$YTMUSIC_RUNTIME" ] && [ -x "$YTMUSIC_VENV" ] \
        && [ -d "$DATA_DIR/plugins/ytmusic/backend" ]; then
    transaction_backup_path "$YTMUSIC_RUNTIME" ytmusic-runtime
    install -m 644 -- "$DATA_DIR/plugins/ytmusic/backend/"*.py "$YTMUSIC_RUNTIME/"
    chmod 755 -- "$YTMUSIC_RUNTIME/server.py"
    "$YTMUSIC_VENV" "$YTMUSIC_RUNTIME/server.py" --self-test >/dev/null
    if systemctl --user is-active --quiet omarchy-ytmusic.service 2>/dev/null; then
        ytmusic_active=1
        systemctl --user restart omarchy-ytmusic.service
    fi
    green "YT Music -> refreshed installed backend"
fi

# ── systemd-Unit ─────────────────────────────────────────────────────────
# The shell lifecycle remains opt-in via `nbshell switch on`; the narrow
# Umbriel recovery guard is enabled independently above.
green "Units   -> $UNIT_DIR (shell lifecycle, sleep lock inhibitor, isolated locker, and Umbriel resume guard)"

# Umbriel is the supported compositor. Installing its include does not alter
# unrelated user configuration.
mkdir -p "$CONFIG_HOME/umbriel"
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell.toml" umbriel-main
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell-motion.toml" umbriel-motion
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell-nested.toml" umbriel-nested
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell-outputs.toml" umbriel-outputs
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell-cursor.toml" umbriel-cursor
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell-overview.toml" umbriel-overview
transaction_backup_path "$CONFIG_HOME/umbriel/nbshell-colors.toml" umbriel-colors
transaction_backup_path "$CONFIG_HOME/umbriel/config.toml" umbriel-config
install -m 644 "$SRC/umbriel/nbshell.toml" "$CONFIG_HOME/umbriel/nbshell.toml"
install -m 644 "$SRC/umbriel/nbshell-motion.toml" "$CONFIG_HOME/umbriel/nbshell-motion.toml"
install -m 644 "$SRC/umbriel/nbshell-nested.toml" "$CONFIG_HOME/umbriel/nbshell-nested.toml"
if [ ! -f "$CONFIG_HOME/umbriel/nbshell-outputs.toml" ]; then
    printf '# Managed by nbshell display; intentionally empty until a setting is saved.\n' > "$CONFIG_HOME/umbriel/nbshell-outputs.toml"
fi
if [ ! -f "$CONFIG_HOME/umbriel/nbshell-cursor.toml" ]; then
    install -m 644 "$SRC/umbriel/nbshell-cursor.toml" "$CONFIG_HOME/umbriel/nbshell-cursor.toml"
fi
if [ ! -f "$CONFIG_HOME/umbriel/nbshell-overview.toml" ]; then
    install -m 644 "$SRC/umbriel/nbshell-overview.toml" "$CONFIG_HOME/umbriel/nbshell-overview.toml"
fi
if [ ! -f "$CONFIG_HOME/umbriel/nbshell-colors.toml" ]; then
    install -m 644 "$SRC/umbriel/nbshell-colors.toml" "$CONFIG_HOME/umbriel/nbshell-colors.toml"
fi
if [ ! -f "$CONFIG_HOME/umbriel/config.toml" ]; then
    printf '# Standalone Umbriel configuration created by nbshell\n[include]\nfiles = ["nbshell-colors.toml", "nbshell.toml"]\n' > "$CONFIG_HOME/umbriel/config.toml"
    green "Umbriel -> $CONFIG_HOME/umbriel/config.toml (created)"
fi
green "Umbriel -> $CONFIG_HOME/umbriel/nbshell.toml"
[ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-umbriel" ] || exit 101

if [ $unit_active -eq 1 ] && [ $defer_service_restart -ne 1 ]; then
    systemctl --user start nbshell.service
    sleep 2
    if ! systemctl --user is-active --quiet nbshell.service; then
        warn "The new shell did not stay active; restoring the previous runtime."
        exit 1
    fi
elif [ $defer_service_restart -eq 1 ]; then
    warn "Shell restart deferred because this installer runs inside nbshell.service."
    warn "The new runtime will load after the service is restarted outside this shell or at the next login."
elif [ "$was_running" = "1" ]; then
    "$BIN_DIR/nbshell" start -d >/dev/null 2>&1 &
fi
systemctl --user enable nbshell-sleep-lock.service >/dev/null 2>&1 || true
if systemctl --user is-active --quiet graphical-session.target; then
    if ! systemctl --user restart nbshell-sleep-lock.service >/dev/null 2>&1 ||
            ! systemctl --user is-active --quiet nbshell-sleep-lock.service; then
        warn "The sleep lock inhibitor did not stay active."
        exit 1
    fi
fi
if [ -n "${UMBRIEL_SOCKET:-}" ]; then
    systemctl --user restart nbshell-umbriel-resume-guard.service >/dev/null 2>&1 || true
fi

# Remove only nbshell-owned artifacts from retired Niri installations. Preserve
# every unrelated user line and file.
NIRI_CONFIG="$CONFIG_HOME/niri/config.kdl"
if [ -f "$NIRI_CONFIG" ]; then
    python3 - "$NIRI_CONFIG" <<'PY'
from pathlib import Path
import shutil, sys
path = Path(sys.argv[1])
managed = {
    'include "nbshell-takeover.kdl"',
    'include "nbshell-outputs.kdl"',
    'include "nbshell-cursor.kdl"',
    'include "nbshell-colors.kdl"',
}
lines = path.read_text(encoding="utf-8").splitlines()
kept = [line for line in lines if line.strip() not in managed]
if kept != lines:
    shutil.copy2(path, path.with_name("config.kdl.before-nbshell-umbriel-only"))
    path.write_text("\n".join(kept) + "\n", encoding="utf-8")
PY
fi
rm -f "$CONFIG_HOME/niri/nbshell-takeover.kdl" \
    "$CONFIG_HOME/niri/nbshell-outputs.kdl" \
    "$CONFIG_HOME/niri/nbshell-cursor.kdl" \
    "$CONFIG_HOME/niri/nbshell-colors.kdl" \
    "$UNIT_DIR/niri.service.d/nbshell.conf" \
    "$UNIT_DIR/niri.service.d/nbshell-grid-atomic.conf" \
    "$HOME/.local/lib/nbshell/niri-atomic"
rmdir "$UNIT_DIR/niri.service.d" 2>/dev/null || true
retired_grid_pid=""
if [ -f "$STATE_DIR/grid-layout.pid" ]; then
    grid_pid="$(cat "$STATE_DIR/grid-layout.pid" 2>/dev/null || true)"
    if [[ $grid_pid =~ ^[0-9]+$ ]] && tr '\0' ' ' <"/proc/$grid_pid/cmdline" 2>/dev/null | grep -Fq 'grid-layout.py watch'; then
        retired_grid_pid="$grid_pid"
    fi
fi
rm -f "$STATE_DIR/grid-layout.json" "$STATE_DIR/grid-layout.lock" \
    "$STATE_DIR/grid-layout.pid" "$STATE_DIR/grid-layout-backend"

# Native workspace snapshots now come directly from Umbriel IPC. Remove the
# retired protocol helper from installations that previously built it.
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/bin/umbriel-workspaces" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/native/umbriel-workspaces.c"
rmdir "${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/native" 2>/dev/null || true

# ── Befehl ───────────────────────────────────────────────────────────────
green "Command -> $BIN_DIR/nbshell"

# Aether supports custom applications with a post-apply hook. Register the
# nbshell bridge when Aether is present so its own Apply button can activate
# the generated palette without a second manual import step.
if command -v aether >/dev/null 2>&1; then
    bash "$SHELL_DIR/scripts/aether.sh" install-hook >/dev/null
    green "Aether  -> Apply updates nbshell automatically"
fi

GREETER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell"
mkdir -p "$GREETER_DATA/greeter"
install -m 755 "$SRC/setup-greeter.sh" "$GREETER_DATA/setup-greeter.sh"
install -m 755 "$SRC/setup-locker.sh" "$GREETER_DATA/setup-locker.sh"
mkdir -p "$GREETER_DATA/locker"
install -m 644 "$SRC/shell/lock/nbshell-lock.pam" "$GREETER_DATA/locker/nbshell-lock.pam"
install -m 644 "$SRC/greeter/nbshell-greetd.pam" "$GREETER_DATA/greeter/nbshell-greetd.pam"
install -m 755 "$SRC/greeter/nbshell-greeter-session" "$GREETER_DATA/greeter/nbshell-greeter-session"
mkdir -p "$GREETER_DATA/greeter/qml"
install -m 644 \
    "$SRC/greeter/qml/shell.qml" \
    "$SRC/greeter/qml/GreeterView.qml" \
    "$SRC/greeter/qml/OrbitalClock.qml" \
    "$SRC/greeter/qml/ClockMath.js" \
    "$SRC/greeter/qml/qmldir" \
    "$SRC/greeter/qml/preview.json" \
    "$GREETER_DATA/greeter/qml/"

# Desktop metadata for portals and notification attribution. The shell stays
# hidden from application launchers because it is managed as a session unit.
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APP_DIR"
install -m 644 "$SRC/data/dev.nerdi.nbshell.desktop" "$APP_DIR/dev.nerdi.nbshell.desktop"
install -m 644 "$SRC/data/dev.nerdi.nbshell.Calculator.desktop" "$APP_DIR/dev.nerdi.nbshell.Calculator.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
green "Apps    -> $APP_DIR (nbshell and Calculator)"

# ── Agent skill ──────────────────────────────────────────────────────────
# One versioned source, linked into the common Agent Skills locations. The
# universal path covers OpenCode and Gemini too; explicit paths keep native
# skill pickers working in Claude, Codex, and Pi. Only the `nbshell`
# entry is managed, so unrelated user skills remain untouched.
SKILL_SOURCE="$SHELL_DIR/skills/nbshell"
for skill_home in \
    "$HOME/.agents/skills" \
    "$HOME/.claude/skills" \
    "$HOME/.codex/skills" \
    "$HOME/.pi/agent/skills"; do
    mkdir -p "$skill_home"
    ln -sfn "$SKILL_SOURCE" "$skill_home/nbshell"
done
# Gemini discovers the shared path itself. Remove the duplicate native link
# created by nbshell 0.1 development builds, otherwise current Gemini warns
# that the same skill was discovered twice.
GEMINI_SKILL="$HOME/.gemini/skills/nbshell"
if [ -L "$GEMINI_SKILL" ] && [ "$(readlink -f "$GEMINI_SKILL")" = "$(readlink -f "$SKILL_SOURCE")" ]; then
    rm "$GEMINI_SKILL"
fi
green "Skill   -> shared Agent Skills directories (nbshell)"
[ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-payload" ] || exit 102
[ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-payload-kill" ] || kill -KILL "$$"

# The transaction is complete only after every runtime, command, integration,
# and skill payload has landed. Until this point the EXIT trap must still be
# able to restore the previous shell and every backed-up user path.
touch "$TRANSACTION_BACKUP/committed"
install_ready=1
if [ -n "$retired_grid_pid" ]; then
    kill "$retired_grid_pid" 2>/dev/null || true
    rm -f "$STATE_DIR/grid-layout.json" "$STATE_DIR/grid-layout.lock" \
        "$STATE_DIR/grid-layout.pid" "$STATE_DIR/grid-layout-backend"
fi
if [ $defer_service_restart -ne 1 ]; then
    rm -rf -- "$TRANSACTION_BACKUP"
    [ ! -d "$ROLLBACK_SHELL" ] || rm -rf -- "$ROLLBACK_SHELL"
    if [ $recovery_armed -eq 1 ]; then
        systemctl --user stop "$recovery_unit.timer" "$recovery_unit.service" \
            >/dev/null 2>&1 || true
    fi
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH." ;;
esac

# Laeuft nbshell als Dienst, gehoert der Neustart dem Dienst -- sonst steht
# neben der Unit-Instanz eine zweite, von Hand gestartete, und die Leiste ist
# doppelt da.
if [ $unit_active -eq 1 ] && [ $defer_service_restart -ne 1 ]; then
    green "Restarted nbshell.service."
elif [ $defer_service_restart -eq 1 ]; then
    green "Updated nbshell.service runtime (restart deferred)."
elif [ "$was_running" = "1" ]; then
    green "Restarted the shell."
fi

# Ruft setup.sh dieses Skript auf, folgt sein eigener Abspann gleich danach --
# zweimal dasselbe untereinander liest sich wie ein Fehler.
if [ -n "${NBSHELL_FROM_SETUP:-}" ]; then
    exit 0
fi

cat <<'EOF'

Start:
  nbshell start          foreground, logs in the terminal
  nbshell start -d       background

Change the layout:
  nbshell bar            full-width bar
  nbshell island         floating island
  nbshell theme gruvbox

Enable autostart and refresh the Umbriel integration:
  nbshell switch on
  nbshell switch status

An old DankMaterialShell installation is only stopped as a migration aid.
nbshell does not require DMS.
EOF
