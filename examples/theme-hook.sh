#!/usr/bin/env bash
#
# Beispiel fuer ~/.config/nbshell/theme-hook.sh
#
# nbshell ruft dieses Skript nach jedem Themewechsel auf, mit Themename und
# Modus als Argumenten:
#
#   theme-hook.sh tokyo-night dark
#
# Die Farben muss es sich nicht selbst zusammensuchen: nbshell schreibt sie
# vorher nach ~/.config/nbshell/palette.sh, in einer Form, die eine Shell
# direkt einliest. Dort sind beide Dialekte von Omarchys colors.toml schon
# aufgeloest (benannte Schluessel UND color0…color15) -- ein Hook, der die
# colors.toml selbst liest, muesste das jedes Mal nachbauen.
#
# Installieren:
#   cp examples/theme-hook.sh ~/.config/nbshell/theme-hook.sh
#   chmod +x ~/.config/nbshell/theme-hook.sh
#
# Und wieder loswerden: die Datei loeschen. Ohne sie passiert nichts.
#
# Jeder Block prueft selbst, ob sein Programm ueberhaupt da ist. Absichtlich
# KEIN `set -e`: ein Programm, das fehlt oder sich beschwert, soll die
# uebrigen nicht mitnehmen.
set -uo pipefail

PALETTE="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/palette.sh"
[ -r "$PALETTE" ] || exit 0
# shellcheck source=/dev/null
. "$PALETTE"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

# ── alacritty ────────────────────────────────────────────────────────────
#
# Alacritty beobachtet seine Dateien selbst -- geschrieben ist gesehen, ohne
# Signal und ohne Neustart. Geschrieben wird eine EIGENE Datei, nicht die
# alacritty.toml: die gehoert dir. Damit sie gelesen wird, muss in der
# alacritty.toml einmal stehen:
#
#   [general]
#   import = ["~/.config/alacritty/nb-theme.toml"]
if [ -d "$CONFIG/alacritty" ]; then
	cat >"$CONFIG/alacritty/nb-theme.toml" <<EOF
# Von theme-hook.sh geschrieben -- Theme: $NB_THEME
[colors.primary]
background = '$NB_BG'
foreground = '$NB_FG'

[colors.cursor]
text = '$NB_BG'
cursor = '$NB_ACCENT'

[colors.selection]
text = '$NB_FG_BRIGHT'
background = '$NB_SELECTION'

[colors.normal]
black = '$NB_BLACK'
red = '$NB_RED'
green = '$NB_GREEN'
yellow = '$NB_YELLOW'
blue = '$NB_BLUE'
magenta = '$NB_MAGENTA'
cyan = '$NB_CYAN'
white = '$NB_WHITE'

[colors.bright]
black = '$NB_BRIGHT_BLACK'
red = '$NB_BRIGHT_RED'
green = '$NB_BRIGHT_GREEN'
yellow = '$NB_BRIGHT_YELLOW'
blue = '$NB_BRIGHT_BLUE'
magenta = '$NB_BRIGHT_MAGENTA'
cyan = '$NB_BRIGHT_CYAN'
white = '$NB_BRIGHT_WHITE'
EOF
fi

# ── cava ─────────────────────────────────────────────────────────────────
#
# cava mischt seine Config mit den Vorgaben, eine Datei mit nur [color] genuegt
# also. Der Farbverlauf laeuft von gedaempft zum Akzent -- ein einfarbiger
# Balken sieht in einem Terminalthema tot aus.
if command -v cava >/dev/null 2>&1; then
	mkdir -p "$CONFIG/cava"
	cat >"$CONFIG/cava/config" <<EOF
# Von theme-hook.sh geschrieben -- Theme: $NB_THEME
[color]
background = '$NB_BG'
foreground = '$NB_ACCENT'
gradient = 1
gradient_count = 4
gradient_color_1 = '$NB_MUTED'
gradient_color_2 = '$NB_ACCENT'
gradient_color_3 = '$NB_CYAN'
gradient_color_4 = '$NB_BRIGHT_WHITE'
EOF
	# cava liest die Config beim Start; laeuft es gerade, bittet SIGUSR1 es
	# zum Nachladen.
	pkill -USR1 -x cava 2>/dev/null
fi

# ── GTK ──────────────────────────────────────────────────────────────────
#
# Die Widgetfarben eines GTK-Themes aus einer Palette zu erzeugen ist ein
# eigenes Projekt. Was sofort wirkt und den groessten Teil ausmacht, ist die
# Hell/Dunkel-Vorliebe: daran haengen GTK4-Programme, Nautilus, die Portale
# und damit auch die Dateiauswahl in Browsern.
if command -v gsettings >/dev/null 2>&1; then
	if [ "$NB_MODE" = "light" ]; then
		gsettings set org.gnome.desktop.interface color-scheme prefer-light
	else
		gsettings set org.gnome.desktop.interface color-scheme prefer-dark
	fi
fi

# ── bat ──────────────────────────────────────────────────────────────────
#
# bat braucht ein .tmTheme, keine Palette -- eines je Omarchy-Theme zu bauen
# waere viel Arbeit fuer wenig. `ansi` ist der kuerzere Weg: bat nimmt dann
# die Farben des Terminals, und die faerbt nbshell ohnehin mit. Deshalb wird
# das nur EINMAL eingetragen und danach nicht mehr angefasst.
if command -v bat >/dev/null 2>&1 && [ ! -e "$CONFIG/bat/config" ]; then
	mkdir -p "$CONFIG/bat"
	printf -- '--theme=ansi\n' >"$CONFIG/bat/config"
fi

# ── Was hier NICHT hingehoert ────────────────────────────────────────────
#
#   ghostty, niri   macht nbshell selbst (Services/ThemeExport.qml)
#   nvim            ein Colorscheme ist ein Plugin, keine Palette. Wer will,
#                   waehlt hier per `sed` ein anderes in seiner LazyVim-Config
#                   und ruft `nvim --server … --remote-send` -- das ist aber
#                   Geschmackssache und keine Farbzuweisung.
#   Browser         Zen und Brave folgen der GTK-Hell/Dunkel-Vorliebe oben,
#                   mehr geht ohne Erweiterung nicht.
exit 0
