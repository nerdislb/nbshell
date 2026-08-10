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
# Flatpaks kommen dazu, wenn flatpak installiert ist. Die Abfrage geht ins Netz
# (`remote-ls --updates` fragt die Gegenstelle) und bekommt deshalb eine
# Zeitgrenze -- ein haengendes Flathub darf die Pruefung nicht blockieren.
#
#   updates.sh check   -> JSON: {"repo":[{"name","from","to"}],"aur":[…],"flatpak":[…]}
#   updates.sh command -> was beim Aktualisieren liefe (nur zum Nachsehen)
#   updates.sh run     -> aktualisiert wirklich
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

# Flatpaks. `remote-ls --updates` nennt nur die neue Version, die installierte
# steht in `list` -- beide zusammen ergeben erst das "von → nach", das die
# Liste im Popout zeigt.
flatpak_updates() {
	have flatpak || return 0
	local installed
	installed="$(timeout 20 flatpak list --app --columns=application,version 2>/dev/null)" || return 0
	[ -n "$installed" ] || return 0
	timeout 60 flatpak remote-ls --updates --columns=application,version 2>/dev/null |
		awk -F'\t' -v inst="$installed" '
			BEGIN {
				n = split(inst, lines, "\n")
				for (i = 1; i <= n; i++) {
					split(lines[i], f, "\t")
					if (f[1] != "")
						have[f[1]] = f[2]
				}
			}
			$1 != "" {
				from = (have[$1] != "") ? have[$1] : "?"
				to = ($2 != "") ? $2 : "?"
				printf "%s %s -> %s\n", $1, from, to
			}'
}

# Der Paketteil. `--noconfirm` ist ausdruecklich gewuenscht: gefragt werden soll
# nur nach dem Passwort, nicht nach jedem Schritt.
#
# Was das mitbringt, gehoert dazugesagt -- pacman beantwortet damit AUCH die
# Rueckfragen, die keine Ja/Nein-Frage sind: ein Paket, das ein anderes ersetzt,
# wird ersetzt; ein Konflikt wird zugunsten des neuen Pakets aufgeloest; bei
# mehreren Anbietern gewinnt der erste. Und paru zeigt keine PKGBUILDs mehr zur
# Durchsicht. Wer das nicht will, setzt `updateNoconfirm` auf false.
NOCONFIRM="${NBSHELL_UPDATE_NOCONFIRM:-1}"

pkg_command() {
	local flag=""
	[ "$NOCONFIRM" = "1" ] && flag=" --noconfirm"
	if have paru; then
		echo "paru -Syu$flag"
	elif have yay; then
		echo "yay -Syu$flag"
	else
		echo "sudo pacman -Syu$flag"
	fi
}

flatpak_command() {
	have flatpak || return 0
	if [ "$NOCONFIRM" = "1" ]; then
		echo "flatpak update -y"
	else
		echo "flatpak update"
	fi
}

case "${1:-check}" in
check)
	printf '{"repo":'
	repo_updates | to_json
	printf ',"aur":'
	aur_updates | to_json
	printf ',"flatpak":'
	flatpak_updates | to_json
	printf '}\n'
	;;
command)
	pkg_command
	flatpak_command
	;;
run)
	# Beide Teile laufen, auch wenn der erste etwas zu meckern hatte: ein
	# fehlgeschlagenes AUR-Paket soll die Flatpaks nicht aufhalten. Der
	# Rueckgabewert bleibt trotzdem der schlechteste von beiden.
	rc=0
	echo ":: Systempakete"
	eval "$(pkg_command)" || rc=$?
	if have flatpak; then
		echo
		echo ":: Flatpak"
		eval "$(flatpak_command)" || rc=$?
	fi
	exit $rc
	;;
*)
	echo "Aufruf: $(basename "$0") check|command|run" >&2
	exit 2
	;;
esac
