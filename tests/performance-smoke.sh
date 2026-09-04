#!/usr/bin/env bash
set -euo pipefail

assert_not_grep() {
    local status
    if grep "$@"; then
        printf 'Unexpected grep match: %s\n' "$*" >&2
        return 1
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            printf 'grep failed with status %s: %s\n' "$status" "$*" >&2
            return "$status"
        fi
    fi
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$ROOT/shell/shell.qml"

grep -Fq 'LazyLoader { active: Runtime.procsOpen; ProcessList {} }' "$SHELL_ROOT"
grep -Fq 'requested: Runtime.displayOpen' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.wallpaperOpen; WallpaperPicker {} }' "$SHELL_ROOT"
grep -Fq 'requested: Runtime.dashboardOpen' "$SHELL_ROOT"
grep -Fq 'requested: Runtime.agentCenterOpen' "$SHELL_ROOT"
grep -Fq 'LazyLoader { active: Runtime.storeOpen; StoreWindow {} }' "$SHELL_ROOT"
grep -Fq 'property bool mounted: false' "$ROOT/shell/Widgets/MotionLoader.qml"
assert_not_grep -Fq 'void SearchProviders' "$SHELL_ROOT"

# Disabling the decorative seconds ring must also disable its frame-rate clock
# updates. Agent transaction details are useful only while their lazy surface
# is visible and must not create helper processes on background status polls.
grep -Fq 'interval: root.showSecondsRing && !root.reducedMotion ? 33 : 1000' "$ROOT/shell/lock/LockView.qml"
grep -Fq 'if (root.overviewVisible && root.selectedJobId)' "$ROOT/shell/Services/Agents.qml"
grep -Fq 'if (root.overviewVisible && root.selectedBrainProposalId)' "$ROOT/shell/Services/Agents.qml"
grep -Fq 'interval: root.overviewVisible || root.completionAttention' "$ROOT/shell/Services/Agents.qml"
grep -Fq '|| Number(root.hermes.brainReviewing || 0) > 0 ? 5000 : 30000' "$ROOT/shell/Services/Agents.qml"
grep -Fq 'running: root.positionConsumers > 0 && root.players.some' "$ROOT/shell/Services/MediaService.qml"
grep -Fq 'MediaService.acquirePosition()' "$ROOT/shell/Widgets/NowPlaying.qml"
grep -Fq 'root.consumers > 0 && MediaService.playing' "$ROOT/shell/Services/Cava.qml"
grep -Fq 'Cava.acquire()' "$ROOT/shell/Bar/Widgets/Visualizer.qml"
grep -Fq 'sleep_timer = 3' "$ROOT/shell/Services/Cava.qml"
assert_not_grep -Fq 'void Phone.available' "$SHELL_ROOT"
assert_not_grep -Fq 'void Tailnet.available' "$SHELL_ROOT"
grep -Fq 'function onScreensChanged()' "$ROOT/shell/Services/Displays.qml"
grep -Fq 'Timer { interval: 300000; running: true; repeat: true; onTriggered: root.refresh() }' "$ROOT/shell/Services/Displays.qml"
grep -Fq 'interval: 60000' "$ROOT/shell/Services/Tailnet.qml"

