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
    warn "Fehlt: ${missing[*]}"
    echo "  sudo pacman -S ${missing[*]}"
    echo
fi

# `grep -c` statt `grep -q`: -q steigt beim ersten Treffer aus, das schickt
# fc-list ein SIGPIPE -- und unter `set -o pipefail` gilt die ganze Kette dann
# als gescheitert, obwohl die Schrift da ist.
fc-list 2>/dev/null | grep -ci "Inconsolata.*Nerd Font" >/dev/null || \
    warn "Hinweis: 'Inconsolata Nerd Font Mono' nicht gefunden — Vorgabeschrift der Config. Paket: ttf-inconsolata-nerd"

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

mkdir -p "$SHELL_DIR"
rm -rf "${SHELL_DIR:?}"/*
cp -a "$SRC/shell/." "$SHELL_DIR/"
green "Shell   -> $SHELL_DIR"

# ── Themes ───────────────────────────────────────────────────────────────
# Die Farbdateien sind dieselben wie in omarchy2dms. Vorhandene werden
# ueberschrieben, eigene daneben bleiben stehen.
mkdir -p "$DATA_DIR/themes"
cp -a "$SRC/themes/." "$DATA_DIR/themes/"
green "Themes  -> $DATA_DIR/themes ($(find "$DATA_DIR/themes" -name colors.toml | wc -l) Stueck)"

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
  "leftWidgets": ["workspaces", "sep", "window"],
  "centerWidgets": ["clock"],
  "rightWidgets": ["sys", "sep", "layout", "battery"]
}
JSON
    green "Config  -> $DATA_DIR/config.json (neu angelegt)"
else
    echo "Config  -> $DATA_DIR/config.json (vorhanden, unangetastet)"
fi

# ── systemd-Unit ─────────────────────────────────────────────────────────
# Nur ablegen, nicht einschalten -- das macht `nbshell switch on`. Vorher
# startet man von Hand (`nbshell start -d`), damit DMS ungestoert bleibt.
UNIT_DIR="$CONFIG_HOME/systemd/user"
mkdir -p "$UNIT_DIR"
install -m 644 "$SRC/systemd/nbshell.service" "$UNIT_DIR/nbshell.service"
systemctl --user daemon-reload 2>/dev/null || true
green "Unit    -> $UNIT_DIR/nbshell.service (noch nicht eingeschaltet)"

# ── niri-Tastenkuerzel fuer den Umstieg ──────────────────────────────────
# Nur ablegen, nicht einbinden -- das macht `nbshell switch on`.
if [ -d "$CONFIG_HOME/niri" ]; then
    install -m 644 "$SRC/niri/nbshell-takeover.kdl" "$CONFIG_HOME/niri/nbshell-takeover.kdl"
    green "Binds   -> $CONFIG_HOME/niri/nbshell-takeover.kdl (noch nicht eingebunden)"
fi

# ── Befehl ───────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/nbshell" "$BIN_DIR/nbshell"
green "Befehl  -> $BIN_DIR/nbshell"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR liegt nicht im PATH." ;;
esac

# Laeuft nbshell als Dienst, gehoert der Neustart dem Dienst -- sonst steht
# neben der Unit-Instanz eine zweite, von Hand gestartete, und die Leiste ist
# doppelt da.
if [ $unit_active -eq 1 ]; then
    systemctl --user start nbshell.service
    green "Dienst nbshell.service wieder gestartet."
elif [ "$was_running" = "1" ]; then
    "$BIN_DIR/nbshell" start -d >/dev/null 2>&1 &
    green "Shell wieder gestartet."
fi

cat <<'EOF'

Starten:
  nbshell start          im Vordergrund, Meldungen im Terminal
  nbshell start -d       im Hintergrund

Umschalten:
  nbshell bar            durchgehender Balken
  nbshell island         freistehende Insel
  nbshell theme gruvbox

Tastenkuerzel fuer niri (~/.config/niri/config.kdl):
  Mod+Shift+I hotkey-overlay-title="nbshell: Insel/Balken" {
      spawn "nbshell" "mode" "toggle";
  }

DMS bleibt unangetastet und laeuft weiter. Beide gleichzeitig ergeben zwei
Leisten -- zum Vergleichen praktisch, im Alltag schaltet man eine davon ab.
EOF
