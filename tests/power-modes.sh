#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$ROOT/shell/Services/PowerService.qml"
BATTERY="$ROOT/shell/Bar/Widgets/Battery.qml"
IPC="$ROOT/shell/Ipc/DeviceIpc.qml"

grep -Fq '{ "label": "Power saver", "value": "powersave" }' "$SERVICE"
grep -Fq '{ "label": "Balanced", "value": "balanced" }' "$SERVICE"
grep -Fq '{ "label": "Performance", "value": "throughput-performance" }' "$SERVICE"
grep -Fq 'options: PowerService.profileOptions' "$BATTERY"
grep -Fq 'value": PowerService.activeProfileLabel' "$BATTERY"
grep -Fq 'unknown mode; use powersaver, balanced, or performance' "$IPC"
! grep -Fq 'more profiles: tuned-adm list' "$BATTERY"

echo "Three power modes and aliases: OK"
