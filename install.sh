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

QS_BIN="$(command -v qs || command -v quickshell || true)"

green() { printf '\033[32m%s\033[0m\n' "$1"; }
warn()  { printf '\033[33m%s\033[0m\n' "$1"; }

# Serialize installs started by terminals, the dashboard, or agent sessions.
mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/install.lock"
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
    optional_check qrencode      "Wi-Fi QR codes"             "qrencode"
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

# ── Shell ────────────────────────────────────────────────────────────────
# Install the shell lifecycle unit before touching the running shell.
mkdir -p "$UNIT_DIR"
install -m 644 "$SRC/systemd/nbshell.service" "$UNIT_DIR/nbshell.service"
install -m 644 "$SRC/systemd/nbshell-lock.service" "$UNIT_DIR/nbshell-lock.service"
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
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable nbshell-umbriel-resume-guard.service >/dev/null 2>&1 || true
systemctl --user enable --now nbshell-upstream-audit.timer >/dev/null 2>&1 || true

unit_active=0
defer_service_restart=0
install_ready=0
rollback_is_runtime() {
    [ -d "$ROLLBACK_SHELL" ] && [ -f "$ROLLBACK_SHELL/shell.qml" ]
}
recover_install() {
    result=$?
    if [ $install_ready -ne 1 ] && rollback_is_runtime; then
        if [ $defer_service_restart -ne 1 ]; then
            systemctl --user stop nbshell.service >/dev/null 2>&1 || true
        fi
        rm -rf -- "${SHELL_DIR:?}"
        mv -T -- "$ROLLBACK_SHELL" "$SHELL_DIR"
    fi
    [ ! -d "$STAGED_SHELL" ] || rm -rf -- "$STAGED_SHELL"
    if [ -d "$ROLLBACK_SHELL" ] && ! rollback_is_runtime; then
        rm -rf -- "$ROLLBACK_SHELL"
    fi
    if [ $unit_active -eq 1 ] && [ $defer_service_restart -ne 1 ]; then
        systemctl --user is-active --quiet nbshell.service 2>/dev/null || \
            systemctl --user start nbshell.service >/dev/null 2>&1 || true
    fi
    return "$result"
}

# Prepare and validate a complete runtime before stopping the bar. Both names
# are private, same-filesystem reservations. A rollback is genuine only after
# the old, validated runtime has occupied its reservation.
mkdir -p "$CONFIG_HOME/quickshell"
STAGED_SHELL="$(mktemp -d "$CONFIG_HOME/quickshell/.nbshell-stage.XXXXXX")"
if ! ROLLBACK_SHELL="$(mktemp -d "$CONFIG_HOME/quickshell/.nbshell-rollback.XXXXXX")"; then
    rm -rf -- "$STAGED_SHELL"
    exit 1
fi
# Arm cleanup immediately after both reservations, before copy, validation, or
# recovery arming can fail.
trap recover_install EXIT

cp -a "$SRC/shell/." "$STAGED_SHELL/"
cp -a "$SRC/integrations" "$STAGED_SHELL/"
install -m 644 "$SRC/VERSION" "$STAGED_SHELL/VERSION"
bash -n "$SRC/install.sh"
bash -n "$SRC/bin/nbshell" "$SRC/bin/nbshell-install-recover"
while IFS= read -r -d '' script; do bash -n "$script"; done < <(find "$SRC/shell/scripts" -type f -name '*.sh' -print0)
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
    "$STAGED_SHELL/scripts/agents.py"
QMLLINT_BIN="$(command -v qmllint || true)"
[ -n "$QMLLINT_BIN" ] || [ ! -x /usr/lib/qt6/bin/qmllint ] || QMLLINT_BIN=/usr/lib/qt6/bin/qmllint
if [ -n "$QMLLINT_BIN" ]; then
    "$QMLLINT_BIN" "$STAGED_SHELL/shell.qml" >/dev/null 2>&1
fi
[ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "pre-swap" ] || exit 97

systemctl --user is-active --quiet nbshell.service 2>/dev/null && unit_active=1
was_running=0
if [ $unit_active -ne 1 ] && "$QS_BIN" list --all 2>/dev/null | grep -c "quickshell/nbshell/shell.qml" >/dev/null; then
    was_running=1
fi

# Agent terminals opened by nbshell are members of nbshell.service. Stopping
# that unit here would also terminate the installer and its controlling agent.
# The runtime directory can still be switched atomically; in that case leave
# the already running shell untouched and let the next login/restart load it.
restart_policy="${NBSHELL_INSTALL_DEFER_RESTART:-auto}"
if [ $unit_active -eq 1 ] && { [ "$restart_policy" = "1" ] \
        || { [ "$restart_policy" = "auto" ] \
            && grep -Fq '/nbshell.service' /proc/$$/cgroup 2>/dev/null; }; }; then
    defer_service_restart=1
fi

