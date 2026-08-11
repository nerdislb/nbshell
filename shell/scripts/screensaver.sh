#!/usr/bin/env bash
#
# Bildschirmschoner starten -- mit TTE, wenn es da ist, sonst mit dem eigenen.
#
# TerminalTextEffects (`tte`) ist das Programm, das auch Omarchy benutzt (dort
# als Fork `ttfx`). Es bringt 39 Effekte mit; unser eigenes Skript hat zehn.
# Die 39 nachzubauen waere Wochen Arbeit und am Ende doch nur die Imitation --
# also wird das Original genommen, wenn es installiert ist:
#
#   paru -S python-terminaltexteffects
#
# Ohne das Paket faellt der Schoner auf scripts/screensaver.py zurueck. Nichts
# bricht, es sind eben zehn statt 39.
#
# Die Aufrufwerte sind die von Omarchy (bin/omarchy-screensaver), Flagge fuer
# Flagge -- sie machen den Eindruck aus:
#
#   --frame-rate 120           fluessig statt ruckelig
#   --canvas-width/-height 0   die Leinwand ist der ganze Schirm, nicht der
#                              Kasten um den Text
#   --reuse-canvas             kein Schwarzblitz zwischen zwei Effekten
#   --anchor-canvas/-text c    mittig
#   --random-effect            jede Runde ein anderer
#
# Nicht jede Fassung von tte kennt jede Flagge -- deshalb wird `tte --help`
# gefragt und nur weitergegeben, was dort auftaucht. Eine unbekannte Flagge
# waere ein sofortiger Abbruch und ein schwarzer Schirm.
set -uo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EIGEN="$HIER/screensaver.py"
VORLAGE="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/screensaver.txt"

# Eigene Vorlage schlaegt die eingebaute -- so kann man den Schriftzug
# austauschen, ohne das Skript anzufassen (wie Omarchys branding-Datei).
if [ ! -s "$VORLAGE" ]; then
	mkdir -p "$(dirname "$VORLAGE")"
	python3 "$EIGEN" --wortmarke >"$VORLAGE" 2>/dev/null || true
fi

if ! command -v tte >/dev/null 2>&1; then
	exec python3 "$EIGEN"
fi

hilfe="$(tte --help 2>&1 || true)"
flags=()
kennt() { printf '%s' "$hilfe" | grep -q -- "$1"; }

kennt --frame-rate && flags+=(--frame-rate 120)
kennt --canvas-width && flags+=(--canvas-width 0)
kennt --canvas-height && flags+=(--canvas-height 0)
kennt --anchor-canvas && flags+=(--anchor-canvas c)
kennt --anchor-text && flags+=(--anchor-text c)
kennt --no-eol && flags+=(--no-eol)
kennt --no-restore-cursor && flags+=(--no-restore-cursor)

printf '\033]0;nbshell-screensaver\007'
printf '\033[?25l'

aufraeumen() {
	pkill -x tte 2>/dev/null
	printf '\033[?25h\033[0m\033[2J\033[H'
	exit 0
}
trap aufraeumen INT TERM HUP

# Wie bei Omarchy: eine Runde Effekt, danach die naechste -- und waehrend sie
# laeuft wird auf eine Taste gehorcht. `read -t 1` ist die Uhr dafuer.
while true; do
	if printf '%s' "$hilfe" | grep -q -- '--random-effect'; then
		tte "${flags[@]}" --random-effect <"$VORLAGE" &
	else
		# Aeltere Fassungen kennen keinen Zufall: dann wird selbst gewuerfelt.
		effekte=(beams binarypath blackhole bouncyballs bubbles burn colorshift
			crumble decrypt errorcorrect expand fireworks middleout
			orbittingvolley overflow pour print rain randomsequence rings
			scattered slice slide spotlights spray swarm sweep synthgrid
			unstable vhstape waves wipe)
		tte "${flags[@]}" "${effekte[RANDOM % ${#effekte[@]}]}" <"$VORLAGE" &
	fi
	kind=$!

	while kill -0 "$kind" 2>/dev/null; do
		if read -rsn1 -t 1; then
			kill "$kind" 2>/dev/null
			aufraeumen
		fi
	done
	wait "$kind" 2>/dev/null

	# tte laesst den Cursor stehen (wir bitten es mit --no-restore-cursor
	# ausdruecklich darum, ihn nicht anzufassen) -- unter dem Schriftzug blinkt
	# dann ein Strich. Nach jeder Runde wieder wegnehmen.
	printf '\033[?25l' 

	# Kurz stehen lassen, sonst hetzt ein Effekt den naechsten.
	if read -rsn1 -t 4; then
		aufraeumen
	fi
done
