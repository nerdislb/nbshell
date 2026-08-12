#!/usr/bin/env bash
#
# Den Ton zu den Bluetooth-Hoerern zurueckholen.
#
# Der Fall: die Kopfhoerer koennen an zwei Geraeten gleichzeitig haengen
# (Multipoint). Kommt ein Anruf aufs Telefon, wechseln sie dorthin -- und
# danach nicht von selbst zurueck. Googles „Audio Switch" hilft nicht: das
# schaltet nur zwischen Geraeten mit demselben Google-Konto, ein Linux-Laptop
# ist dort nicht dabei.
#
# Zurueck geht es nur, wenn DIESE Seite wieder Ton anmeldet. Das tut sie aber
# nicht mehr, denn WirePlumber legt eine untaetige Senke nach fuenf Sekunden
# schlafen (suspend-node.lua). Waehrend des Telefonats pausiert die Musik, die
# Senke schlaeft ein -- und nach dem Anruf ist nichts mehr da, wohin die Hoerer
# zurueckkehren koennten.
#
# Das Gegenmittel ohne Nebenwirkung ist ein Anstupsen auf Zuruf: das Profil
# einmal aus- und wieder einschalten. Damit wird die Audioverbindung neu
# aufgebaut, und die Hoerer nehmen sie an.
#
# Die Alternative waere, die Senke gar nicht erst schlafen zu lassen
# (`session.suspend-timeout-seconds = 0`). Dann bliebe die Verbindung dauernd
# offen -- mehr Akkuverbrauch an den Hoerern, und manche rauschen bei offenem,
# stillem Stream leise vor sich hin. Deshalb hier der Weg auf Knopfdruck.
set -uo pipefail

meldung() { printf '{"ok": %s, "grund": "%s"}\n' "$1" "$2"; }

command -v pactl >/dev/null 2>&1 || { meldung false "pactl fehlt"; exit 1; }

MERKER="${XDG_STATE_HOME:-$HOME/.local/state}/nbshell/ton-geraet"

# Zwei Faelle, und der zweite kam erst beim Nachsehen heraus:
#
#   1. Die Hoerer haengen noch am Laptop, die Senke schlaeft nur. Dann genuegt
#      ein Anstupsen des Profils.
#   2. Sie haben sich GANZ getrennt -- keine Karte, keine Senke. Genau das war
#      hier der Fall, nachdem das Telefon sie uebernommen hatte. Dann hilft
#      kein Profilwechsel, sondern nur ein Verbinden.
karte="$(pactl list cards short 2>/dev/null | awk '/bluez_card/ {print $2; exit}')"

if [ -z "$karte" ]; then
	# Welches Geraet? Das zuletzt benutzte, sonst das erste gepaarte, das
	# ueberhaupt Ton kann -- ein Tastatur- oder Maus-Eintrag hilft hier nicht.
	mac=""
	[ -r "$MERKER" ] && mac="$(cat "$MERKER" 2>/dev/null)"
	if [ -z "$mac" ] || ! bluetoothctl info "$mac" >/dev/null 2>&1; then
		while read -r _ kandidat _; do
			[ -n "$kandidat" ] || continue
			if bluetoothctl info "$kandidat" 2>/dev/null | grep -qi 'Icon: audio'; then
				mac="$kandidat"
				break
			fi
		done < <(bluetoothctl devices Paired 2>/dev/null)
	fi
	if [ -z "$mac" ]; then
		meldung false "kein gepaartes Tongeraet gefunden"
		exit 1
	fi

	# Mit Deckel: `bluetoothctl connect` wartet sonst bis zu einer Minute auf
	# ein Geraet, das gar nicht antworten kann, weil es am Telefon haengt oder
	# im Etui liegt. Fuer einen Knopf, der den Ton zurueckholen soll, ist eine
	# Minute Schweigen dasselbe wie ein Fehler -- nur laenger.
	timeout 8 bluetoothctl connect "$mac" >/dev/null 2>&1 &
	frisch=1

	# Die Karte taucht auf, sobald es geklappt hat -- darauf wird gewartet,
	# nicht auf den Befehl.
	for _ in $(seq 1 40); do
		karte="$(pactl list cards short 2>/dev/null | awk '/bluez_card/ {print $2; exit}')"
		[ -n "$karte" ] && break
		sleep 0.2
	done
	if [ -z "$karte" ]; then
		wait 2>/dev/null
		meldung false "Verbinden mit $mac ging nicht — Hoerer im Etui oder noch am Telefon?"
		exit 1
	fi
