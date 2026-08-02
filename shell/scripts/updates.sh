#!/usr/bin/env bash
#
# Verfuegbare Updates suchen -- ohne root und ohne die Systemdatenbank
# anzufassen.
#
# Der Trick ist derselbe wie in `checkupdates` aus pacman-contrib: pacman
# synchronisiert in eine EIGENE Datenbank unter fakeroot, und `-Qu` vergleicht
# dagegen. Ein `pacman -Sy` auf die echte Datenbank waere die uebliche Falle --
# danach ist das System auf einem halben Stand ("partial upgrade"), und der
# naechste Paketwunsch zieht womoeglich Bibliotheken in Versionen, die zum Rest
# nicht passen.
#
#   updates.sh check   -> JSON: {"repo":[{"name","from","to"}],"aur":[...]}
#   updates.sh command -> der Befehl, mit dem aktualisiert wird
set -uo pipefail

DB="${XDG_CACHE_HOME:-$HOME/.cache}/nbshell/checkupdates-db"

have() { command -v "$1" >/dev/null 2>&1; }

# "name 1.2-1 -> 1.3-1" in ein JSON-Objekt.
to_json() {
	awk 'BEGIN { printf "[" ; first = 1 }
		NF >= 4 {
			if (!first) printf ","
			first = 0
			printf "{\"name\":\"%s\",\"from\":\"%s\",\"to\":\"%s\"}", $1, $2, $4
		}
		END { printf "]" }'
}

repo_updates() {
	if have checkupdates; then
		checkupdates 2>/dev/null
		return 0
	fi
	have fakeroot || return 0
	mkdir -p "$DB"
	# Die lokale Datenbank verlinken: `-Qu` braucht sie, synchronisiert wird
	# nur die Kopie.
	[ -L "$DB/local" ] || ln -sf /var/lib/pacman/local "$DB/local" 2>/dev/null
	# `--disable-sandbox` ist Pflicht: pacman 7 sperrt sich per Landlock in
	# einen Sandkasten und wechselt auf den Benutzer 'alpm' -- beides scheitert
	# unter fakeroot, und der Abgleich bricht mit "failed to retrieve some
	# files" ab. Ohne das Flag meldet die Pruefung stumm null Updates.
	fakeroot -- pacman -Sy --dbpath "$DB" --logfile /dev/null --disable-sandbox >/dev/null 2>&1 \
		|| fakeroot -- pacman -Sy --dbpath "$DB" --logfile /dev/null >/dev/null 2>&1
	pacman -Qu --dbpath "$DB" 2>/dev/null | grep -v '\[ignoriert\]\|\[ignored\]'
}

aur_updates() {
	if have paru; then
		paru -Qua 2>/dev/null
	elif have yay; then
		yay -Qua 2>/dev/null
	fi
}

case "${1:-check}" in
check)
	printf '{"repo":'
	repo_updates | to_json
	printf ',"aur":'
	aur_updates | to_json
	printf '}\n'
	;;
command)
	# Interaktiv im Terminal: es fragt nach dem Passwort und will bestaetigt
	# werden. Etwas anderes waere bei einem Systemupdate auch unheimlich.
	if have paru; then
		echo "paru -Syu"
	elif have yay; then
		echo "yay -Syu"
	else
		echo "sudo pacman -Syu"
	fi
	;;
*)
	echo "Aufruf: $(basename "$0") check|command" >&2
	exit 2
	;;
esac
