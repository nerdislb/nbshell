pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellDir + "/scripts/zen-pip.py"
    property bool active: false
    property bool floating: false
    property int windowId: -1
    property string sizeName: "small"
    property string cornerName: "bottom-right"

    function refresh() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function run(action) {
        actionProc.command = [root.helper, action];
        actionProc.running = true;
    }

    Process {
        id: statusProc
        command: [root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.active = value.active === true;
                    root.floating = value.floating === true;
                    root.sizeName = value.sizeName || "small";
                    root.cornerName = value.cornerName || "bottom-right";
                    const newId = value.id === null ? -1 : Number(value.id);
                    if (newId >= 0 && newId !== root.windowId) {
                        root.windowId = newId;
                        root.run("apply");
                    } else if (newId < 0) {
                        root.windowId = -1;
                    }
                } catch (e) {
                    root.active = false;
                    root.windowId = -1;
                }
            }
        }
    }

    Process {
        id: actionProc
        onExited: refreshTimer.restart()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshTimer
        interval: 180
        onTriggered: root.refresh()
    }
}
