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
#   updates.sh reboot-status -> JSON status from the last successful update
set -uo pipefail

DB="${XDG_CACHE_HOME:-$HOME/.cache}/nbshell/checkupdates-db"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nbshell"
REBOOT_STATE="${NBSHELL_REBOOT_STATE:-$STATE_DIR/update-reboot.json}"

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

# Execute fixed argument vectors instead of evaluating the human-readable
# command above. Today all values are internal, but keeping update execution
# free of `eval` prevents a future option from accidentally becoming shell
# syntax in this privileged path.
run_pkg_update() {
	local args=(-Syu)
	[ "$NOCONFIRM" = "1" ] && args+=(--noconfirm)
	if have paru; then
		paru "${args[@]}"
	elif have yay; then
		yay "${args[@]}"
	else
		sudo pacman "${args[@]}"
	fi
}

run_flatpak_update() {
	local args=(update)
	[ "$NOCONFIRM" = "1" ] && args+=(-y)
	flatpak "${args[@]}"
}

boot_id() {
	cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown'
}

# These packages replace components that cannot be fully swapped underneath a
# running desktop session. This is deliberately narrower than "every shared
# library": normal services can be restarted without turning each Arch update
# into a reboot prompt.
reboot_package() {
	case "$1" in
	linux | linux-lts | linux-zen | linux-hardened | linux-cachyos* | amd-ucode | intel-ucode | systemd | systemd-libs | glibc | linux-firmware | nvidia | nvidia-open | nvidia-dkms | nvidia-open-dkms | nvidia-utils | mesa | vulkan-*) return 0 ;;
	esac
	return 1
}

write_reboot_state() {
	local packages="$1" tmp
	mkdir -p "$STATE_DIR"
	tmp="$(mktemp "$STATE_DIR/.update-reboot.XXXXXX")" || return 1
	PACKAGES="$packages" BOOT_ID="$(boot_id)" python3 - "$tmp" "$REBOOT_STATE" <<'PY'
import json, os, sys, time

packages = [line for line in os.environ.get("PACKAGES", "").splitlines() if line]
boot_id = os.environ.get("BOOT_ID", "unknown")
try:
    with open(sys.argv[2], encoding="utf-8") as handle:
        previous = json.load(handle)
    if previous.get("bootId") == boot_id and previous.get("recommended") is True:
        packages.extend(str(item) for item in previous.get("packages", []))
except (OSError, ValueError, TypeError):
    pass
packages = sorted(set(packages))
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "recommended": bool(packages),
        "packages": packages,
        "bootId": boot_id,
        "updatedAt": int(time.time()),
    }, handle, separators=(",", ":"))
    handle.write("\n")
os.chmod(sys.argv[1], 0o600)
PY
	mv -f "$tmp" "$REBOOT_STATE"
}

reboot_status() {
	BOOT_ID="$(boot_id)" python3 - "$REBOOT_STATE" <<'PY'
import json, os, sys

fallback = {"recommended": False, "packages": [], "updatedAt": 0}
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("bootId") != os.environ.get("BOOT_ID"):
        data = fallback
except (OSError, ValueError, TypeError):
    data = fallback
print(json.dumps(data, separators=(",", ":")))
PY
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
	pkg_rc=0
	critical="$(
		{ repo_updates; aur_updates; } | awk '{print $1}' | sort -u |
			while IFS= read -r package; do
				reboot_package "$package" && printf '%s\n' "$package"
			done
	)"
	echo ":: Systempakete"
	run_pkg_update || { pkg_rc=$?; rc=$pkg_rc; }
	if [ "$pkg_rc" -eq 0 ]; then
		write_reboot_state "$critical"
		if [ -n "$critical" ]; then
			echo
			echo "Restart recommended: core system components were updated ($(printf '%s' "$critical" | paste -sd ',' - | sed 's/,/, /g'))."
			have notify-send && notify-send -a nbshell -u normal "Restart recommended" "Core system components were updated. Restart when convenient."
		fi
	fi
	if have flatpak; then
		echo
		echo ":: Flatpak"
		run_flatpak_update || rc=$?
	fi
	exit $rc
	;;
reboot-status)
	reboot_status
	;;
*)
	echo "Usage: $(basename "$0") check|command|run|reboot-status" >&2
	exit 2
	;;
esac
