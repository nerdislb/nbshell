#!/usr/bin/env bash
#
# Themes von aussen holen, aktualisieren, entfernen.
#
# Uebernommen aus omarchy2dms (gleiche Hand, gleiche Lizenz) -- inklusive der
# Ableitung einer colors.toml aus der alacritty.toml. Die brauchen alle Themes
# aus der Zeit vor Omarchys Umstellung auf colors.toml, und das sind bis heute
# die meisten im Umlauf.
#
#   theme-install.sh install [--force] <git-url|verzeichnis>
#   theme-install.sh remove  <name>
#   theme-install.sh update
#   theme-install.sh list
#
# Absichtlich KEIN `set -e`: mehrere Funktionen enden mit einem Test.
set -uo pipefail

THEME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/themes"

# Wird vom Trap geraeumt. Muss VOR dem Trap existieren -- unter `set -u`
# scheitert er sonst in jedem Aufruf, der gar nichts holt (list, remove).
TMP=""
trap '[ -n "$TMP" ] && rm -rf "$TMP"' EXIT

note() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

# Zwei Farben mischen, t=0 gibt a, t=1 gibt b.
mix() {
	awk -v a="${1#\#}" -v b="${2#\#}" -v t="$3" 'BEGIN{
		ar=strtonum("0x" substr(a,1,2)); ag=strtonum("0x" substr(a,3,2)); ab=strtonum("0x" substr(a,5,2))
		br=strtonum("0x" substr(b,1,2)); bg=strtonum("0x" substr(b,3,2)); bb=strtonum("0x" substr(b,5,2))
		printf "#%02x%02x%02x", int(ar*(1-t)+br*t+.5), int(ag*(1-t)+bg*t+.5), int(ab*(1-t)+bb*t+.5)
	}'
}

# Relative Luminanz nach WCAG -- entscheidet ueber hell/dunkel.
luminance() {
	awk -v h="${1#\#}" 'BEGIN{
		for (i=0;i<3;i++) {
			v = strtonum("0x" substr(h, 1+i*2, 2)) / 255
			v = (v <= 0.03928) ? v/12.92 : ((v+0.055)/1.055)^2.4
			s += v * (i==0 ? 0.2126 : i==1 ? 0.7152 : 0.0722)
		}
		print s
	}'
}

