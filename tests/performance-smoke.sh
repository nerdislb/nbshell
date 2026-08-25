#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$ROOT/shell/shell.qml"

grep -Fq 'LazyLoader { active: Runtime.procsOpen; ProcessList {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.displayOpen; DisplayPanel {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.wallpaperOpen; WallpaperPicker {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.dashboardOpen; Dashboard {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.agentCenterOpen; AgentCenter {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.storeOpen; StoreWindow {} }' "$SHELL_ROOT"
! grep -Fq 'void SearchProviders' "$SHELL_ROOT"

# These surfaces and handlers must remain resident for immediate desktop
# feedback and so lazy surfaces can still be opened through IPC.
grep -Fq 'Bar {}' "$SHELL_ROOT"
grep -Fq 'Popups {}' "$SHELL_ROOT"
grep -Fq 'DesktopIpc {}' "$SHELL_ROOT"
grep -Fq 'MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000' "$ROOT/systemd/nbshell.service"
grep -Fq 'UMask=0077' "$ROOT/systemd/nbshell.service"

# Package updates may require elevation, so their execution path must use
# fixed argv arrays and never reinterpret a display string as shell syntax.
if grep -Eq '^[[:space:]]*eval[[:space:]]' "$ROOT/shell/scripts/updates.sh"; then
    echo "Update execution must not use eval" >&2
    exit 1
fi

echo "Performance structure: OK"
