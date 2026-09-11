#!/usr/bin/env python3
"""Exercise the real lazy agenda service with a synthetic calendar backend."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='clock-agenda-') as folder:
    work = Path(folder)
    services = work / 'Services'
    services.mkdir()
    (services / 'CalendarAgenda.qml').write_text((ROOT / 'shell/Services/CalendarAgenda.qml').read_text())
    (services / 'qmldir').write_text('module Services\nsingleton CalendarAgenda 1.0 CalendarAgenda.qml\nsingleton Plugins 1.0 Plugins.qml\n')
    (services / 'Plugins.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property var enabledIds: ["io.github.nbshell.calendar"]
    function entry(id) { return {entryPoints: {panel: "%s/Panel.qml"}}; }
}
''' % work)
    (work / 'Service.qml').write_text('''import QtQuick
Item {
    property int calls: 0
    property bool busy: false
    property bool stale: false
    property string error: ""
    property var events: []
    property var calendars: [{key: "visible", visible: true}, {key: "hidden", visible: false}]
    property string start: ""
    property string end: ""
    function refresh(a,b) { calls++; start=a; end=b; }
}
''')
    (work / 'shell.qml').write_text('''import QtQuick
import Quickshell
import "Services"
ShellRoot {
    function check(ok, message) { if (!ok) { console.error("AGENDA_FAIL " + message); Qt.exit(1); } }
    Component.onCompleted: {
        check(CalendarAgenda.backend === null, "must remain idle before hover");
        CalendarAgenda.refresh();
    }
    Timer {
        interval: 250; running: true
        onTriggered: {
            const agenda = CalendarAgenda;
            check(!!agenda.backend, "backend loaded");
            check(agenda.backend.calls === 1, "one initial refresh");
            agenda.refresh(); agenda.refresh();
            check(agenda.backend.calls === 1, "repeat hover uses cache");
            check(agenda.backend.start === agenda.day(0).toISOString(), "local midnight start");
            check(agenda.backend.end === agenda.day(3).toISOString(), "three calendar days");
            agenda.backend.events = [
                {calendarKey:"visible",start:agenda.day(0).toISOString(),end:agenda.day(1).toISOString(),allDay:true,title:"Today only"},
                {calendarKey:"hidden",start:agenda.day(0).toISOString(),end:agenda.day(3).toISOString(),allDay:true,title:"Hidden"}
            ];
            check(agenda.eventsOn(agenda.day(0)).length === 1, "visible calendars only");
            check(agenda.eventsOn(agenda.day(1)).length === 0, "exclusive end");
            agenda.requestedDay = "previous day"; agenda.refresh();
            check(agenda.backend.calls === 2, "day rollover bypasses cache");
            Plugins.enabledIds = [];
            finish.start();
        }
    }
    Timer {
        id: finish; interval: 50
        onTriggered: {
            check(!CalendarAgenda.available && !CalendarAgenda.backend, "disable unloads backend");
            console.info("AGENDA_PASS"); Qt.quit();
        }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='', QML_DISABLE_DISK_CACHE='1')
    result = subprocess.run(['qs', '-p', str(work / 'shell.qml')], env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    if result.returncode or 'AGENDA_PASS' not in output or 'AGENDA_FAIL' in output:
        raise SystemExit(output)
    print('Clock agenda: lazy load, cache, three-day range, filtering, midnight and disable passed')
