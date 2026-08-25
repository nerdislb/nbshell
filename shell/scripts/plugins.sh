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
#   plugins.sh add <source>   -> git-Repo oder Verzeichnis hereinholen
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

		local entry
		entry="$(check_plugin "$dir" json 2>/dev/null)" || {
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

# Manifest v2:
#   schemaVersion: 2
#   kinds: ["bar-widget", "panel", "overlay", "service"]
#   entryPoints: { "barWidget": "BarWidget.qml", ... }
#
# Alte nbshell-Manifeste ohne schemaVersion bleiben als reine Bar-Widgets
# gueltig. Ein gesetztes schemaVersion muss dagegen exakt 2 sein -- damit wird
# ein Omarchy-Manifest nicht versehentlich als kompatibel behandelt, obwohl
# dessen QML andere Imports und einen anderen Shell-Kontext erwartet.
check_plugin() {
	local dir="$1"
	local mode="${2:-label}"
	python3 - "$dir" "$mode" <<'PY'
import configparser, json, os, re, sys

directory, mode = os.path.realpath(sys.argv[1]), sys.argv[2]
path = os.path.join(directory, "manifest.json")
if not os.path.isfile(path):
    raise SystemExit("manifest.json fehlt")
try:
    with open(path) as handle:
        data = json.load(handle)
except Exception as exc:
    raise SystemExit("manifest.json unlesbar: %s" % exc)

if not isinstance(data, dict):
    raise SystemExit("manifest.json muss ein Objekt sein")

ident = str(data.get("id") or os.path.basename(directory))
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", ident) or ".." in ident:
    raise SystemExit("ungueltige Plugin-ID: %s" % ident)
if ident.startswith("nbshell."):
    raise SystemExit("Plugin-ID nutzt den reservierten Namensraum nbshell.*")

# Kein Symlink darf aus dem als vertrauenswuerdig geladenen Plugin-Baum
# herauszeigen. .git selbst wird von der Shell nie geladen und bleibt fuer
# Updates erhalten.
for root, dirs, files in os.walk(directory, followlinks=False):
    dirs[:] = [name for name in dirs if name != ".git"]
    for name in dirs + files:
        candidate = os.path.join(root, name)
        if os.path.islink(candidate):
            raise SystemExit("Symlinks are not allowed in plugins: %s" % os.path.relpath(candidate, directory))

schema = data.get("schemaVersion")
if schema is None:
    kinds = ["bar-widget"]
    entry_points = {"barWidget": str(data.get("entry") or "BarWidget.qml")}
else:
    if schema != 2:
        raise SystemExit("unsupported schemaVersion (expected: 2)")
    for field in ("id", "name", "version", "kinds", "entryPoints"):
        if field not in data:
            raise SystemExit("Pflichtfeld fehlt: %s" % field)
    kinds = data.get("kinds")
    entry_points = data.get("entryPoints")
    if not isinstance(kinds, list) or not kinds:
        raise SystemExit("kinds must be a non-empty list")
    if not isinstance(entry_points, dict):
        raise SystemExit("entryPoints muss ein Objekt sein")

dependencies = data.get("dependencies", {})
if dependencies is None:
    dependencies = {}
if not isinstance(dependencies, dict):
    raise SystemExit("dependencies must be an object")
for field in ("commands", "packages"):
    values = dependencies.get(field, [])
    if not isinstance(values, list) or any(not isinstance(value, str) or not value for value in values):
        raise SystemExit("dependencies.%s must be a list of strings" % field)

hosts = data.get("hosts", [])
if hosts is None:
    hosts = []
if not isinstance(hosts, list) or any(host not in {"bar", "panel", "overlay", "window", "service"} for host in hosts):
    raise SystemExit("hosts must contain only bar, panel, overlay, window, or service")

allowed = {"bar-widget": "barWidget", "panel": "panel", "overlay": "overlay", "service": "service"}
if any(kind not in allowed for kind in kinds):
    raise SystemExit("unknown plugin type: %s" % ", ".join(str(k) for k in kinds if k not in allowed))
for kind in kinds:
    if allowed[kind] not in entry_points:
        raise SystemExit("Einstiegspunkt fuer %s fehlt: %s" % (kind, allowed[kind]))

resolved = {}
for key, value in entry_points.items():
    if not isinstance(value, str) or not value or os.path.isabs(value):
        raise SystemExit("Einstiegspunkt muss ein relativer Pfad sein: %s" % key)
    parts = value.replace("\\", "/").split("/")
    if ".." in parts:
        raise SystemExit("Einstiegspunkt verlaesst das Plugin: %s" % value)
    full = os.path.realpath(os.path.join(directory, value))
    if os.path.commonpath((directory, full)) != directory:
        raise SystemExit("Einstiegspunkt verlaesst das Plugin: %s" % value)
    if not os.path.isfile(full):
        raise SystemExit("Einstiegsdatei fehlt: %s" % value)
    resolved[key] = full

repository = str(data.get("repository") or data.get("homepage") or "")
git_managed = os.path.isdir(os.path.join(directory, ".git"))
if not repository and git_managed:
    config = configparser.ConfigParser()
    try:
        config.read(os.path.join(directory, ".git", "config"))
        repository = config.get('remote "origin"', "url", fallback="")
    except Exception:
        repository = ""

record = {
    "schemaVersion": schema or 1,
    "id": ident,
    "name": data.get("name") or ident,
    "description": data.get("description") or "",
    "category": data.get("category") or "Plugin",
    "kinds": kinds,
    "entryPoints": resolved,
    "entry": resolved.get("barWidget", ""),
    "dir": directory,
    "__sourceDir": directory,
    "version": str(data.get("version") or ""),
    "author": data.get("author") or "",
    "activation": data.get("activation") or "eager",
    "license": str(data.get("license") or ""),
    "repository": repository,
    "dependencies": dependencies,
    "barWidget": data.get("barWidget") if isinstance(data.get("barWidget"), dict) else {},
    "hosts": hosts,
    "managed": os.path.isfile(os.path.join(directory, ".nbshell-managed")),
    "gitManaged": git_managed,
}
if mode == "json":
    print(json.dumps(record, ensure_ascii=False))
else:
    print(record["name"])
PY
}

valid_name() {
	[[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != *'..'* ]]
}

cmd_add() {
	local source="${1:?source is required}"
	local name="${2:-}"

	if [ -z "$name" ]; then
		name="$(basename "$source")"
		name="${name%.git}"
		# Ein Repo heisst oft "nbshell-wetter" -- als Verzeichnisname reicht
		# der Teil dahinter, sonst steht in der Config "nbshell-nbshell-…".
		name="${name#nbshell-}"
	fi
	valid_name "$name" || {
		echo "Ungueltiger Plugin-Name: $name" >&2
		return 1
	}

	mkdir -p "$PLUGIN_DIR"
	local target="$PLUGIN_DIR/$name"
	if [ -e "$target" ]; then
		echo "'$name' ist schon da: $target" >&2
		echo "  remove: nbshell plugin remove $name" >&2
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
			echo "Not an nbshell plugin: $source/manifest.json is missing" >&2
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
			echo "git is missing -- cannot clone the plugin." >&2
			rm -rf "$staging"
			return 1
		}
		echo "Hole $source …"
		echo
		echo "WARNING: plugins are QML running INSIDE the shell. They can"
		echo "do everything the shell can do, including reading files and starting programs."
		echo "Only install code you reviewed or trust."
		echo
		git clone --depth 1 -- "$source" "$staging/holen" >/dev/null 2>&1 || {
			echo "Clone failed: $source" >&2
			rm -rf "$staging"
			return 1
		}
	fi

	# .git bleibt liegen: nur damit kann `nbshell plugin update` das Plugin
	# spaeter nachziehen. Bei einem kopierten Verzeichnis gibt es keines, und
	# dann meldet `update` es einfach nicht.
	local label
	label="$(check_plugin "$staging/holen" 2>&1)" || {
		echo "Not an nbshell plugin: $label" >&2
		rm -rf "$staging"
		return 1
	}

	mv "$staging/holen" "$target" || {
		rm -rf "$staging"
		return 1
	}
	rm -rf "$staging"
	echo "$label -> $target"
	echo "It becomes visible after: nbshell restart"
	echo "Add it to the bar with: nbshell modules  (or Mod+Comma)"
}

