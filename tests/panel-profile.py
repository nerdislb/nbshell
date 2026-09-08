#!/usr/bin/env python3
"""Private panel render/readback profiling used by wayland-lifecycle.py."""
import io
import hashlib
import json
import re
import statistics
import subprocess
import time
from pathlib import Path

PANELS = [('settings', 'Settings/SettingsWindow.qml'), ('modules', 'Settings/ModulesMenu.qml'),
          ('agents', 'Menu/AgentCenter.qml'), ('dashboard', 'Menu/Dashboard.qml'),
          ('plugin-manager', 'Settings/PluginDeveloper.qml')]


def instrument(directory, asynchronous):
    digest = hashlib.sha256()
    for path in sorted(directory.rglob('*.qml')):
        digest.update(str(path.relative_to(directory)).encode() + b'\0' + path.read_bytes())
    Path('/work/panel-source.json').write_text(json.dumps({'baselineQmlSha256': digest.hexdigest()}))
    root = directory / 'shell.qml'
    source = root.read_text()
    end = source.rfind('}')
    source = source[:end] + '''
    property double profileStarted: 0
    property double profileLastBeat: 0
    property double profileMaxGap: 0
    property bool profileMeasuring: false
    Timer {
        interval: 1; repeat: true; running: true
        onTriggered: {
            const now = Date.now();
            if (shell.profileMeasuring)
                shell.profileMaxGap = Math.max(shell.profileMaxGap, now - shell.profileLastBeat);
            shell.profileLastBeat = now;
        }
    }
    IpcHandler {
        target: "panelProfile"
        function open(panel: string): string {
            shell.profileMaxGap = 0;
            shell.profileStarted = Date.now();
            shell.profileLastBeat = shell.profileStarted;
            shell.profileMeasuring = true;
            if (panel === "settings") Runtime.settingsOpen = true;
            else if (panel === "modules") Runtime.modulesOpen = true;
            else if (panel === "agents") Runtime.agentCenterOpen = true;
            else if (panel === "dashboard") Runtime.dashboardOpen = true;
            else Runtime.pluginDeveloperOpen = true;
            return String(shell.profileStarted);
        }
        function finish(): string {
            shell.profileMeasuring = false;
            return JSON.stringify({maxHeartbeatGapMs: shell.profileMaxGap});
        }
    }
''' + source[end:]
    root.write_text(source)
    if asynchronous:
        loader = directory / 'Widgets/MotionLoader.qml'
        source = loader.read_text()
        if source.count('asynchronous: false') != 1:
            raise RuntimeError('Expected exactly one synchronous MotionLoader setting')
        loader.write_text(source.replace('asynchronous: false', 'asynchronous: true'))
    for name, filename in PANELS:
        path = directory / filename
        text = path.read_text(); end = text.rfind('}')
        text = text[:end] + '''
    // Each cycle destroys its MotionLoader item. This flag belongs to that
    // new PanelWindow instance, and its contentItem owns a private QQuickWindow.
    property bool profileFrameRecorded: false
    Connections {
        target: root.contentItem.Window.window
        function onFrameSwapped() {
            if (!root.profileFrameRecorded) {
                root.profileFrameRecorded = true;
                console.info("PANEL_FIRST_SWAP NAME " + Date.now());
            }
        }
    }
'''.replace('NAME', name) + text[end:]
        path.write_text(text)


def measure(ipc, wait, mapped, cycles, asynchronous):
    from PIL import Image, ImageChops

    def capture():
        result = subprocess.run(['grim', '-'], capture_output=True, check=True, timeout=10)
        picture = Image.open(io.BytesIO(result.stdout)).convert('RGB')
        width, height = picture.size
        return picture.crop((width // 4, height // 4, width * 3 // 4, height * 3 // 4))

    rows = []
    for panel, _ in PANELS:
        for cycle in range(cycles):
            baseline = capture()
            log_start = len(Path('/work/shell.log').read_text())
            started = time.monotonic()
            request_ms = int(ipc('panelProfile', 'open', panel))
            deadline = time.monotonic() + 10
            while True:
                picture = capture()
                # A changed central region confirms visible overlay output.
                difference = ImageChops.difference(baseline, picture)
                changed = sum(max(pixel) > 8 for pixel in difference.getdata())
                if changed >= 100:
                    visible_ms = (time.monotonic() - started) * 1000
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError('No visible panel pixels: ' + panel)
            wait(lambda: bool(re.search(r'PANEL_FIRST_SWAP ' + panel + r' (\d+)', Path('/work/shell.log').read_text()[log_start:])), 'Qt first frame')
            log = Path('/work/shell.log').read_text()[log_start:]
            swap_ms = int(re.search(r'PANEL_FIRST_SWAP ' + panel + r' (\d+)', log).group(1)) - request_ms
            if not 0 <= swap_ms < 10000:
                raise RuntimeError('Invalid or stale first-swap timestamp')
            row = {'panel': panel, 'cycle': cycle, 'qtFirstSwapMs': swap_ms,
                   'visibleReadbackUpperBoundMs': visible_ms, **json.loads(ipc('panelProfile', 'finish'))}
            rows.append(row)
            if cycle == 0:
                time.sleep(0.25)
                subprocess.run(['grim', '/work/' + panel + '.png'], check=True, timeout=10)
            ipc('lifecycleProbe', 'closePanels')
            wait(lambda: not mapped(panel), 'panel unmap')
            time.sleep(0.1)
    summary = {}
    for panel, _ in PANELS:
        summary[panel] = {}
        for metric in ['qtFirstSwapMs', 'visibleReadbackUpperBoundMs', 'maxHeartbeatGapMs']:
            values = sorted(row[metric] for row in rows if row['panel'] == panel)
            summary[panel][metric] = {'p50': statistics.median(values), 'p95': values[max(0, int(len(values) * .95 + .999) - 1)], 'max': max(values)}
    events = {panel: len(re.findall(r'PANEL_FIRST_SWAP ' + panel + r' \d+', Path('/work/shell.log').read_text())) for panel, _ in PANELS}
    if any(count != cycles for count in events.values()):
        raise RuntimeError('Expected one distinct first-swap event for every created panel instance')
    result = {'asynchronousExperiment': asynchronous, 'firstSwapEvents': events,
              **json.loads(Path('/work/panel-source.json').read_text()),
              'measurement': 'Qt frameSwapped callback from in-process request; screenshot-confirmed visible central overlay is an upper bound including IPC/readback; Qt heartbeat gaps include timer/render scheduling and are not exact CPU blockage. Private software-rendered Wayland, not physical monitor scanout.',
              'cycles': rows, 'summary': summary}
    Path('/work/panel-profile.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result['summary'], indent=2))
