#!/usr/bin/env bash
set -uo pipefail

event="Unknown"
for arg in "$@"; do
	case "$arg" in --event=*) event="${arg#--event=}" ;; esac
done

# Limit the hook payload and only read harmless display fields. Output must
# remain valid JSON so Codex never waits for the handler.
payload=$(dd bs=4096 count=256 2>/dev/null)
cwd=$(jq -r '(.cwd? // .workspace? // "") | select(type == "string")' <<<"$payload" 2>/dev/null)
case "$event" in
PermissionRequest) kind="decision" ;;
Stop) kind="finished" ;;
*) kind="finished" ;;
esac
helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-notify.sh"
if [[ -n ${HERDR_PANE_ID:-} && -x $helper ]]; then
	nohup "$helper" "$HERDR_PANE_ID" "Codex" "$kind" "${cwd:-Agent session}" \
		>/dev/null 2>&1 </dev/null &
else
	notify-send -a Codex -u normal -t 9000 "Codex ${kind}" "${cwd:-Agent session}" >/dev/null 2>&1 || true
fi
printf '{}\n'
