#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="$(python3 "$ROOT/shell/scripts/system-report.py" --json)"

printf '%s' "$REPORT" | jq -e '
    .schemaVersion == 1 and
    (.desktop.backend | type == "string") and
    (.extensions.installed | type == "array") and
    (.tools | type == "object") and
    (.services.memoryGuard.protected | type == "boolean") and
    (has("clipboard") | not) and
    (has("notifications") | not) and
    (has("windows") | not)
' >/dev/null

grep -Fq 'fileDelay' "$ROOT/shell/Services/SearchProviders.qml"
grep -Fq 'root.mode === "file"' "$ROOT/shell/Launcher/Launcher.qml"
grep -Fq 'Runtime.storeOpen' "$ROOT/shell/Store/StoreWindow.qml"
grep -Fq 'wallpaperCount' "$ROOT/shell/Store/StoreWindow.qml"
grep -Fq 'terminalPreview' "$ROOT/shell/Store/StoreWindow.qml"
bash -n "$ROOT/shell/scripts/demo.sh"

echo "System report, launcher providers, store, and demo workflow: OK"
