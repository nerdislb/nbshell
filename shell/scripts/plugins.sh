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
#   plugins.sh list           -> JSON
#   plugins.sh dir            -> das Verzeichnis (auch wenn es noch nicht existiert)
#   plugins.sh add <quelle>   -> git-Repo oder Verzeichnis hereinholen
#   plugins.sh update [name]  -> geklonte Plugins nachziehen
#   plugins.sh remove <name>  -> wieder entfernen
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

# Prueft ein frisch hereingeholtes Verzeichnis, BEVOR es stehen bleibt: ohne
# manifest.json und die darin genannte QML-Datei ist es kein Plugin, sondern
# irgendein Repo -- und die Leiste meldete beim naechsten Start nur, dass sie
# etwas uebersprungen hat.
check_plugin() {
	local dir="$1"
	python3 - "$dir" <<'PY'
import json, os, sys

directory = sys.argv[1]
path = os.path.join(directory, "manifest.json")
if not os.path.isfile(path):
    raise SystemExit("manifest.json fehlt")
try:
    with open(path) as handle:
        data = json.load(handle)
except Exception as exc:
    raise SystemExit("manifest.json unlesbar: %s" % exc)

entry = str(data.get("entry") or "BarWidget.qml")
if not os.path.isfile(os.path.join(directory, entry)):
    raise SystemExit("Einstiegsdatei fehlt: %s" % entry)
print(data.get("name") or os.path.basename(directory))
PY
}

cmd_add() {
	local source="${1:?Quelle fehlt}"
	local name="${2:-}"

	if [ -z "$name" ]; then
		name="$(basename "$source")"
		name="${name%.git}"
		# Ein Repo heisst oft "nbshell-wetter" -- als Verzeichnisname reicht
		# der Teil dahinter, sonst steht in der Config "nbshell-nbshell-…".
		name="${name#nbshell-}"
	fi

	mkdir -p "$PLUGIN_DIR"
	local target="$PLUGIN_DIR/$name"
	if [ -e "$target" ]; then
		echo "'$name' ist schon da: $target" >&2
		echo "  entfernen: nbshell plugin remove $name" >&2
		return 1
	fi

	# In ein Nebenverzeichnis holen und erst nach der Pruefung an seinen Platz
	# schieben: ein halb geklontes oder falsches Repo soll nicht als Plugin
	# gelten, nur weil es im Ordner liegt.
	local staging
	staging="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-plugin.XXXXXX")" || return 1

	if [ -d "$source" ]; then
		# Bei einem Verzeichnis laesst sich vorher hineinsehen -- dann muss
		# nicht erst ein halbes Dateisystem kopiert werden, um am Ende
		# festzustellen, dass kein Manifest darin liegt.
		[ -f "$source/manifest.json" ] || {
			echo "Kein nbshell-Plugin: $source/manifest.json fehlt" >&2
			rm -rf "$staging"
			return 1
		}
		mkdir -p "$staging/holen"
		cp -a "$source/." "$staging/holen/" || {
			rm -rf "$staging"
			return 1
		}
	else
		command -v git >/dev/null 2>&1 || {
			echo "git fehlt -- ohne das laesst sich nichts klonen." >&2
			rm -rf "$staging"
			return 1
		}
		echo "Hole $source …"
		echo
		echo "ACHTUNG: ein Plugin ist QML, das IN der Shell laeuft. Es kann"
		echo "alles, was die Shell kann -- Dateien lesen, Programme starten."
		echo "Nur hereinholen, was du gelesen hast oder wem du traust."
		echo
		git clone --depth 1 -- "$source" "$staging/holen" >/dev/null 2>&1 || {
			echo "Klonen fehlgeschlagen: $source" >&2
			rm -rf "$staging"
			return 1
		}
	fi

	# .git bleibt liegen: nur damit kann `nbshell plugin update` das Plugin
	# spaeter nachziehen. Bei einem kopierten Verzeichnis gibt es keines, und
	# dann meldet `update` es einfach nicht.
	local label
	label="$(check_plugin "$staging/holen" 2>&1)" || {
		echo "Kein nbshell-Plugin: $label" >&2
		rm -rf "$staging"
		return 1
	}

	mv "$staging/holen" "$target" || {
		rm -rf "$staging"
		return 1
	}
	rm -rf "$staging"
	echo "$label -> $target"
	echo "Sichtbar wird es erst nach: nbshell restart"
	echo "In die Leiste kommt es ueber: nbshell modules  (oder Mod+Comma)"
}

cmd_remove() {
	local name="${1:?Name fehlt}"
	local target="$PLUGIN_DIR/$name"
	[ -d "$target" ] || {
		echo "'$name' nicht gefunden in $PLUGIN_DIR" >&2
		return 1
	}
	rm -rf "$target"
	echo "$name entfernt."
	echo 'Steht es noch in der Leiste, nimmt `nbshell modules` es heraus.'
}

cmd_update() {
	local only="${1:-}"
	local dir name found=0
	for dir in "$PLUGIN_DIR"/*/; do
		[ -d "$dir/.git" ] || continue
		name="$(basename "$dir")"
		[ -z "$only" ] || [ "$only" = "$name" ] || continue
		found=1
		printf '%-16s ' "$name"
		git -C "$dir" pull --ff-only 2>&1 | tail -1
	done
	[ $found -eq 1 ] || echo "Nichts zu aktualisieren (kein Plugin mit .git in $PLUGIN_DIR)."
}

case "${1:-list}" in
list) cmd_list ;;
dir)
	echo "$PLUGIN_DIR"
	;;
add)
	shift
	cmd_add "$@"
	;;
remove | rm)
	shift
	cmd_remove "$@"
	;;
update)
	shift
	cmd_update "$@"
	;;
*)
	echo "Aufruf: $(basename "$0") list|dir|add <quelle>|update [name]|remove <name>" >&2
	exit 2
	;;
esac
