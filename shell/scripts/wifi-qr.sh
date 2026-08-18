#!/usr/bin/env bash
#
# Das verbundene WLAN als QR-Code -- zum Abscannen mit einem Telefon.
#
# Ausgegeben wird die MODULMATRIX als JSON, kein fertiges Bild und kein
# Blockzeichensalat:
#
#   {"ok":true,"ssid":"…","note":"","size":37,"rows":["  ##  ##…", …]}
#
# Der erste Versuch malte den Code mit `qrencode -t UTF8` aus Halbblockzeichen
# direkt ins Popout. Das sah gut aus und war NICHT LESBAR -- gleich dreifach:
#
#   1. Die Blockzeichen kamen hell auf dunklem Grund. Ein QR-Code ist per
#      Vorgabe dunkel auf hell; viele Kameras lesen die Umkehrung nicht.
#   2. Die Ruhezone war 1 Modul breit statt der vorgeschriebenen 4.
#   3. Der gestauchte Zeilenabstand (0.85) verzerrte die Module.
#
# Deshalb jetzt: eine Matrix aus Nullen und Einsen, die das Fenster als
# schwarze Quadrate auf weiss zeichnet. Die Ruhezone bringt `-m 4` mit.
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

fail() {
	printf '{"ok":false,"grund":"%s"}\n' "$1"
	exit 0
}

have qrencode || fail "qrencode fehlt — sudo pacman -S qrencode"
have nmcli || fail "nmcli is missing — NetworkManager is required for the network name"

ssid="${1:-}"
if [ -z "$ssid" ]; then
	# Die aktive WLAN-Verbindung. `-t` trennt mit Doppelpunkten, deshalb wird
	# nur bis zum ersten geschnitten -- Netznamen duerfen selbst keine
	# enthalten, der Rest der Zeile schon.
	ssid="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2 == "802-11-wireless" { print $1; exit }')"
fi

[ -n "$ssid" ] || fail "not connected to Wi-Fi"

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

note=""
if [ -z "$psk" ] && [ "$typ" = "WPA" ]; then
	note="no password — nmcli did not provide it"
fi

# `-t ASCII` malt jedes Modul mit ZWEI Zeichen (damit es im Terminal quadratisch
# wirkt). Fuer die Matrix wird deshalb jedes zweite genommen -- so ist eine
# Zeile so lang, wie der Code Module breit ist.
# OHNE abschliessenden Zeilenumbruch: `printf … '\\n'` haengt ihn an die
# NUTZLAST, nicht an die Ausgabe -- der Code kodiert dann ein Zeichen zu viel.
# Gelesen haetten ihn die meisten Kameras trotzdem, sauber ist es nicht.
matrix="$(printf 'WIFI:T:%s;S:%s;P:%s;;' "$typ" "$(escape "$ssid")" "$(escape "$psk")" |
	qrencode -t ASCII -m 4 2>/dev/null |
	awk '{ out = ""; for (i = 1; i <= length($0); i += 2) out = out substr($0, i, 1); print out }')"

[ -n "$matrix" ] || fail "qrencode returned no image"

QR_MATRIX="$matrix" QR_SSID="$ssid" QR_NOTE="$note" python3 - <<'PY'
import json, os

rows = [r for r in os.environ["QR_MATRIX"].split("\n") if r]
print(json.dumps({
    "ok": True,
    "ssid": os.environ["QR_SSID"],
    "note": os.environ["QR_NOTE"],
    "size": max((len(r) for r in rows), default=0),
    "rows": rows,
}, ensure_ascii=False))
PY
