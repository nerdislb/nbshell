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
was_running=0
if "$QS_BIN" list --all 2>/dev/null | grep -c "quickshell/nbshell/shell.qml" >/dev/null; then
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

# ── Befehl ───────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/nbshell" "$BIN_DIR/nbshell"
green "Befehl  -> $BIN_DIR/nbshell"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR liegt nicht im PATH." ;;
esac

if [ "$was_running" = "1" ]; then
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
