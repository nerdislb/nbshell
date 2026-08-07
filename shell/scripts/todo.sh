#!/usr/bin/env bash
# Aufgabenliste -- der Teil, der ins Dateisystem greift.
#
#   todo.sh merge <datei>   Konfliktkopien zurueckfalten
#   todo.sh show  <datei>   die Liste als Text (fuers Terminal)
#
# Warum ueberhaupt: ein Dateiabgleich (Syncthing, Nextcloud, Dropbox) kann zwei
# gleichzeitige Aenderungen nicht aufloesen. Er behaelt eine Fassung und legt
# die andere als Kopie daneben:
#
#   todo.sync-conflict-20260807-101500-ABCDEFG.json
#
# Wer die Kopie liegen laesst, verliert alles, was nur in ihr steht. Hier wird
# sie nach derselben Regel zurueckgefaltet wie in Services/Todo.qml: gleiche
# `id` -> die groessere `updated` gewinnt. Danach ist die Kopie ueberfluessig
# und wird geloescht.
#
# Absichtlich KEIN `set -e`: eine kaputte Konfliktkopie soll die Liste nicht
# mit sich reissen.
set -uo pipefail

cmd="${1:-}"
file="${2:-}"

[ -n "$file" ] || { echo "Datei fehlt" >&2; exit 2; }

dir="$(dirname "$file")"
base="$(basename "$file")"
stem="${base%.json}"

mkdir -p "$dir" 2>/dev/null

case "$cmd" in
    merge)
        command -v jq >/dev/null 2>&1 || exit 0

        # Nichts da, nichts zu tun. `nullglob`, damit ein leeres Muster nicht
        # als Dateiname durchgereicht wird.
        shopt -s nullglob
        conflicts=("$dir/$stem".sync-conflict-*.json "$dir/$stem"-conflict-*.json)
        shopt -u nullglob
        [ ${#conflicts[@]} -gt 0 ] || exit 0

        [ -f "$file" ] || printf '[]\n' > "$file"

        tmp="$(mktemp "$dir/.$stem.XXXXXX")" || exit 0

        # `-s` liest alle Dateien als eine Liste von Listen, `add` haengt sie
        # aneinander. Danach je id der juengste Eintrag. Eintraege ohne id
        # fallen raus -- ohne sie laesst sich nichts zusammenfuehren.
        if jq -s '
              map(if type == "object" and (.items | type) == "array" then .items else . end)
            | map(select(type == "array")) | add
            | map(select(type == "object" and .id != null))
            | group_by(.id | tostring)
            | map(max_by(.updated // 0))
            | sort_by(.created // .id)
        ' "$file" "${conflicts[@]}" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            mv "$tmp" "$file"
            rm -f "${conflicts[@]}"
            echo "${#conflicts[@]} Konfliktkopie(n) zurueckgefaltet"
        else
            # Lieber die Kopie behalten als die Liste beschaedigen.
            rm -f "$tmp"
            echo "Konfliktkopie liess sich nicht lesen -- liegen gelassen: ${conflicts[*]}" >&2
        fi
        ;;

    show)
        [ -f "$file" ] || exit 0
        command -v jq >/dev/null 2>&1 || { cat "$file"; exit 0; }
        # Dieselbe Reihenfolge wie in der Shell: offene nach Eintragen, dann
        # die erledigten, zuletzt Abgehaktes oben. Sonst meint `todo done 3`
        # im Terminal eine andere Zeile als die Liste zeigt.
        jq -r '
              map(select(.deleted != true))
            | (map(select(.done | not)) | sort_by(.created // .id))
            + (map(select(.done))       | sort_by(-(.updated // 0)))
            | to_entries[]
            | "\(.key + 1 | tostring | (" " * (3 - length)) + .)  \(if .value.done then "[x]" else "[ ]" end)  \(.value.text)"
        ' "$file"
        ;;

    *)
        echo "todo.sh merge|show <datei>" >&2
        exit 2
        ;;
esac
