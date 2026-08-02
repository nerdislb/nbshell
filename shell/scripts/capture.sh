#!/usr/bin/env bash
#
# Helfer fuer das DMS-Widget "Screen Capture".
#
# Die Aufnahme selbst macht das Widget: es schickt niri per IPC eine
# Screenshot-Aktion mit einem festen Pfad. Alles, was danach kommt --
# warten, benachrichtigen, Editor oeffnen, OCR, Bildschirmaufnahme --
# steht hier, weil es Shell-Arbeit ist und sich so auch auf eine Taste
# legen laesst.
#
# Absichtlich KEIN `set -e`: mehrere Funktionen enden mit einem Test, und
# unter `set -e` wuerde das Skript dort still aussteigen.
#
#   capture.sh post      <pfad> <editor> <auto 0|1> <melden 0|1>
#   capture.sh ocr       <pfad> <sprachen> <melden 0|1>
#   capture.sh edit-last <ordner> <editor>
#   capture.sh open-dir  <ordner>
#   capture.sh rec-start <ordner> <ton off|mic|desktop> <bereich 0|1> [args...]
#   capture.sh rec-stop  <melden 0|1>
#   capture.sh rec-active
set -uo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/screen-capture-recording"
APP="Screen Capture"

have() { command -v "$1" >/dev/null 2>&1; }

note() {
	# -a setzt den App-Namen, damit DMS die Meldungen gruppiert.
	notify-send -a "$APP" "$@" >/dev/null 2>&1
}

fail() {
	notify-send -a "$APP" -u critical "$APP" "$1" -t 6000 >/dev/null 2>&1
	echo "$1" >&2
	exit 1
}

need() {
	have "$1" || fail "$1 fehlt. Installieren mit: sudo pacman -S $2"
}

stamp() { date +'%Y-%m-%d_%H-%M-%S'; }

open_editor() {
	local file="$1" editor="${2:-satty}"

	case "$editor" in
	satty)
		need satty satty
		# Wie in Omarchy: Enter speichert und legt das Bild in die
		# Zwischenablage, gespeichert wird ueber die Vorlage.
		satty --filename "$file" \
			--output-filename "$file" \
			--actions-on-enter save-to-clipboard \
			--save-after-copy \
			--copy-command wl-copy
		;;
	swappy)
		need swappy swappy
		swappy -f "$file"
		;;
	*)
		# Freier Befehl. %path% wird ersetzt, sonst haengt der Pfad
		# hinten dran. Bewusst ohne Anfuehrungszeichen, damit eigene
		# Argumente durchkommen -- der Wert stammt aus den eigenen
		# Einstellungen, nicht von aussen.
		if [[ $editor == *%path%* ]]; then
			# shellcheck disable=SC2086
			${editor//\%path\%/$file}
		else
			# shellcheck disable=SC2086
			$editor "$file"
		fi
		;;
	esac
}

# niris Auswahl darf dauern (der Nutzer sucht sich das Fenster in Ruhe aus),
# deshalb bis zu zwei Minuten. Wer abbricht, hinterlaesst gar keine Datei --
# dann endet das Skript ohne Meldung.
wait_for_file() {
	local file="$1" i
	for ((i = 0; i < 600; i++)); do
		[[ -s $file ]] && return 0
		sleep 0.2
	done
	return 1
}

cmd_post() {
	local file="$1" editor="${2:-satty}" auto="${3:-0}" notify="${4:-1}"
	wait_for_file "$file" || exit 0

	if [[ $auto == 1 ]]; then
		[[ $notify == 1 ]] && note "Screenshot gespeichert" "$(basename "$file")" -i "$file" -t 4000
		open_editor "$file" "$editor"
		exit 0
	fi

	[[ $notify == 1 ]] || exit 0

	# -A laesst notify-send warten, bis geklickt oder ausgeblendet wird.
	# timeout ist die Reissleine, falls der Melder keine Aktionen kann.
	local action
	action=$(timeout 20 notify-send -a "$APP" \
		"Screenshot gespeichert" "In der Zwischenablage · klicken zum Bearbeiten" \
		-i "$file" -t 10000 -A "edit=Bearbeiten" 2>/dev/null)
	[[ $action == edit ]] && open_editor "$file" "$editor"
	return 0
}

