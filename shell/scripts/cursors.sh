#!/usr/bin/env bash
#
# Mouse cursors: list available themes and apply one.
#
#   cursors.sh list                 -> JSON: ["Adwaita","macOS",…]
#   cursors.sh apply <theme> <px>   -> write the niri file and update GTK
#   cursors.sh current              -> print the active settings
#
# Ein Zeigerthema ist ein Verzeichnis mit Bilddateien, kein Programm: alles
# unter /usr/share/icons oder ~/.local/share/icons, das einen `cursors`-Ordner
# hat, zaehlt. Deshalb kann man eines von Hand dazulegen (siehe README), ohne
# etwas zu installieren.
#
# Geschrieben wird an ZWEI Stellen, und das ist kein Versehen:
#
#   niri      ueber eine eigene Include-Datei; niri gibt Thema und Groesse an
#             alles weiter, was es startet (XCURSOR_THEME/XCURSOR_SIZE).
#   gsettings weil GTK nicht niri fragt. Ohne diesen Teil behalten
#             Dateidialoge den alten Zeiger -- ein halber Wechsel, der genau
#             dort auffaellt, wo man ihn am wenigsten erwartet.
set -uo pipefail

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
UMBRIEL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel"
CURSOR_FILE="nbshell-cursor.kdl"
CURSOR_LINE="include \"$CURSOR_FILE\""

themes() {
	local d
	for d in /usr/share/icons/*/cursors "$HOME"/.icons/*/cursors "$HOME"/.local/share/icons/*/cursors; do
		[ -d "$d" ] || continue
		basename "$(dirname "$d")"
	done | sort -u
}

cmd_list() {
	themes | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()], ensure_ascii=False))'
}

cmd_current() {
	if [ -f "$NIRI_DIR/$CURSOR_FILE" ]; then
		printf '{"theme":"%s","size":%s}\n' \
			"$(awk -F'"' '/xcursor-theme/ {print $2}' "$NIRI_DIR/$CURSOR_FILE")" \
			"$(awk '/xcursor-size/ {print $2}' "$NIRI_DIR/$CURSOR_FILE")"
	else
		printf '{"theme":"%s","size":%s}\n' "${XCURSOR_THEME:-}" "${XCURSOR_SIZE:-24}"
	fi
}

cmd_apply() {
	local theme="${1:-}" size="${2:-24}"
	[ -n "$theme" ] || {
		echo "Theme is required" >&2
		return 1
	}
	themes | grep -qx "$theme" || {
		echo "Unknown cursor theme: $theme" >&2
		themes | sed 's/^/  /' >&2
		return 1
	}
	case "$size" in
	'' | *[!0-9]*)
		echo "Size must be a number: $size" >&2
		return 1
		;;
	esac

	mkdir -p "$NIRI_DIR"
	cat >"$NIRI_DIR/$CURSOR_FILE" <<KDL
// Managed by nbshell. The cursor command and settings menu update this file.
cursor {
    xcursor-theme "$theme"
    xcursor-size $size
}
KDL

	# Die Include-Zeile nur einmal, und nur wenn niri danach noch einverstanden
	# ist. Eine ungueltige Config heisst: keine Sitzung mehr.
	local cfg="$NIRI_DIR/config.kdl"
	if [ -f "$cfg" ] && ! grep -qF "$CURSOR_LINE" "$cfg"; then
		cp "$cfg" "$cfg.vor-cursor"
		printf '\n// Cursor settings managed by nbshell\n%s\n' "$CURSOR_LINE" >>"$cfg"
		if command -v niri >/dev/null 2>&1 && ! niri validate >/dev/null 2>&1; then
			mv "$cfg.vor-cursor" "$cfg"
			echo "The niri configuration would be invalid; the change was reverted." >&2
			return 1
		fi
	fi

	if command -v gsettings >/dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface cursor-theme "$theme" 2>/dev/null || true
		gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null || true
	fi

	# Umbriel owns the compositor cursor in an Umbriel session. Keep this in a
	# small generated include so the repository-owned integration stays intact.
	mkdir -p "$UMBRIEL_DIR"
	python3 - "$theme" "$size" "$UMBRIEL_DIR/nbshell-cursor.toml" <<'PY'
import json
import pathlib
import sys

theme, size, destination = sys.argv[1:]
text = "# Managed by nbshell cursor settings.\n[input.cursor]\n"
text += f"theme = {json.dumps(theme)}\nsize = {int(size)}\n"
pathlib.Path(destination).write_text(text)
PY
	if [ -n "${UMBRIEL_SOCKET:-}" ] || [[ "${XDG_CURRENT_DESKTOP:-}" == *[Uu]mbriel* ]]; then
		umbriel msg config-reload >/dev/null 2>&1 || true
	fi

	printf '%s %s\n' "$theme" "$size"
}

case "${1:-list}" in
list) cmd_list ;;
current) cmd_current ;;
apply)
	shift
	cmd_apply "$@"
	;;
*)
	echo "Usage: $(basename "$0") list|current|apply <theme> [size]" >&2
	exit 2
	;;
esac
