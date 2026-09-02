#!/usr/bin/env bash
#
# Termine lesen -- ueber khal, das seinerseits die von vdirsyncer geholten
# Ordner liest.
#
# Warum nicht direkt die .ics-Dateien: Wiederholungen. Ein "jeden zweiten
# Dienstag im Monat, ausser am 24.12." steht als RRULE in der Datei und muss
# ausgerechnet werden. khal kann das, ein Leser in QML koennte es nicht.
#
# Google, iCloud & Co. kommen ueber vdirsyncer in ~/.local/share/calendars und
# sind damit fuer khal ganz normale Ordner -- die Shell weiss von keinem
# Anbieter etwas.
#
#   calendar.sh events <ISO-Datum> <Tage>   -> JSON
#   calendar.sh calendars                   -> die Namen, einer je Zeile
#   calendar.sh writable-calendars          -> beschreibbare Namen, je Zeile
#   calendar.sh create <Kalender> <Start-ISO> <Ende-ISO> <Titel>
#   calendar.sh sync                        -> vdirsyncer anstossen
#   calendar.sh status                      -> was fehlt
set -uo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/khal/config"

have() { command -v "$1" >/dev/null 2>&1; }

# khal versteht Datumsangaben NUR in dem Format, das in seiner Config steht --
# ein ISO-Datum quittiert es mit "Could not parse". Also holen wir uns das
# Format und rechnen um. Es ist eine strftime-Zeichenkette, `date` kann das
# direkt.
khal_dateformat() {
	local fmt=""
	[ -f "$CONFIG" ] && fmt="$(sed -nE 's/^[[:space:]]*dateformat[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$CONFIG" | head -1)"
	printf '%s' "${fmt:-%d.%m.%Y}"
}

khal_timeformat() {
	local fmt=""
	[ -f "$CONFIG" ] && fmt="$(sed -nE 's/^[[:space:]]*timeformat[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$CONFIG" | head -1)"
	printf '%s' "${fmt:-%H:%M}"
}

# Und zurueck: khal gibt seine Daten im selben Format aus, QML will ISO.
# Angefasst werden nur die Werte hinter "start-full"/"end-full" -- der Titel
# bleibt unberuehrt, auch wenn zufaellig ein Datum darin steht.
to_iso() {
	local fmt="$1"
	case "$fmt" in
	'%d.%m.%Y' | '%d.%m.%y')
		sed -E 's/"(start-full|end-full)": "([0-9]{2})\.([0-9]{2})\.([0-9]{4}) ([0-9]{2}:[0-9]{2})"/"\1": "\4-\3-\2T\5"/g'
		;;
	'%m/%d/%Y')
		sed -E 's/"(start-full|end-full)": "([0-9]{2})\/([0-9]{2})\/([0-9]{4}) ([0-9]{2}:[0-9]{2})"/"\1": "\4-\2-\3T\5"/g'
		;;
	*)
		# Unbekanntes Format: unveraendert durchreichen. Die Shell zeigt dann
		# den Rohtext -- besser als ein falsch gedrehtes Datum.
		cat
		;;
	esac
}

cmd_events() {
	local iso="${1:-}" days="${2:-45}"
	[ -n "$iso" ] || iso="$(date +%F)"

	if ! have khal; then
		printf '{"ok":false,"grund":"khal fehlt","events":[]}\n'
		return 0
	fi

	local fmt start
	fmt="$(khal_dateformat)"
	start="$(date -d "$iso" +"$fmt" 2>/dev/null)" || start=""
	if [ -z "$start" ]; then
		printf '{"ok":false,"grund":"Datum unlesbar","events":[]}\n'
		return 0
	fi

	# khal schreibt PRO TAG eine eigene JSON-Liste, nicht eine grosse. Die
	# Klammern fallen weg, der Rest wird mit Komma aneinandergehaengt.
	local body
	body="$(khal list --json start-full --json end-full --json title --json calendar --json all-day \
		"$start" "${days}d" 2>/dev/null |
		to_iso "$fmt" |
		sed -E 's/^\[//; s/\]$//' |
		grep -v '^[[:space:]]*$' |
		paste -sd, -)"

	printf '{"ok":true,"events":[%s]}\n' "$body"
}

cmd_calendars() {
	have khal || return 0
	khal printcalendars 2>/dev/null
}

