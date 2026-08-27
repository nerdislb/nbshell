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
grep -Fq 'Slice=session.slice' "$ROOT/systemd/nbshell.service"
grep -Fq 'Slice=session.slice' "$ROOT/systemd/nbshell-umbriel-resume-guard.service"
grep -Fq 'ManagedOOMMemoryPressureLimit=60%' "$ROOT/shell/scripts/memory-guard.sh"
grep -Fq 'ManagedOOMMemoryPressureDurationSec=20s' "$ROOT/shell/scripts/memory-guard.sh"
grep -Fq '"systemd-run", "--user", "--quiet", "--collect"' "$ROOT/shell/Services/ShellUpdates.qml"
grep -Fq '"--gtk-single-instance=false"' "$ROOT/shell/Services/ShellUpdates.qml"

# OmaWhatsApp used to watch SQLite's WAL and immediately query the same database.
# Opening the read-only query touched WAL/SHM again and created several short
# Python processes per second. The packaged source patch removes that feedback
# loop while retaining the bounded 12-second refresh timer.
python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
setup = (root / "shell/scripts/omawhatsapp.sh").read_text(encoding="utf-8")
patch = (root / "integrations/omawhatsapp/nbshell-refresh.patch").read_text(encoding="utf-8")
assert 'nbshell-refresh.patch' in setup
for removed in ("storeWatchProcess", "storeRefreshDebounce", "refreshFromStore", "storeRefreshPending"):
    assert f"-    id: {removed}" in patch or f"-  function {removed}" in patch or f"-  property bool {removed}" in patch
assert "   Timer {\n     interval: 12000" in patch
PY

# Package updates may require elevation, so their execution path must use
# fixed argv arrays and never reinterpret a display string as shell syntax.
if grep -Eq '^[[:space:]]*eval[[:space:]]' "$ROOT/shell/scripts/updates.sh"; then
    echo "Update execution must not use eval" >&2
    exit 1
fi

echo "Performance structure: OK"
