#!/usr/bin/env bash
#
# Das verbundene WLAN als QR-Code -- zum Abscannen mit einem Telefon.
#
# Ausgegeben wird TEXT, keine Bilddatei: `qrencode -t UTF8` malt den Code aus
# Halbblockzeichen, und damit passt er in ein Popout, das ohnehin aus Zeichen
# besteht. Ein PNG muesste erst irgendwohin geschrieben, geladen und wieder
# aufgeraeumt werden -- fuer etwas, das zehn Sekunden sichtbar ist.
#
#   wifi-qr.sh [ssid]   ohne Angabe: das gerade verbundene Netz
#
# Das Passwort holt `nmcli -s`. Gehoert die Verbindung dem System und nicht dem
# Benutzer, fragt dabei polkit nach -- dafuer gibt es seit kurzem einen Agenten
# (siehe README, "Rechteabfragen"). Kommt kein Passwort zurueck, wird der Code
# trotzdem gebaut: fuer ein offenes Netz ist das richtig, und bei einem
# gesicherten sagt die Zeile darunter, woran es lag.
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

if ! have qrencode; then
	echo "qrencode fehlt — sudo pacman -S qrencode"
	exit 0
fi

if ! have nmcli; then
	echo "nmcli fehlt — ohne NetworkManager kein Netzname"
	exit 0
fi

ssid="${1:-}"
if [ -z "$ssid" ]; then
	# Die aktive WLAN-Verbindung. `-t` trennt mit Doppelpunkten, deshalb wird
	# nur bis zum ersten geschnitten -- Netznamen duerfen selbst keine
	# enthalten, der Rest der Zeile schon.
	ssid="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2 == "802-11-wireless" { print $1; exit }')"
fi

if [ -z "$ssid" ]; then
	echo "kein WLAN verbunden"
	exit 0
fi

psk="$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null || true)"
keymgmt="$(nmcli -g 802-11-wireless-security.key-mgmt connection show "$ssid" 2>/dev/null || true)"

# Nach der WIFI-Kennung, wie sie jedes Telefon versteht. Sonderzeichen in Name
# und Passwort werden maskiert -- ein Semikolon im Passwort beendet sonst das
# Feld, und der Code fuehrt ins Leere.
escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/;/\\;/g' -e 's/,/\\,/g' -e 's/:/\\:/g' -e 's/"/\\"/g'
}

if [ -n "$psk" ]; then
	typ="WPA"
elif [ -z "$keymgmt" ]; then
	typ="nopass"
else
	typ="WPA"
fi

printf 'WIFI:T:%s;S:%s;P:%s;;\n' "$typ" "$(escape "$ssid")" "$(escape "$psk")" |
	qrencode -t UTF8 -m 1 2>/dev/null

echo "$ssid"
if [ -z "$psk" ] && [ "$typ" = "WPA" ]; then
	echo "(ohne Passwort — nmcli gibt es nicht heraus)"
fi
