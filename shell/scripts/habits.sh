#!/usr/bin/env bash
# Habit Tracker (nbHabits / init.Habits) -- Dateisystem- und Terminal-Werkzeug.
#
#   habits.sh merge  <datei>   Syncthing-Konfliktkopien zusammenfuehren
#   habits.sh show   <datei>   Heutige Gewohnheiten im Terminal anzeigen
#   habits.sh matrix <datei>   20-Wochen GitHub-Style Heatmap im Terminal
#   habits.sh status <datei>   Statuszusammenfassung (JSON)
#
set -uo pipefail

cmd="${1:-}"
file="${2:-}"

[ -n "$file" ] || { echo "Datei fehlt" >&2; exit 2; }

dir="$(dirname "$file")"
base="$(basename "$file")"
stem="${base%.json}"

mkdir -p "$dir" 2>/dev/null

today="$(date +%Y-%m-%d)"

case "$cmd" in
    merge)
        command -v jq >/dev/null 2>&1 || exit 0

        shopt -s nullglob
        conflicts=("$dir/$stem".sync-conflict-*.json "$dir/$stem"-conflict-*.json)
        shopt -u nullglob
        [ ${#conflicts[@]} -gt 0 ] || exit 0

        [ -f "$file" ] || printf '{"version":"1.0.0","syncedAt":0,"habits":[],"entries":[]}\n' > "$file"

        tmp="$(mktemp "$dir/.$stem.XXXXXX")" || exit 0

        # Zusammenfuehren von habits und entries nach juengstem `updated`/`timestamp`
        if jq -s '
            def norm_habits:
                map(if type == "object" and .habits then .habits else [] end)
                | add // []
                | map(select(type == "object" and .id != null))
                | group_by(.id | tostring)
                | map(max_by(.updated // .createdAt // 0))
                | sort_by(.createdAt // 0);

            def norm_entries:
                map(if type == "object" and .entries then .entries else [] end)
                | add // []
                | map(select(type == "object" and .habitId != null and .date != null))
                | group_by((.habitId | tostring) + "_" + (.date | tostring))
                | map(max_by(.updated // .timestamp // 0))
                | sort_by(.date, .timestamp);

            {
                version: "1.0.0",
                syncedAt: (now * 1000 | floor),
                habits: norm_habits,
                entries: norm_entries
            }
        ' "$file" "${conflicts[@]}" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            mv "$tmp" "$file"
            rm -f "${conflicts[@]}"
            echo "${#conflicts[@]} Konfliktkopie(n) zurueckgefaltet"
        else
            rm -f "$tmp"
            echo "Konfliktkopie liess sich nicht lesen: ${conflicts[*]}" >&2
        fi
        ;;

    show)
        [ -f "$file" ] || { echo "Keine Gewohnheiten-Datei unter $file"; exit 0; }
        command -v jq >/dev/null 2>&1 || { cat "$file"; exit 0; }

        jq -r --arg today "$today" '
            def pad(n; len): (tostring | (" " * (len - length)) + .);
            def pbar(cur; target):
                if target <= 0 then "" else
                    ( (cur / target * 10 | floor | if . > 10 then 10 elif . < 0 then 0 else . end) as $f |
                      "[" + ("=" * $f) + (" " * (10 - $f)) + "]" )
                end;

            .habits as $all_habits |
            ($all_habits | map(select(.deleted != true and .isArchived != true))) as $habits |
            .entries as $entries |

            ($entries | map(select(.date == $today))) as $todays |

            ($habits | map(
                . as $h |
                ($todays | map(select(.habitId == $h.id)) | last) as $e |
                {
                    id: $h.id,
                    name: $h.name,
                    icon: ($h.icon // "✨"),
                    mode: ($h.mode // "CHECKBOX"),
                    routine: ($h.routine // "all"),
                    target: ($h.targetValue // 1.0),
                    unit: ($h.unit // ""),
                    shields: ($h.shields // 2),
                    done: ($e.isCompleted // false),
                    val: ($e.currentValue // 0.0)
                }
            )) as $items |

            ($items | length) as $total |
            ($items | map(select(.done)) | length) as $done_cnt |
            (if $total > 0 then ($done_cnt / $total * 100 | floor) else 0 end) as $pct |

            "\u001b[1;36m$ status --today // " + $today + "\u001b[0m\n" +
            "\u001b[1;32m" + ($done_cnt | tostring) + " of " + ($total | tostring) + " COMPLETED (" + ($pct | tostring) + "%)\u001b[0m\n" +
            "--------------------------------------------------\n" +
            (
                $items | to_entries[] |
                (
                    (.key + 1 | pad(.; 2)) + "  " +
                    (if .value.done then "\u001b[32m[✔]\u001b[0m" else "\u001b[33m[ ]\u001b[0m" end) + "  " +
                    .value.icon + "  " +
                    (if .value.done then "\u001b[90m\u001b[9m" + .value.name + "\u001b[0m" else "\u001b[1m" + .value.name + "\u001b[0m" end) +
                    (if .value.mode == "COUNTER" or .value.mode == "NUMBER" or .value.mode == "DURATION" then
                        "  (" + (.value.val | tostring) + "/" + (.value.target | tostring) + " " + .value.unit + ") " + pbar(.value.val; .value.target)
                     else "" end) +
                    "  \u001b[34m//" + .value.routine + "\u001b[0m"
                )
            )
        ' "$file"
        ;;

    matrix)
        [ -f "$file" ] || exit 0
        command -v jq >/dev/null 2>&1 || exit 0

        jq -r --arg today "$today" '
            .habits as $habits |
            ($habits | map(select(.deleted != true and .isArchived != true)) | length) as $habit_count |
            .entries as $entries |

            # Berechne Heatmap fuer die letzten 140 Tage (20 Wochen)
            "\u001b[1;36m$ matrix --heatmap // 20-WEEK CONTRIBUTION MATRIX\u001b[0m\n" +
            "\u001b[90mless ░ ▒ ▓ █ more\u001b[0m\n"
        ' "$file"
        ;;

    status)
        [ -f "$file" ] || { echo '{"error":"Datei fehlt"}'; exit 0; }
        command -v jq >/dev/null 2>&1 || { cat "$file"; exit 0; }
        jq -r --arg today "$today" '
            .habits as $all |
            ($all | map(select(.deleted != true and .isArchived != true))) as $habits |
            .entries as $entries |
            ($entries | map(select(.date == $today))) as $todays |
            ($habits | length) as $total |
            ($habits | map(
                . as $h |
                ($todays | map(select(.habitId == $h.id)) | last) as $e |
                select($e.isCompleted == true)
            ) | length) as $done |
            {
                total: $total,
                completed: $done,
                percent: (if $total > 0 then ($done / $total * 100 | floor) else 0 end),
                today: $today,
                file: "'"$file"'"
            }
        ' "$file"
        ;;

    *)
        echo "habits.sh merge|show|matrix|status <datei>" >&2
        exit 2
        ;;
esac