fi

# Fuer das naechste Mal merken.
mkdir -p "$(dirname "$MERKER")"
printf '%s' "${karte#bluez_card.}" | tr '_' ':' > "$MERKER"

# Welches Ausgabeprofil das Geraet ueberhaupt kann. A2DP ist das mit der guten
# Qualitaet; ohne Mikrofon. Wer telefoniert, landet ohnehin im Headset-Profil,
# und dann soll dieser Befehl nicht dazwischenfunken.
#
# NICHT das erste A2DP-Profil, sondern das mit der hoechsten Prioritaet. Das
# war hier ein echter Fehler und faellt nur auf, wenn man hinsieht: pactl
# listet `a2dp-sink-sbc` zuerst, und `a2dp-sink` OHNE Anhaengsel ist nicht
# etwa der Standard, sondern AAC. Die alte Fassung holte die Pixel Buds
# deshalb jedesmal auf SBC zurueck -- den schlechtesten der vier, obwohl sie
# AAC koennen. Die Prioritaet in der Klammer ist PipeWires eigene Rangfolge
# und die ehrlichste Quelle dafuer, was hier "das Beste" heisst.
profil="$(pactl list cards 2>/dev/null |
	awk -v k="$karte" '
		# Nur `Card #` beendet den Block -- pactl rueckt mit Tabulatoren ein,
		# und ein Versuch, ueber die Einrueckung abzugrenzen, schlug fehl:
		# "Driver:" steht auf derselben Ebene wie "Name:" und beendete den
		# Block sofort nach der ersten Zeile.
		/^Card #/ { gefunden = 0 }
		$0 ~ "Name: "k { gefunden = 1; next }
		gefunden && /a2dp/ && /priority:/ {
			name = $1; sub(/:$/, "", name)
			if (match($0, /priority: [0-9]+/))
				print substr($0, RSTART + 10, RLENGTH - 10), name
		}' |
	sort -rn | head -1 | awk '{print $2}')"
[ -n "$profil" ] || profil="a2dp-sink"

vorher="$(pactl get-default-sink 2>/dev/null)"

# Nur anstupsen, wenn die Karte schon vorher da war. Frisch verbunden steht
# a2dp ohnehin, und ein Aus/An waere bloss ein zweiter Abbruch.
if [ "${frisch:-0}" != "1" ]; then
	pactl set-card-profile "$karte" off 2>/dev/null
	sleep 0.5
	pactl set-card-profile "$karte" "$profil" 2>/dev/null || {
		meldung false "Profil $profil ging nicht"
		exit 1
	}
fi

# Die Senke braucht einen Moment, bis sie wieder da ist -- nachfragen statt
# blind warten.
senke=""
for _ in $(seq 1 20); do
	senke="$(pactl list sinks short 2>/dev/null | awk '/bluez_output/ {print $2; exit}')"
	[ -n "$senke" ] && break
	sleep 0.2
done
if [ -z "$senke" ]; then
	meldung false "Senke kam nicht zurueck"
	exit 1
fi

pactl set-default-sink "$senke" 2>/dev/null

# Was gerade spielt, mitnehmen. Ohne das haengen laufende Programme an der
# alten, verschwundenen Senke und sind still, obwohl alles verbunden aussieht.
umgezogen=0
while read -r nummer _; do
	[ -n "$nummer" ] || continue
	pactl move-sink-input "$nummer" "$senke" 2>/dev/null && umgezogen=$((umgezogen + 1))
done < <(pactl list sink-inputs short 2>/dev/null)

printf '{"ok": true, "senke": "%s", "vorher": "%s", "umgezogen": %d}\n' "$senke" "$vorher" "$umgezogen"