colors_from_alacritty() {
	local dir="$1" ala="$1/alacritty.toml"
	[ -f "$ala" ] || return 1

	declare -A A
	local section="" line key value
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		[[ $line =~ ^[[:space:]]*# ]] && continue
		if [[ $line =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
			section="${BASH_REMATCH[1]}"
			continue
		fi
		[[ $line =~ ^[[:space:]]*([A-Za-z_]+)[[:space:]]*=[[:space:]]*[\"\']?(#[0-9A-Fa-f]{6})[\"\']? ]] || continue
		key="${BASH_REMATCH[1]}"
		value="${BASH_REMATCH[2],,}"
		A["${section}.${key}"]="$value"
	done < "$ala"

	local bg fg
	bg="${A[colors.primary.background]:-}"
	fg="${A[colors.primary.foreground]:-}"
	[ -n "$bg" ] && [ -n "$fg" ] || return 1

	local blue accent mode lum
	blue="${A[colors.normal.blue]:-${A[colors.bright.blue]:-$fg}}"
	accent="${A[colors.bright.blue]:-$blue}"
	lum="$(luminance "$bg")"
	mode="$(awk -v l="$lum" 'BEGIN{print (l > 0.5) ? "light" : "dark"}')"

	{
		echo "# Aus alacritty.toml abgeleitet von nbshell."
		echo "# Das Theme brachte keine colors.toml mit."
		echo
		echo "mode = \"$mode\""
		echo
		echo "accent = \"$accent\""
		echo "selection = \"${A[colors.selection.background]:-$(mix "$bg" "$fg" 0.18)}\""
		echo "muted = \"${A[colors.bright.black]:-$(mix "$bg" "$fg" 0.35)}\""
		echo
		echo "background = \"$bg\""
		echo "dark_background = \"$(mix "$bg" "#000000" 0.25)\""
		echo "lighter_background = \"$(mix "$bg" "$fg" 0.12)\""
		echo
		echo "foreground = \"$fg\""
		echo "dark_foreground = \"$(mix "$fg" "$bg" 0.45)\""
		echo "light_foreground = \"$(mix "$fg" "#ffffff" 0.15)\""
		echo "bright_foreground = \"${A[colors.bright.white]:-$(mix "$fg" "#ffffff" 0.3)}\""
		echo
		local c
		for c in red yellow green cyan blue magenta; do
			[ -n "${A[colors.normal.$c]:-}" ] && echo "$c = \"${A[colors.normal.$c]}\""
		done
		for c in red yellow green cyan blue magenta; do
			[ -n "${A[colors.bright.$c]:-}" ] && echo "bright_$c = \"${A[colors.bright.$c]}\""
		done
	} > "$dir/colors.toml"

	# Explizit: sonst wird der Status der letzten Schleifenbedingung zum
	# Rueckgabewert -- fehlt dem Theme etwa bright_magenta, gaelte die
	# erfolgreich geschriebene Datei als Fehlschlag.
	return 0
}

# Ein Name ohne Trennzeichen und Grossschreibung. `lasthorizon` und
# `last-horizon` sind dasselbe Theme -- das Repo heisst nun mal anders als das
# Verzeichnis, das Omarchy mitliefert. Ohne diesen Vergleich steht beides
# nebeneinander in der Liste, mit derselben Palette und demselben Wallpaper.
norm() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

# Der Verzeichnisname eines schon installierten Themes, das so heisst -- oder
# nur so geschrieben. Leer, wenn es keines gibt.
installed_twin() {
	local want t n hit=""
	want="$(norm "$1")"
	for t in "$THEME_DIR"/*/; do
		[ -d "$t" ] || continue
		n="$(basename "$t")"
		[ "$(norm "$n")" = "$want" ] || continue
		# Gibt es beide Schreibweisen, gewinnt die genaue -- sonst meldet die
		# Sperre einen Namen, den man gar nicht installieren wollte.
		[ "$n" = "$1" ] && { printf '%s' "$n"; return 0; }
		[ -z "$hit" ] && hit="$n"
	done
	printf '%s' "$hit"
}

cmd_install() {
	local force=0 src path name dest twin

	while [ $# -gt 0 ]; do
		case "${1:-}" in
		-f | --force) force=1 && shift ;;
		--) shift && break ;;
		*) break ;;
		esac
	done

	src="${1:-}"
	[ -n "$src" ] || die "Aufruf: theme-install.sh install [--force] <git-url|verzeichnis>"

	# user@host:org/repo.git -- den Prefix abschneiden, damit basename greift.
	path="$src"
	[[ $path != *"://"* && $path == *:*/* ]] && path="${path#*:}"
	name="$(basename "$path" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')"
	[ -n "$name" ] || die "aus '$src' laesst sich kein Themename ableiten"

	dest="$THEME_DIR/$name"
	mkdir -p "$THEME_DIR"

	# VOR dem Holen fragen, ob es das schon gibt. Bisher wurde erst geklont und
	# danach kommentarlos ersetzt -- wer ein Theme zweimal installierte, sah
	# nichts davon, und ein selbst geaendertes war weg. Ersetzen soll man
	# muessen, nicht versehentlich tun.
	if [ $force -eq 0 ]; then
		twin="$(installed_twin "$name")"
		if [ -n "$twin" ]; then
			if [ "$twin" = "$name" ]; then
				note "'$name' ist schon installiert -- es wurde nichts geaendert."
			else
				note "'$twin' ist schon installiert; '$name' ist nur eine andere Schreibweise davon."
				note "es wurde nichts geaendert."
			fi
			note "trotzdem holen: nbshell theme install --force $src"
			return 0
		fi
	fi

	# ERST holen, DANN ersetzen. Andersherum ist ein vorhandenes Theme weg,
	# sobald das Klonen scheitert -- und das passiert schon bei einem Tippfehler
	# in der URL.
	TMP="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-theme.XXXXXX")" || die "kein temporaeres Verzeichnis"
	local tmp="$TMP"

	if [ -d "$src" ]; then
		cp -a "$src/." "$tmp/" || die "Kopieren von '$src' fehlgeschlagen"
	else
		command -v git >/dev/null || die "git wird zum Installieren gebraucht"
		# GIT_TERMINAL_PROMPT=0: sonst bleibt git bei einer falschen URL mit
		# einer Passwortfrage stehen, die niemand sieht.
		GIT_TERMINAL_PROMPT=0 git clone --depth 1 --quiet "$src" "$tmp/clone" 2>/dev/null \
			|| die "Klonen von '$src' fehlgeschlagen -- URL pruefen"
		mv "$tmp/clone"/* "$tmp/clone"/.[!.]* "$tmp/" 2>/dev/null
		rmdir "$tmp/clone" 2>/dev/null
	fi

	# Manche Repos verpacken das Theme in einem Unterverzeichnis.
	local work="$tmp"
	if [ ! -f "$work/colors.toml" ] && [ ! -f "$work/alacritty.toml" ]; then
		local inner
		inner="$(find "$work" -mindepth 2 -maxdepth 2 \( -name colors.toml -o -name alacritty.toml \) -print -quit)"
		[ -n "$inner" ] && {
			note "Theme liegt in $(basename "$(dirname "$inner")")/"
			work="$(dirname "$inner")"
		}
	fi

	if [ ! -f "$work/colors.toml" ]; then
		if colors_from_alacritty "$work"; then
			note "keine colors.toml -- Palette aus alacritty.toml abgeleitet"
		else
			die "'$name' enthaelt weder colors.toml noch eine lesbare alacritty.toml"
		fi
	fi

	# Jetzt erst das alte ersetzen.
	[ -d "$dest" ] && { note "'$name' war schon da -- wird ersetzt"; rm -rf "$dest"; }
	cp -a "$work" "$dest" || die "Installieren nach '$dest' fehlgeschlagen"

	local shots
	shots="$(find "$dest/backgrounds" -maxdepth 1 -type f 2>/dev/null | wc -l)"
	note "'$name' installiert (${shots} Bilder)"
	note "wechseln mit: nbshell theme $name"
}

cmd_remove() {
	local name="${1:-}"
	[ -n "$name" ] || die "Aufruf: theme-install.sh remove <name>"
	local dest="$THEME_DIR/$name"
	[ -d "$dest" ] || die "'$name' ist nicht installiert"
	rm -rf "$dest"
	note "'$name' entfernt"
}

# Nur Themes mit Git-Historie -- die mitgelieferten kommen aus dem Repo und
# wuerden beim naechsten install.sh ohnehin ueberschrieben.
cmd_update() {
	local t name found=0
	for t in "$THEME_DIR"/*/; do
		[ -d "$t/.git" ] || continue
		name="$(basename "$t")"
		found=1
		if git -C "$t" pull --quiet --ff-only 2>/dev/null; then
			note "$name aktualisiert"
		else
			note "$name uebersprungen (kein schneller Vorlauf moeglich)"
		fi
	done
	[ $found -eq 1 ] || note "keine selbst installierten Themes mit Git-Historie"
}

cmd_list() {
	local t name
	for t in "$THEME_DIR"/*/; do
		[ -f "$t/colors.toml" ] || continue
		name="$(basename "$t")"
		if [ -d "$t/.git" ]; then
			printf '%-22s selbst installiert\n' "$name"
		else
			printf '%-22s mitgeliefert\n' "$name"
		fi
	done
}

case "${1:-}" in
install) shift && cmd_install "$@" ;;
remove) shift && cmd_remove "${1:-}" ;;
update) cmd_update ;;
list) cmd_list ;;
*)
	echo "Aufruf: $(basename "$0") install [--force] <url|verzeichnis> | remove <name> | update | list" >&2
	exit 2
	;;
esac
