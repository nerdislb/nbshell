#!/usr/bin/env bash
set -uo pipefail

pane="${1:-}"
agent="${2:-Agent}"
event="${3:-finished}"
project="${4:-}"

[[ -n $pane ]] || exit 0

case "$event" in
  decision)
    title="$agent needs your input"
    urgency="critical"
    ;;
  *)
    title="$agent finished"
    urgency="normal"
    ;;
esac

detail="${project:-Agent session}"
action=$(notify-send \
  --app-name="nbshell Agents" \
  --urgency="$urgency" \
  --expire-time=15000 \
  --action="default=Open session" \
  "$title" "$detail" 2>/dev/null) || exit 0

if [[ $action == "default" ]] && command -v herdr >/dev/null 2>&1; then
  herdr agent focus "$pane" >/dev/null 2>&1 || true
fi
