#!/usr/bin/env bash
#
# Bausteine von aussen einsammeln.
#
# Ein Plugin ist ein Verzeichnis unter ~/.config/nbshell/plugins mit einer
# manifest.json und der QML-Datei, die darin steht:
#
#   ~/.config/nbshell/plugins/wetter/
#       manifest.json     { "id": "wetter", "name": "Wetter", … }
#       BarWidget.qml
#
# Gelesen wird hier, nicht in QML: QML kann kein Verzeichnis auflisten.
# Ausgegeben wird eine JSON-Liste; kaputte Manifeste werden uebersprungen und
# gemeldet, statt die ganze Liste scheitern zu lassen -- ein Tippfehler in
# einem fremden Plugin darf die Leiste nicht leeren.
#
#   plugins.sh list   -> JSON
#   plugins.sh dir    -> das Verzeichnis (auch wenn es noch nicht existiert)
set -uo pipefail

PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/plugins"

cmd_list() {
	local first=1
	printf '['
	local manifest dir
	for manifest in "$PLUGIN_DIR"/*/manifest.json; do
		[ -f "$manifest" ] || continue
		dir="$(dirname "$manifest")"

		# python statt jq: jq ist auf einem frischen Arch nicht da, python
		# schon (pacman selbst braucht es nicht, aber quickshell zieht es
		# ueber die Werkzeugkette mit -- und ohne beides faellt die Liste
		# einfach leer aus, statt dass etwas kaputtgeht).
		local entry
		entry="$(python3 - "$manifest" "$dir" <<'PY' 2>/dev/null
import json, os, sys

path, directory = sys.argv[1], sys.argv[2]
with open(path) as handle:
    data = json.load(handle)

ident = str(data.get("id") or os.path.basename(directory))
qml = str(data.get("entry") or "BarWidget.qml")
full = os.path.join(directory, qml)
if not os.path.isfile(full):
    raise SystemExit(1)

print(json.dumps({
    "id": ident,
    "name": data.get("name") or ident,
    "description": data.get("description") or "",
    "category": data.get("category") or "Plugin",
    "entry": full,
    "dir": directory,
    "version": str(data.get("version") or ""),
    "author": data.get("author") or "",
}, ensure_ascii=False))
PY
)" || {
			printf '%s' "" >&2
			echo "nbshell/plugins: '$dir' uebersprungen (manifest.json unlesbar oder Einstiegsdatei fehlt)" >&2
			continue
		}
		[ -n "$entry" ] || continue

		[ $first -eq 1 ] || printf ','
		first=0
		printf '%s' "$entry"
	done
	printf ']\n'
}

case "${1:-list}" in
list) cmd_list ;;
dir)
	echo "$PLUGIN_DIR"
	;;
*)
	echo "Aufruf: $(basename "$0") list|dir" >&2
	exit 2
	;;
esac
