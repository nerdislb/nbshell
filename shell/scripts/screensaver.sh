#!/usr/bin/env bash
#
# Bildschirmschoner starten -- bevorzugt mit ttfx, sonst TTE oder dem eigenen.
#
# `ttfx` is the Rust port of TerminalTextEffects used by current Omarchy. It
# preserves all 37 effects while avoiding Python startup and rendering cost.
# Version 0.3.1 could abort when its terminal disappeared, so nbshell only
# accepts 0.3.2 or newer. The Python original remains a compatible fallback:
#
#   ttfx >= 0.3.2 -> tte -> scripts/screensaver.py
#
# Die Aufrufwerte folgen dem Upstream-CLI, Flagge fuer
# Flagge -- sie machen den Eindruck aus:
#
#   --frame-rate 120           fluessig statt ruckelig
#   --canvas-width/-height 0   die Leinwand ist der ganze Schirm, nicht der
#                              Kasten um den Text
#   --reuse-canvas             kein Schwarzblitz zwischen zwei Effekten
#   --anchor-canvas/-text c    mittig
#   --random-effect            jede Runde ein anderer
#
# Nicht jede Fassung kennt jede Flagge -- deshalb wird `--help` gefragt und nur
# weitergegeben, was dort auftaucht. Eine unbekannte Flagge waere ein sofortiger
# Abbruch und ein schwarzer Schirm.
set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EIGEN="$HIER/screensaver.py"
VORLAGE="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/screensaver.txt"

version_ge() {
	[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

renderer=""
if command -v ttfx >/dev/null 2>&1; then
	ttfx_version="$(ttfx --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
	if [ -n "$ttfx_version" ] && version_ge "$ttfx_version" "0.3.2"; then
		renderer="ttfx"
	fi
fi
[ -n "$renderer" ] || ! command -v tte >/dev/null 2>&1 || renderer="tte"

# Stable diagnostic hook used by setup checks and tests. It must not create a
# branding file or open a terminal.
if [ "${1:-}" = "--renderer" ]; then
	printf '%s\n' "${renderer:-internal}"
	exit 0
fi

# Eigene Vorlage schlaegt die eingebaute -- so kann man den Schriftzug
# austauschen, ohne das Skript anzufassen (wie Omarchys branding-Datei).
if [ ! -s "$VORLAGE" ]; then
	mkdir -p "$(dirname "$VORLAGE")"
	python3 "$EIGEN" --wortmarke >"$VORLAGE" 2>/dev/null || true
fi

if [ -z "$renderer" ]; then
	exec python3 "$EIGEN"
fi

hilfe="$($renderer --help 2>&1 || true)"
flags=()
kennt() { printf '%s' "$hilfe" | grep -q -- "$1"; }

kennt --frame-rate && flags+=(--frame-rate 120)
kennt --canvas-width && flags+=(--canvas-width 0)
kennt --canvas-height && flags+=(--canvas-height 0)
kennt --anchor-canvas && flags+=(--anchor-canvas c)
kennt --anchor-text && flags+=(--anchor-text c)
kennt --reuse-canvas && flags+=(--reuse-canvas)
kennt --no-eol && flags+=(--no-eol)
kennt --no-restore-cursor && flags+=(--no-restore-cursor)

printf '\033]0;nbshell-screensaver\007'
printf '\033[?25l'

aufraeumen() {
	# Only stop the renderer owned by this screen-saver instance. A broad
	# `pkill -x ttfx` would also terminate an unrelated effect in a terminal.
	[ -z "${kind:-}" ] || kill "$kind" 2>/dev/null
	printf '\033[?25h\033[0m\033[2J\033[H'
	exit 0
}
trap aufraeumen INT TERM HUP

# Wie bei Omarchy: eine Runde Effekt, danach die naechste -- und waehrend sie
# laeuft wird auf eine Taste gehorcht. `read -t 1` ist die Uhr dafuer.
while true; do
	if printf '%s' "$hilfe" | grep -q -- '--random-effect'; then
		"$renderer" -i "$VORLAGE" "${flags[@]}" --random-effect &
	else
		# Aeltere Fassungen kennen keinen Zufall: dann wird selbst gewuerfelt.
		effekte=(beams binarypath blackhole bouncyballs bubbles burn colorshift
			crumble decrypt errorcorrect expand fireworks middleout
			orbittingvolley overflow pour print rain randomsequence rings
			scattered slice slide spotlights spray swarm sweep synthgrid
			unstable vhstape waves wipe)
		"$renderer" -i "$VORLAGE" "${flags[@]}" "${effekte[RANDOM % ${#effekte[@]}]}" &
	fi
	kind=$!

	while kill -0 "$kind" 2>/dev/null; do
		if read -rsn1 -t 1; then
			kill "$kind" 2>/dev/null
			aufraeumen
		fi
	done
	wait "$kind" 2>/dev/null

	# Der Renderer laesst den Cursor stehen (wir bitten ihn mit --no-restore-cursor
	# ausdruecklich darum, ihn nicht anzufassen) -- unter dem Schriftzug blinkt
	# dann ein Strich. Nach jeder Runde wieder wegnehmen.
	printf '\033[?25l' 

	# Kurz stehen lassen, sonst hetzt ein Effekt den naechsten.
	if read -rsn1 -t 4; then
		aufraeumen
	fi
done