# This timer belongs to the user manager, not to the calling terminal. Even a
# killed installer cannot leave a previously running desktop without its bar.
recovery_armed=0
if [ $unit_active -eq 1 ]; then
    systemctl --user stop nbshell-install-recovery.timer nbshell-install-recovery.service >/dev/null 2>&1 || true
    systemctl --user reset-failed nbshell-install-recovery.service >/dev/null 2>&1 || true
    recovery_mode=restart
    [ $defer_service_restart -ne 1 ] || recovery_mode=deferred
    if systemd-run --user --quiet --unit=nbshell-install-recovery --on-active=20s \
            --timer-property=AccuracySec=1s "$BIN_DIR/nbshell-install-recover" \
            "$SHELL_DIR" "$ROLLBACK_SHELL" "$recovery_mode"; then
        recovery_armed=1
    fi
fi

if [ $unit_active -eq 1 ] && [ $defer_service_restart -ne 1 ]; then
    systemctl --user stop nbshell.service
elif [ "$was_running" = "1" ]; then
    "${SRC}/bin/nbshell" stop >/dev/null 2>&1 || true
    sleep 0.3
fi
if [ -d "$SHELL_DIR" ]; then
    # mv cannot replace the reserved directory itself. Removing that empty
    # inode is safe: the unpredictable name remains ours and installs are
    # serialized. Cleanup validates the moved contents, not a flag.
    rmdir -- "$ROLLBACK_SHELL"
    mv -T -- "$SHELL_DIR" "$ROLLBACK_SHELL"
    [ "${NBSHELL_INSTALL_TEST_FAULT:-}" != "post-first-rename" ] || exit 98
fi
mv -T -- "$STAGED_SHELL" "$SHELL_DIR"

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
install_ready=1
if [ -d "$ROLLBACK_SHELL" ] && [ $defer_service_restart -ne 1 ]; then
    rm -rf -- "$ROLLBACK_SHELL"
fi
if [ $recovery_armed -eq 1 ] && [ $defer_service_restart -ne 1 ]; then
    systemctl --user stop nbshell-install-recovery.timer >/dev/null 2>&1 || true
fi
if [ -n "${UMBRIEL_SOCKET:-}" ]; then
    systemctl --user restart nbshell-umbriel-resume-guard.service >/dev/null 2>&1 || true
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
    cat > "$DATA_DIR/config.json" <<'JSON'
{
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

# ── Plugins ──────────────────────────────────────────────────────────────
# Nur das Verzeichnis anlegen und die Vorlage hineinlegen, falls sie fehlt.
# Was hier drin liegt, gehoert dem Benutzer -- es wird nie ueberschrieben.
mkdir -p "$DATA_DIR/plugins"
added=()
for plugin in "$SRC"/plugins/*/; do
    [ -d "$plugin" ] || continue
    name="$(basename "$plugin")"
    if [ -f "$plugin/.nbshell-managed" ] && [ -f "$DATA_DIR/plugins/$name/.nbshell-managed" ]; then
        rm -rf "$DATA_DIR/plugins/$name"
        cp -a "$plugin" "$DATA_DIR/plugins/"
        added+=("$name updated")
        continue
    fi
    [ -d "$DATA_DIR/plugins/$name" ] && continue
    cp -a "$plugin" "$DATA_DIR/plugins/"
    added+=("$name")
done
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
    install -m 644 -- "$DATA_DIR/plugins/ytmusic/backend/"*.py "$YTMUSIC_RUNTIME/"
    chmod 755 -- "$YTMUSIC_RUNTIME/server.py"
    "$YTMUSIC_VENV" "$YTMUSIC_RUNTIME/server.py" --self-test >/dev/null
    if systemctl --user is-active --quiet omarchy-ytmusic.service 2>/dev/null; then
        systemctl --user restart omarchy-ytmusic.service
    fi
    green "YT Music -> refreshed installed backend"
fi

# ── systemd-Unit ─────────────────────────────────────────────────────────
# The shell lifecycle remains opt-in via `nbshell switch on`; the narrow
# Umbriel recovery guard is enabled independently above.
green "Units   -> $UNIT_DIR (shell lifecycle, isolated locker, and Umbriel resume guard)"

# Umbriel is the supported compositor. Installing its include does not alter
# unrelated user configuration.
mkdir -p "$CONFIG_HOME/umbriel"
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
if [ -f "$STATE_DIR/grid-layout.pid" ]; then
    grid_pid="$(cat "$STATE_DIR/grid-layout.pid" 2>/dev/null || true)"
    if [[ $grid_pid =~ ^[0-9]+$ ]] && tr '\0' ' ' <"/proc/$grid_pid/cmdline" 2>/dev/null | grep -Fq 'grid-layout.py watch'; then
        kill "$grid_pid" 2>/dev/null || true
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
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/nbshell" "$BIN_DIR/nbshell"
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
