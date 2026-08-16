#!/usr/bin/env bash
set -uo pipefail

event="Unknown"
for arg in "$@"; do
	case "$arg" in --event=*) event="${arg#--event=}" ;; esac
done

# Hook-Payload begrenzen und nur harmlose Anzeigefelder lesen. Die Ausgabe
# muss gültiges JSON bleiben, damit Codex nicht auf den Handler wartet.
payload=$(dd bs=4096 count=256 2>/dev/null)
cwd=$(jq -r '(.cwd? // .workspace? // "") | select(type == "string")' <<<"$payload" 2>/dev/null)
case "$event" in
PermissionRequest) title="Codex braucht eine Entscheidung" ;;
Stop) title="Codex ist fertig" ;;
*) title="Codex: $event" ;;
esac
detail="${cwd:-Agent-Sitzung}"
notify-send -a Codex -u normal -t 9000 "$title" "$detail" >/dev/null 2>&1 || true
printf '{}\n'
