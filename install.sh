#!/usr/bin/env bash
# Installiert nbshell.
#
# Ziel ist der eine Befehl auf einem nackten Arch mit niri. Was fehlt, wird
# gemeldet statt heimlich nachinstalliert -- Pakete gehoeren in die Hand des
# Benutzers.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_DIR="$CONFIG_HOME/quickshell/nbshell"   # von `qs -c nbshell` gesucht
DATA_DIR="$CONFIG_HOME/nbshell"               # Config und Themes
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

QS_BIN="$(command -v qs || command -v quickshell || true)"

green() { printf '\033[32m%s\033[0m\n' "$1"; }
warn()  { printf '\033[33m%s\033[0m\n' "$1"; }

# ── Voraussetzungen ──────────────────────────────────────────────────────
missing=()
command -v quickshell >/dev/null 2>&1 || command -v qs >/dev/null 2>&1 || missing+=("quickshell")
command -v niri >/dev/null 2>&1 || missing+=("niri")

if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing: ${missing[*]}"
    echo "  sudo pacman -S ${missing[*]}"
    echo
fi

# `grep -c` statt `grep -q`: -q steigt beim ersten Treffer aus, das schickt
# fc-list ein SIGPIPE -- und unter `set -o pipefail` gilt die ganze Kette dann
# als gescheitert, obwohl die Schrift da ist.
fc-list 2>/dev/null | grep -ci "Inconsolata.*Nerd Font" >/dev/null || \
    warn "Note: 'Inconsolata Nerd Font Mono' was not found. Install: ttf-inconsolata-nerd"

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
    optional_check hyprlock      "screen locking"             "hyprlock"
    optional_check fakeroot      "update checks"              "fakeroot"
    optional_check paru          "AUR updates"                "paru or yay"
    optional_check tuned-adm     "power profiles"             "tuned"
    optional_check notify-send   "script notifications"       "libnotify"
    optional_check git           "installing themes"          "git"
    optional_check khal          "calendar"                   "khal"
    optional_check curl          "weather plugin"             "curl"
    optional_check vdirsyncer    "calendar sync"              "vdirsyncer"
    optional_check wf-recorder   "screen recording"           "wf-recorder"
    optional_check slurp         "region selection"           "slurp"
    optional_check satty         "screenshot editing"         "satty"
    optional_check tesseract     "OCR"                        "tesseract tesseract-data-eng"
    optional_check swappy        "screenshot editing"         "swappy"
    optional_check checkupdates  "fast update checks"         "pacman-contrib"
    optional_check jq            "helper scripts"             "jq"
    optional_check syncthing     "task sync"                  "syncthing"
    optional_check headsetcontrol "headset battery"           "headsetcontrol"
    optional_check qrencode      "Wi-Fi QR codes"             "qrencode"
    optional_check speedtest-cli "network speed tests"        "speedtest-cli"
    optional_check magick        "transparent-bar contrast"   "imagemagick"
    optional_check node          "WhatsApp bar module"        "nodejs (>= 20)"
    optional_check npm           "WhatsApp bridge setup"      "npm"
    optional_check tte           "additional screen-saver effects" "python-terminaltexteffects (AUR)"
    optional_check sqlite3       "finding Antigravity accounts" "sqlite"
    optional_check secret-tool   "reading the Antigravity keyring" "libsecret"
    optional_check adb           "Android connection"         "android-tools"
    optional_check scrcpy        "Android mirroring"          "scrcpy"
    optional_check nbphone       "phone mirror control"       "github.com/nerdislb/nbphone"
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
# Laeuft eine Instanz, wird sie vorher beendet: waehrend des Kopierens ist das
# Verzeichnis kurz unvollstaendig, und Quickshell laedt bei jeder Aenderung neu
# -- es wuerde also mitten im Austausch eine halbe Shell lesen und aufgeben.
# Reihenfolge zaehlt: laeuft nbshell als Dienst, gehoert ihm das Anhalten und
# das Starten. Wer stattdessen die Instanz killt, bringt die Unit auf
# "inactive" -- und danach steht eine von Hand gestartete Kopie daneben.
unit_active=0
systemctl --user is-active --quiet nbshell.service 2>/dev/null && unit_active=1

was_running=0
if [ $unit_active -eq 1 ]; then
    systemctl --user stop nbshell.service
elif "$QS_BIN" list --all 2>/dev/null | grep -c "quickshell/nbshell/shell.qml" >/dev/null; then
    was_running=1
    "${SRC}/bin/nbshell" stop >/dev/null 2>&1 || true
    sleep 0.3
fi

