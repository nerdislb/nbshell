#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/shell/scripts/kill-process.py"
child=""

cleanup() {
    if [[ -n $child ]] && kill -0 "$child" 2>/dev/null; then
        kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
}
trap cleanup EXIT

sleep 60 &
child=$!
started="$(ps -p "$child" -o lstart=)"
python3 "$HELPER" "$child" "$started" 15
if wait "$child" 2>/dev/null; then
    echo "Process helper did not terminate its exact target" >&2
    exit 1
else
    status=$?
    test "$status" -eq 143
fi
child=""

sleep 60 &
child=$!
started="$(ps -p "$child" -o lstart=)"
if python3 "$HELPER" "$child" "Fri Jan 01 00:00:00 1999" 15; then
    echo "Process helper accepted a mismatched process identity" >&2
    exit 1
fi
kill -0 "$child"

kill "$child"
wait "$child" 2>/dev/null || true
child=""

echo "Process selection identity and pidfd signaling: OK"