# Only explicit calendar sections are safe write targets. In particular, a
# calendar merely reported by khal (for example through discovery) does not
# become writable by accident. A readonly value is scoped to its [[name]].
cmd_writable_calendars() {
	[ -f "$CONFIG" ] || return 0
	awk '
		function emit() { if (name != "" && !readonly) print name }
		/^[[:space:]]*\[\[[^][]+\]\][[:space:]]*([#;].*)?$/ {
			emit()
			line = $0
			sub(/^[[:space:]]*\[\[/, "", line)
			sub(/\]\][[:space:]]*([#;].*)?$/, "", line)
			name = line
			readonly = 0
			next
		}
		name != "" && /^[[:space:]]*readonly[[:space:]]*=/ {
			value = $0
			sub(/^[^=]*=[[:space:]]*/, "", value)
			sub(/[[:space:]]*([#;].*)?$/, "", value)
			value = tolower(value)
			if (value == "true" || value == "yes" || value == "on" || value == "1") readonly = 1
		}
		END { emit() }
	' "$CONFIG"
}

fail_create() {
	printf '%s\n' "$1" >&2
	return 1
}

valid_local_iso() {
	[[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] &&
		date -d "$1" +%s >/dev/null 2>&1
}

cmd_create() {
	local calendar="${1:-}" start_iso="${2:-}" end_iso="${3:-}" title="${4:-}"
	[ -n "$calendar" ] || fail_create "Choose a writable calendar." || return
	[ -n "${title//[[:space:]]/}" ] || fail_create "Enter an event title." || return
	have khal || fail_create "khal is not installed." || return

	local writable=false name
	while IFS= read -r name; do
		if [ "$name" = "$calendar" ]; then writable=true; break; fi
	done < <(cmd_writable_calendars)
	[ "$writable" = true ] || fail_create "Calendar '$calendar' is not configured as writable." || return
	valid_local_iso "$start_iso" || fail_create "Start must be a valid local ISO date and time (YYYY-MM-DDTHH:MM)." || return
	valid_local_iso "$end_iso" || fail_create "End must be a valid local ISO date and time (YYYY-MM-DDTHH:MM)." || return

	local start_epoch end_epoch date_fmt time_fmt start_arg end_arg
	start_epoch="$(date -d "$start_iso" +%s)"
	end_epoch="$(date -d "$end_iso" +%s)"
	(( end_epoch > start_epoch )) || fail_create "End time must be after start time." || return
	date_fmt="$(khal_dateformat)"
	time_fmt="$(khal_timeformat)"
	start_arg="$(date -d "$start_iso" +"$date_fmt $time_fmt")"
	end_arg="$(date -d "$end_iso" +"$date_fmt $time_fmt")"

	# Every user-controlled value is one argv element; never reconstruct a
	# command string or use eval.
	khal new --calendar "$calendar" "$start_arg" "$end_arg" "$title" >/dev/null ||
		fail_create "khal could not create the event. Check the calendar and dates."
}

# Abgleichen ist Sache von vdirsyncer. Laeuft der Timer, gehoert ihm auch der
# Dienst -- ihn von Hand zu starten waere zwar moeglich, liefe aber an der
# Sperre des Timers vorbei und koennte zwei Abgleiche gleichzeitig ergeben.
cmd_sync() {
	if systemctl --user list-unit-files vdirsyncer.service >/dev/null 2>&1 &&
		systemctl --user cat vdirsyncer.service >/dev/null 2>&1; then
		systemctl --user start vdirsyncer.service >/dev/null 2>&1 && {
			echo "vdirsyncer angestossen"
			return 0
		}
	fi
	if have vdirsyncer; then
		vdirsyncer sync >/dev/null 2>&1 && {
			echo "abgeglichen"
			return 0
		}
		echo "vdirsyncer reported an error" >&2
		return 1
	fi
	echo "vdirsyncer is not installed" >&2
	return 1
}

cmd_status() {
	local khal_ok=false vdir_ok=false timer=""
	have khal && khal_ok=true
	have vdirsyncer && vdir_ok=true
	timer="$(systemctl --user is-active vdirsyncer.timer 2>/dev/null)"
	printf '{"khal":%s,"vdirsyncer":%s,"timer":"%s","kalender":%s}\n' \
		"$khal_ok" "$vdir_ok" "${timer:-unknown}" \
		"$(cmd_calendars | wc -l)"
}

case "${1:-events}" in
events) shift && cmd_events "${1:-}" "${2:-45}" ;;
calendars) cmd_calendars ;;
writable-calendars) cmd_writable_calendars ;;
create) shift && cmd_create "${1:-}" "${2:-}" "${3:-}" "${4:-}" ;;
sync) cmd_sync ;;
status) cmd_status ;;
*)
	echo "Usage: $(basename "$0") events <ISO-date> <days> | calendars | writable-calendars | create <calendar> <start-iso> <end-iso> <title> | sync | status" >&2
	exit 2
	;;
esac