cmd_ocr() {
	local file="$1" langs="${2:-eng}" notify="${3:-1}"
	need tesseract "tesseract tesseract-data-deu tesseract-data-eng"
	wait_for_file "$file" || exit 0

	# niri legt das Bild selbst in die Zwischenablage. Kurz warten, sonst
	# ueberschreibt es hinterher den Text, den wir gleich hineinlegen.
	sleep 0.4

	local text
	text=$(tesseract "$file" stdout --oem 1 --psm 6 -l "$langs" --dpi 300 \
		-c preserve_interword_spaces=1 2>/dev/null)
	rm -f "$file"

	if [[ -z ${text//[[:space:]]/} ]]; then
		[[ $notify == 1 ]] && note "Kein Text erkannt" "Nichts in der Auswahl gefunden." -t 4000
		exit 1
	fi

	printf '%s' "$text" | wl-copy
	[[ $notify == 1 ]] && note "Text kopiert" "$(printf '%s' "$text" | head -c 140)" -t 5000
	return 0
}

cmd_edit_last() {
	local dir="$1" editor="${2:-satty}" file
	file=$(ls -1t "$dir"/*.png "$dir"/*.jpg "$dir"/*.jpeg 2>/dev/null | head -1)
	[[ -n $file ]] || fail "Keine Aufnahme in $dir gefunden."
	open_editor "$file" "$editor"
}

cmd_open_dir() {
	local dir="$1"
	mkdir -p "$dir"
	need xdg-open xdg-utils
	xdg-open "$dir" >/dev/null 2>&1 &
	return 0
}

cmd_rec_start() {
	local dir="$1" audio="${2:-off}" region="${3:-0}"
	shift 3
	need wf-recorder wf-recorder

	pgrep -x wf-recorder >/dev/null && exit 0
	mkdir -p "$dir"

	local args=()
	if [[ $region == 1 ]]; then
		need slurp slurp
		local geo
		geo=$(slurp 2>/dev/null)
		[[ -n $geo ]] || exit 0 # abgebrochen
		args+=(-g "$geo")
	else
		# Ohne -o nimmt wf-recorder irgendeinen Ausgang; wir wollen den,
		# auf dem der Nutzer gerade arbeitet.
		local out
		out=$(niri msg -j focused-output 2>/dev/null | jq -r '.name // empty' 2>/dev/null)
		[[ -n $out ]] && args+=(-o "$out")
	fi

	case "$audio" in
	mic)
		args+=(--audio)
		;;
	desktop)
		local sink
		sink=$(pactl get-default-sink 2>/dev/null)
		if [[ -n $sink ]]; then
			args+=(--audio="${sink}.monitor")
		else
			args+=(--audio)
		fi
		;;
	esac

	local file="$dir/screenrecording-$(stamp).mp4"
	printf '%s' "$file" >"$STATE_FILE"

	# Losgeloest starten, damit die Aufnahme einen Neustart der Shell
	# ueberlebt und nicht am Skript haengt.
	setsid wf-recorder "${args[@]}" "$@" -f "$file" >/dev/null 2>&1 &
	disown

	sleep 0.6
	if pgrep -x wf-recorder >/dev/null; then
		note "Aufnahme laeuft" "$(basename "$file")" -t 3000
	else
		rm -f "$STATE_FILE"
		fail "Aufnahme konnte nicht gestartet werden."
	fi
	return 0
}

cmd_rec_stop() {
	local notify="${1:-1}" i
	pgrep -x wf-recorder >/dev/null || exit 0

	# SIGINT ist Pflicht -- nur dann schreibt wf-recorder die Datei fertig.
	pkill -INT -x wf-recorder
	for ((i = 0; i < 100; i++)); do
		pgrep -x wf-recorder >/dev/null || break
		sleep 0.1
	done
	if pgrep -x wf-recorder >/dev/null; then
		pkill -9 -x wf-recorder
		note "Aufnahme abgebrochen" "Der Rekorder musste hart beendet werden, die Datei kann beschaedigt sein." -u critical -t 6000
		rm -f "$STATE_FILE"
		exit 1
	fi

	local file
	file=$(cat "$STATE_FILE" 2>/dev/null)
	rm -f "$STATE_FILE"
	[[ $notify == 1 ]] || exit 0
	[[ -s $file ]] || {
		note "Aufnahme leer" "Es wurde nichts geschrieben." -u critical -t 5000
		exit 1
	}

	local action
	action=$(timeout 20 notify-send -a "$APP" \
		"Aufnahme gespeichert" "$(basename "$file") · klicken zum Abspielen" \
		-t 10000 -A "open=Öffnen" 2>/dev/null)
	[[ $action == open ]] && xdg-open "$file" >/dev/null 2>&1 &
	return 0
}

case "${1:-}" in
post) shift && cmd_post "$@" ;;
ocr) shift && cmd_ocr "$@" ;;
edit-last) shift && cmd_edit_last "$@" ;;
open-dir) shift && cmd_open_dir "$@" ;;
rec-start) shift && cmd_rec_start "$@" ;;
rec-stop) shift && cmd_rec_stop "$@" ;;
rec-active) pgrep -x wf-recorder >/dev/null ;;
*)
	echo "Aufruf: $(basename "$0") post|ocr|edit-last|open-dir|rec-start|rec-stop|rec-active ..." >&2
	exit 2
	;;
esac