cmd_remove() {
	local name="${1:?Name fehlt}"
	valid_name "$name" || {
		echo "Ungueltiger Plugin-Name: $name" >&2
		return 1
	}
	local target="$PLUGIN_DIR/$name"
	[ -d "$target" ] || {
		echo "'$name' was not found in $PLUGIN_DIR" >&2
		return 1
	}
	if [ -f "$target/.nbshell-managed" ]; then
		echo "'$name' ships with nbshell and cannot be removed; disable it instead." >&2
		return 1
	fi

	# Remove every runtime and bar reference before deleting the checkout. A
	# stale id in the layout otherwise leaves a blank slot after the next scan.
	local manifest_id config
	manifest_id="$(check_plugin "$target" json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)" || manifest_id="$name"
	config="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/config.json"
	python3 - "$config" "$manifest_id" <<'PY'
import json, os, sys, tempfile

path, ident = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except FileNotFoundError:
    data = {}
if not isinstance(data, dict):
    raise SystemExit("config.json must be an object")
for key in ("enabledPlugins", "collapsedWidgets", "leftWidgets", "centerWidgets", "rightWidgets"):
    values = data.get(key, [])
    if isinstance(values, list):
        data[key] = [value for value in values if str(value) != ident]
settings = data.get("pluginSettings", {})
if isinstance(settings, dict):
    settings.pop(ident, None)
    data["pluginSettings"] = settings
directory = os.path.dirname(path)
os.makedirs(directory, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=".config.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
	rm -rf "$target"
	echo "$name removed."
}

cmd_update() {
	local only="${1:-}"
	if [ -n "$only" ] && ! valid_name "$only"; then
		echo "Ungueltiger Plugin-Name: $only" >&2
		return 1
	fi
	local dir name found=0
	for dir in "$PLUGIN_DIR"/*/; do
		[ -d "$dir/.git" ] || continue
		name="$(basename "$dir")"
		[ -z "$only" ] || [ "$only" = "$name" ] || continue
		found=1
		printf '%-16s ' "$name"

		# Den entfernten Stand erst in einem Wegwerfverzeichnis validieren.
		# Dadurch braucht es nach einem kaputten Update weder reset --hard noch
		# ein halb aktualisiertes Plugin in der laufenden Shell.
		local stage upstream candidate message
		stage="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-plugin-update.XXXXXX")" || continue
		if ! git -C "$dir" fetch --quiet; then
			echo "Fetch failed"
			rm -rf "$stage"
			continue
		fi
		upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || upstream="origin/$(git -C "$dir" branch --show-current)"
		candidate="$(git -C "$dir" rev-parse "$upstream" 2>/dev/null)" || {
			echo "no upstream"
			rm -rf "$stage"
			continue
		}
		git -C "$dir" archive "$candidate" | tar -x -C "$stage" || {
			echo "Validation copy failed"
			rm -rf "$stage"
			continue
		}
		message="$(check_plugin "$stage" label 2>&1)" || {
			echo "abgelehnt: $message"
			rm -rf "$stage"
			continue
		}
		rm -rf "$stage"
		git -C "$dir" merge --ff-only "$candidate" 2>&1 | tail -1
	done
	[ $found -eq 1 ] || echo "Nothing to update (no plugin with .git in $PLUGIN_DIR)."
}

cmd_diff() {
	local name="${1:?Plugin name is required}"
	valid_name "$name" || {
		echo "Invalid plugin name: $name" >&2
		return 1
	}
	local dir="$PLUGIN_DIR/$name"
	[ -d "$dir/.git" ] || {
		echo "'$name' is not a Git-managed plugin." >&2
		return 1
	}
	git -C "$dir" fetch --quiet || {
		echo "Could not fetch '$name'." >&2
		return 1
	}
	local upstream candidate current
	upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || upstream="origin/$(git -C "$dir" branch --show-current)"
	candidate="$(git -C "$dir" rev-parse "$upstream" 2>/dev/null)" || {
		echo "No upstream revision was found." >&2
		return 1
	}
	current="$(git -C "$dir" rev-parse HEAD)" || return 1
	if [ "$current" = "$candidate" ]; then
		echo "Already up to date."
		return 0
	fi
	printf 'COMMITS\n'
	git -C "$dir" log --oneline --no-decorate "$current..$candidate" | head -12
	printf '\nFILES\n'
	git -C "$dir" diff --stat "$current..$candidate" | tail -20
}

plugin_id_exists() {
	local wanted="$1" manifest dir id
	for manifest in "$PLUGIN_DIR"/*/manifest.json; do
		[ -f "$manifest" ] || continue
		dir="$(dirname "$manifest")"
		id="$(check_plugin "$dir" json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)" || continue
		[ "$id" = "$wanted" ] && return 0
	done
	return 1
}

set_enabled() {
	local id="$1" enabled="$2"
	valid_name "$id" || {
		echo "Ungueltige Plugin-ID: $id" >&2
		return 1
	}
	plugin_id_exists "$id" || {
		echo "Plugin not found or invalid: $id" >&2
		return 1
	}

	local config="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/config.json"
	mkdir -p "$(dirname "$config")"
	python3 - "$config" "$id" "$enabled" <<'PY'
import json, os, sys, tempfile

path, ident, enabled = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except FileNotFoundError:
    data = {}
if not isinstance(data, dict):
    raise SystemExit("config.json muss ein Objekt sein")
items = data.get("enabledPlugins", [])
if not isinstance(items, list):
    items = []
items = [str(item) for item in items if str(item) != ident]
if enabled:
    items.append(ident)
data["enabledPlugins"] = items
directory = os.path.dirname(path)
fd, temp = tempfile.mkstemp(prefix=".config.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
PY
	[ "$enabled" = 1 ] && echo "$id enabled" || echo "$id disabled"
}

case "${1:-list}" in
list) cmd_list ;;
validate)
	shift
	check_plugin "${1:?Plugin-Verzeichnis fehlt}" label
	;;
enable)
	shift
	set_enabled "${1:?Plugin-ID fehlt}" 1
	;;
disable)
	shift
	set_enabled "${1:?Plugin-ID fehlt}" 0
	;;
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
diff)
	shift
	cmd_diff "$@"
	;;
*)
echo "Usage: $(basename "$0") list|dir|validate <directory>|add <source>|enable <id>|disable <id>|diff <name>|update [name]|remove <name>" >&2
	exit 2
	;;
esac