# These surfaces and handlers must remain resident for immediate desktop
# feedback and so lazy surfaces can still be opened through IPC.
grep -Fq 'Bar {}' "$SHELL_ROOT"
grep -Fq 'Popups {}' "$SHELL_ROOT"
grep -Fq 'DesktopIpc {}' "$SHELL_ROOT"
grep -Fq 'MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000' "$ROOT/systemd/nbshell.service"
grep -Fq 'NBSHELL_DISABLE_HOT_RELOAD=1' "$ROOT/systemd/nbshell.service"
grep -Fq 'Quickshell.watchFiles = !shell.disableHotReload' "$SHELL_ROOT"
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
manifest = (root / "integrations/omawhatsapp/manifest.json").read_text(encoding="utf-8")
patch = (root / "integrations/omawhatsapp/nbshell-refresh.patch").read_text(encoding="utf-8")
composer_patch = (root / "integrations/omawhatsapp/nbshell-composer-scroll.patch").read_text(encoding="utf-8")
wheel_patch = (root / "integrations/omawhatsapp/nbshell-wheel-scroll.patch").read_text(encoding="utf-8")
wheel_handler = (root / "integrations/omawhatsapp/FastScrollHandler.qml").read_text(encoding="utf-8")
assert "source_revision=1f58d8da93565f020a63a61ad314c965cbcd8cdc" in setup
assert '"version": "0.11.2-nbshell.2"' in manifest
assert 'nbshell-refresh.patch' in setup
assert 'nbshell-composer-scroll.patch' in setup
assert 'nbshell-wheel-scroll.patch' in setup
assert 'FastScrollHandler.qml' in setup
assert 'omawhatsapp_assets.py' in setup
assert 'value in (old, "whatsapp")' in setup
assert "defer_shell_restart=1" in setup
assert "Shell restart deferred until the next external restart or login." in setup
assert composer_patch.count("+            ScrollView {") == 1
assert composer_patch.count("+                ScrollView {") == 1
assert composer_patch.count("ScrollBar.vertical.policy: ScrollBar.AsNeeded") == 2
assert composer_patch.count("width: composerScroll.availableWidth") == 2
assert wheel_patch.count("+              FastScrollHandler {") == 1
assert wheel_patch.count("+            FastScrollHandler {") == 3
assert wheel_patch.count("+          FastScrollHandler {") == 1
assert "Application.styleHints.wheelScrollLines" in wheel_handler
assert "acceptedDevices: PointerDevice.Mouse" in wheel_handler
assert "event.pixelDelta.y" in wheel_handler
removed_names = (
    "storeWatchProcess", "storeWatchers", "storeWatchRestart",
    "storeRefreshDebounce", "refreshFromStore", "storeRefreshPending",
    "storeDirectories",
)
removed_lines = [line for line in patch.splitlines() if line.startswith("-")]
for removed in removed_names:
    if removed == "storeWatchProcess" and "storeWatchers" in patch:
        continue
    assert any(removed in line for line in removed_lines), removed
assert not any("interval: 12000" in line for line in removed_lines)
for unit_name in ("wacli-sync.service", "wacli-sync@.service"):
    unit = (root / "integrations/omawhatsapp" / unit_name).read_text(encoding="utf-8")
    assert "--lock-wait 30s sync --follow" in unit
assert 'install -Dm644 "$runtime_shell/integrations/omawhatsapp/wacli-sync@.service"' in setup
assert 'status_json=$("$bin_dir/omawhatsapp" status)' in setup
assert 'wacli-sync@${account_name}.service' in setup
PY

# Hot refreshers must read procfs/runtime snapshots in-process. These paths
# used to create five child processes per network sample and one `cat` child
# per Pit Wall bridge sample respectively.
grep -Fq 'path: "/proc/net/route"' "$ROOT/shell/Services/Net.qml"
grep -Fq 'path: "/proc/net/dev"' "$ROOT/shell/Services/Net.qml"
assert_not_grep -Fq 'ip -o route show default' "$ROOT/shell/Services/Net.qml"
grep -Fq 'property var bridgeSnapshotFile: FileView {' "$ROOT/plugins/pit-wall/Service.qml"
assert_not_grep -Fq 'command: ["/usr/bin/cat", root.bridgeSnapshot]' "$ROOT/plugins/pit-wall/Service.qml"
node "$ROOT/tests/net-metrics.test.js"

# Package updates may require elevation, so their execution path must use
# fixed argv arrays and never reinterpret a display string as shell syntax.
if grep -Eq '^[[:space:]]*eval[[:space:]]' "$ROOT/shell/scripts/updates.sh"; then
    echo "Update execution must not use eval" >&2
    exit 1
fi

echo "Performance structure: OK"
