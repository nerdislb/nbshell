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
#   plugins.sh update [name] [--yes]  -> geklonte Plugins nachziehen (fragt
#                                        ohne --yes vor dem Merge)
#   plugins.sh remove <name>  -> wieder entfernen
set -uo pipefail

PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/plugins"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$SCRIPT_DIR/../templates/plugins"
DESIGN_CHECK="$SCRIPT_DIR/plugin-design-check.py"

cmd_list() {
	local first=1
	declare -A seen_ids=()
	printf '['
	local manifest dir ident
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
		ident="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$entry")" || continue
		if [ -n "${seen_ids[$ident]:-}" ]; then
			echo "nbshell/plugins: duplicate plugin ID '$ident' in '$dir' and '${seen_ids[$ident]}' — skipped" >&2
			continue
		fi
		seen_ids[$ident]="$dir"

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

plugin_id_for() {
	check_plugin "$1" json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
}

plugin_id_conflict() {
	local wanted="$1" except="${2:-}" manifest dir id
	for manifest in "$PLUGIN_DIR"/*/manifest.json; do
		[ -f "$manifest" ] || continue
		dir="$(dirname "$manifest")"
		[ -z "$except" ] || [ "$(realpath -m -- "$dir")" != "$(realpath -m -- "$except")" ] || continue
		id="$(plugin_id_for "$dir")" || continue
		if [ "$id" = "$wanted" ]; then
			printf '%s\n' "$dir"
			return 0
		fi
	done
	return 1
}

cmd_design_check() {
	local directory="${1:?Plugin directory is required}"
	shift
	python3 "$DESIGN_CHECK" "$directory" "$@"
}

cmd_new() {
	local id="${1:?Plugin ID is required}"
	shift
	valid_name "$id" || {
		echo "Invalid plugin ID: $id" >&2
		return 1
	}
	[[ "$id" != nbshell.* ]] || {
		echo "Plugin ID uses the reserved nbshell.* namespace: $id" >&2
		return 1
	}

	local kind="bar-widget" output="" name="" author=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--kind)
			kind="${2:?--kind requires a value}"
			shift 2
			;;
		--output)
			output="${2:?--output requires a directory}"
			shift 2
			;;
		--name)
			name="${2:?--name requires a value}"
			shift 2
			;;
		--author)
			author="${2:?--author requires a value}"
			shift 2
			;;
		*)
			echo "Unknown plugin new option: $1" >&2
			return 2
			;;
		esac
	done
	case "$kind" in
	bar-widget | panel | overlay | service) ;;
	*)
		echo "Unsupported plugin kind: $kind" >&2
		echo "Choose: bar-widget, panel, overlay, or service" >&2
		return 2
		;;
	esac

	local slug="${id##*.}"
	[ -n "$output" ] || output="$PWD/$slug"
	[ ! -e "$output" ] || {
		echo "Output already exists: $output" >&2
		return 1
	}
	if [ -z "$name" ]; then
		name="$(python3 - "$slug" <<'PY'
import re, sys
print(" ".join(word.capitalize() for word in re.split(r"[-_]", sys.argv[1]) if word))
PY
)"
	fi
	[ -n "$author" ] || author="$(git config --get user.name 2>/dev/null || true)"
	[ -n "$author" ] || author="Your name"

	[ -d "$TEMPLATE_ROOT/$kind" ] || {
		echo "Plugin template is missing: $TEMPLATE_ROOT/$kind" >&2
		return 1
	}
	mkdir -p "$(dirname "$output")" || return 1
	local stage
	stage="$(mktemp -d "$(dirname "$output")/.nbshell-plugin-new.XXXXXX")" || return 1
	trap 'rm -rf -- "$stage"; exit 130' INT TERM HUP
	cp -a "$TEMPLATE_ROOT/$kind/." "$stage/" || {
		rm -rf "$stage"
		return 1
	}
	cp "$TEMPLATE_ROOT/README.md" "$stage/README.md" || {
		rm -rf "$stage"
		return 1
	}
	python3 - "$stage" "$id" "$name" "$author" "$slug" <<'PY'
import json, pathlib, sys

directory = pathlib.Path(sys.argv[1])
raw_values = {
    "{{ID}}": sys.argv[2],
    "{{NAME}}": sys.argv[3],
    "{{AUTHOR}}": sys.argv[4],
    "{{SLUG}}": sys.argv[5],
}
for path in directory.rglob("*"):
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    string_literal = path.suffix in {".json", ".qml"}
    for marker, value in raw_values.items():
        replacement = json.dumps(value, ensure_ascii=False)[1:-1] if string_literal else value
        text = text.replace(marker, replacement)
    path.write_text(text, encoding="utf-8")
PY

	check_plugin "$stage" label >/dev/null || {
		rm -rf "$stage"
		return 1
	}
	cmd_design_check "$stage" --strict >/dev/null || {
		echo "Generated plugin failed its design contract." >&2
		cmd_design_check "$stage" --strict >&2 || true
		rm -rf "$stage"
		return 1
	}
	mv -T -- "$stage" "$output" || {
		rm -rf "$stage"
		return 1
	}
	trap - INT TERM HUP
	printf '%s\n' "Created $name ($kind) at $output"
	printf '%s\n' "Next: cd '$output' && nbshell plugin validate . && nbshell plugin design-check . --strict"
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
		# A local copy is deliberately unmanaged. Never retain repository-local
		# hooks or Git configuration that could execute later during `update`.
		rm -rf -- "$staging/holen/.git"
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
	local label record ident conflict
	record="$(check_plugin "$staging/holen" json 2>&1)" || {
		echo "Not an nbshell plugin: $record" >&2
		rm -rf "$staging"
		return 1
	}
	ident="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$record")" || {
		rm -rf "$staging"
		return 1
	}
	if conflict="$(plugin_id_conflict "$ident")"; then
		echo "Plugin ID '$ident' is already installed at $conflict" >&2
		rm -rf "$staging"
		return 1
	fi
	if ! cmd_design_check "$staging/holen" --strict >/dev/null; then
		echo "Plugin rejected by the strict nbshell design contract:" >&2
		cmd_design_check "$staging/holen" --strict >&2 || true
		rm -rf "$staging"
		return 1
	fi
	label="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' <<<"$record")" || {
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

print_incoming_summary() {
	local dir="$1" current="$2" candidate="$3"
	printf 'COMMITS\n'
	git -C "$dir" log --oneline --no-decorate "$current..$candidate" | head -12
	printf '\nFILES\n'
	git -C "$dir" diff --stat "$current..$candidate" | tail -20
}

cmd_update() {
	local only="" assume_yes=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--yes | -y) assume_yes=1 ;;
		--*) echo "Unknown option: $1" >&2; return 2 ;;
		*)
			[ -z "$only" ] || { echo "Usage: plugins.sh update [name] [--yes]" >&2; return 2; }
			only="$1"
			;;
		esac
		shift
	done
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

		# Validate the fetched revision in a disposable directory before the
		# installed checkout can move.
		local stage upstream candidate current message current_id candidate_id conflict
		stage="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-plugin-update.XXXXXX")" || continue
		if ! git -c core.hooksPath=/dev/null -C "$dir" fetch --quiet; then
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
		current="$(git -C "$dir" rev-parse HEAD)" || {
			rm -rf "$stage"
			continue
		}
		if [ "$current" = "$candidate" ]; then
			echo "up to date"
			rm -rf "$stage"
			continue
		fi
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
		current_id="$(plugin_id_for "$dir")" || {
			echo "installed manifest is invalid"
			rm -rf "$stage"
			continue
		}
		candidate_id="$(plugin_id_for "$stage")" || {
			echo "candidate manifest is invalid"
			rm -rf "$stage"
			continue
		}
		if [ "$candidate_id" != "$current_id" ]; then
			echo "rejected: plugin ID changed from '$current_id' to '$candidate_id'"
			rm -rf "$stage"
			continue
		fi
		if conflict="$(plugin_id_conflict "$candidate_id" "$dir")"; then
			echo "rejected: plugin ID '$candidate_id' is also installed at $conflict"
			rm -rf "$stage"
			continue
		fi
		if ! cmd_design_check "$stage" --strict >/dev/null; then
			echo "rejected: strict design contract failed"
			cmd_design_check "$stage" --strict >&2 || true
			rm -rf "$stage"
			continue
		fi
		rm -rf "$stage"

		echo
		print_incoming_summary "$dir" "$current" "$candidate"
		if [ "$assume_yes" != 1 ]; then
			local reply=""
			if { exec 3<>/dev/tty; } 2>/dev/null; then
				printf '\nMerge %s after reviewing these changes? [y/N] ' "$name" >&3
				read -r reply <&3 || reply=""
				exec 3>&-
			fi
			case "$reply" in
			y | Y | yes | Yes) ;;
			*)
				echo "Skipped '$name': not confirmed. Review with 'plugin diff $name', then re-run 'plugin update $name --yes' or confirm interactively." >&2
				continue
				;;
			esac
		fi
		printf '%-16s ' "$name"
		git -c core.hooksPath=/dev/null -C "$dir" merge --ff-only "$candidate" 2>&1 | tail -1
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
	git -c core.hooksPath=/dev/null -C "$dir" fetch --quiet || {
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
	print_incoming_summary "$dir" "$current" "$candidate"
}

plugin_id_exists() {
	plugin_id_conflict "$1" >/dev/null
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
new)
	shift
	cmd_new "$@"
	;;
validate)
	shift
	check_plugin "${1:?Plugin-Verzeichnis fehlt}" label
	;;
design-check | audit)
	shift
	cmd_design_check "$@"
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
echo "Usage: $(basename "$0") list|dir|new <id> [--kind kind] [--output dir]|validate <directory>|design-check <directory> [--strict]|add <source>|enable <id>|disable <id>|diff <name>|update [name] [--yes]|remove <name>" >&2
	exit 2
	;;
esac
