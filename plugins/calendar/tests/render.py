#!/usr/bin/env python3
"""Render real CalendarView with repository Qt test imports, no services/network."""
import json
import os
from pathlib import Path
import sys
from PySide6.QtCore import QUrl, QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

root = Path(__file__).resolve().parents[3]
work = Path(os.environ['CALENDAR_TEST_WORK'])
app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(str(work / 'imports'))
fixture = '''import QtQuick
import "file:%s/plugins/calendar"
import qs.Common
import qs.Widgets
PanelSurface {
    width: %s; height: %s
    QtObject {
        id: backend
        property var accounts: [{id:"a",name:"Synthetic iCloud",provider:"icloud"},{id:"g",name:"Synthetic Google",provider:"google"}]
        property var calendars: [{account:"a",id:"c",key:"a:c",name:"Personal",visible:true,writable:true},{account:"g",id:"r",key:"g:r",name:"Shared read-only",visible:true,writable:false}]
        property var events: [{account:"a",calendar:"c",calendarKey:"a:c",title:"Long synthetic event title to check clipping and keyboard navigation",start:"2026-09-11T10:00:00Z",end:"2026-09-11T11:00:00Z",allDay:false,blocked:false,writable:true}]
        property bool busy: false
        property bool stale: false
        property string error: ""
        property string loadedAt: "2026-09-11T09:00:00Z"
        property string authorizationUrl: ""
        signal changed()
        function run(value) {}
        function refresh(start,end) {}
        function cancel() {}
    }
    CalendarView {
        id: calendar
        anchors.fill: parent
        anchors.margins: Theme.panelPadding
        backend: backend
        anchor: new Date(2026,8,11)
        mode: "%s"
        page: "%s"
        Component.onCompleted: {
            %s
            forceActiveFocus();
        }
    }
}
'''
mode, page, width, height, name = sys.argv[1:6]
extra = ''
if page == 'editor': extra = 'edit(backend.events[0]);'
if page == 'error': page='calendar'; extra='backend.stale=true; backend.error="Synthetic network failure. Refresh to retry.";'
if page == 'empty': page='calendar'; extra='backend.accounts=[]; backend.calendars=[]; backend.events=[];'
if page == 'invalid': page='editor'; extra='edit(backend.events[0]); allDay=true; toggleAllDay();'
if page == 'disconnect': page='accounts'; extra='prepareDisconnect("a");'
if page == 'allday': page='editor'; extra='edit(backend.events[0]); toggleAllDay();'
if page == 'loading': page='calendar'; extra='backend.busy=true;'
path = work / 'render.qml'
path.write_text(fixture % (root, width, height, mode, page, extra))
view.setSource(QUrl.fromLocalFile(str(path)))
if view.status() == QQuickView.Error:
    print([e.toString() for e in view.errors()], flush=True)
    sys.exit(1)
view.show()
def capture():
    output=Path(os.environ['CALENDAR_TEST_OUTPUT']) / (name + '.png')
    output.parent.mkdir(exist_ok=True)
    if not view.grabWindow().save(str(output)): sys.exit(1)
    app.quit()
QTimer.singleShot(400,capture)
app.exec()