# Ab hier laeuft keine Leiste mehr. Endet das Skript vor dem regulaeren
# Neustart -- durch einen Fehler unter `set -e`, durch Strg-C oder durch ein
# SIGPIPE, weil jemand die Ausgabe nach `head` geschickt hat --, dann steht
# der Benutzer ohne Leiste da und sucht den Grund woanders. Der EXIT-Trap holt
# sie in jedem dieser Faelle zurueck; nach einem sauberen Durchlauf hat der
# Abschnitt unten sie schon gestartet, und dann ist er wirkungslos.
zurueckholen() {
    if [ $unit_active -eq 1 ]; then
        systemctl --user is-active --quiet nbshell.service 2>/dev/null || \
            systemctl --user start nbshell.service 2>/dev/null || true
    fi
}
trap zurueckholen EXIT

mkdir -p "$SHELL_DIR"
rm -rf "${SHELL_DIR:?}"/*
cp -a "$SRC/shell/." "$SHELL_DIR/"
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
if [ -d "$OLD_WALLPAPERS" ]; then
    mkdir -p "$NEW_WALLPAPERS"
    cp -an "$OLD_WALLPAPERS/." "$NEW_WALLPAPERS/"
    green "Images  -> $NEW_WALLPAPERS (migrated from the old location)"
fi

# ── Config ───────────────────────────────────────────────────────────────
# Nur anlegen, nie ueberschreiben: sie gehoert dem Benutzer.
if [ ! -f "$DATA_DIR/config.json" ]; then
    cat > "$DATA_DIR/config.json" <<'JSON'
{
  "theme": "tokyo-night",
  "mode": "island",
  "edge": "top",
  "font": "Inconsolata Nerd Font Mono",
  "fontSize": 13,
  "gap": 6,
  "radius": 0,
  "borderWidth": 1,
  "opacity": 1.0,
  "widgetStyle": "box",
  "collapsedWidgets": ["clock"],
  "leftWidgets": ["workspaces", "whatsapp", "sep", "window"],
  "centerWidgets": ["clock"],
  "rightWidgets": ["sys", "sep", "layout", "battery"]
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
    [ -d "$DATA_DIR/plugins/$name" ] && continue
    cp -a "$plugin" "$DATA_DIR/plugins/"
    added+=("$name")
done
if [ ${#added[@]} -gt 0 ]; then
    green "Plugins -> $DATA_DIR/plugins (added: ${added[*]})"
else
    echo "Plugins -> $DATA_DIR/plugins ($(find "$DATA_DIR/plugins" -maxdepth 2 -name manifest.json 2>/dev/null | wc -l) installed, existing files kept)"
fi

# ── systemd-Unit ─────────────────────────────────────────────────────────
# Nur ablegen, nicht einschalten -- das macht `nbshell switch on`.
UNIT_DIR="$CONFIG_HOME/systemd/user"
mkdir -p "$UNIT_DIR"
install -m 644 "$SRC/systemd/nbshell.service" "$UNIT_DIR/nbshell.service"
systemctl --user daemon-reload 2>/dev/null || true
green "Unit    -> $UNIT_DIR/nbshell.service (not enabled yet)"

# ── niri-Tastenkuerzel ───────────────────────────────────────────────────
mkdir -p "$CONFIG_HOME/niri"
install -m 644 "$SRC/niri/nbshell-takeover.kdl" "$CONFIG_HOME/niri/nbshell-takeover.kdl"
if [ ! -f "$CONFIG_HOME/niri/config.kdl" ]; then
    printf '// Standalone niri configuration created by nbshell\ninclude "nbshell-takeover.kdl"\n' > "$CONFIG_HOME/niri/config.kdl"
    green "Niri    -> $CONFIG_HOME/niri/config.kdl (created)"
fi
green "Binds   -> $CONFIG_HOME/niri/nbshell-takeover.kdl"

# ── Befehl ───────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/nbshell" "$BIN_DIR/nbshell"
green "Command -> $BIN_DIR/nbshell"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH." ;;
esac

# Laeuft nbshell als Dienst, gehoert der Neustart dem Dienst -- sonst steht
# neben der Unit-Instanz eine zweite, von Hand gestartete, und die Leiste ist
# doppelt da.
if [ $unit_active -eq 1 ]; then
    systemctl --user start nbshell.service
    green "Restarted nbshell.service."
elif [ "$was_running" = "1" ]; then
    "$BIN_DIR/nbshell" start -d >/dev/null 2>&1 &
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

Enable autostart and niri integration:
  nbshell switch on
  nbshell switch status

An old DankMaterialShell installation is only stopped as a migration aid.
nbshell does not require DMS.
EOF
