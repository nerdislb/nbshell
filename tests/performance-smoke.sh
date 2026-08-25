#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$ROOT/shell/shell.qml"

grep -Fq 'LazyLoader { active: Runtime.procsOpen; ProcessList {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.displayOpen; DisplayPanel {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.wallpaperOpen; WallpaperPicker {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.dashboardOpen; Dashboard {} }' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.agentCenterOpen; AgentCenter {} }' "$SHELL_ROOT"

# These surfaces and handlers must remain resident for immediate desktop
# feedback and so lazy surfaces can still be opened through IPC.
grep -Fq 'Bar {}' "$SHELL_ROOT"
grep -Fq 'Popups {}' "$SHELL_ROOT"
grep -Fq 'DesktopIpc {}' "$SHELL_ROOT"
grep -Fq 'MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000' "$ROOT/systemd/nbshell.service"

echo "Performance structure: OK"
