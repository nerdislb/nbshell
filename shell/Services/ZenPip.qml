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

    function updateFromNiri() {
        const win = Niri.windows.find(candidate => {
            const title = String(candidate.title || "").toLowerCase();
            const appId = String(candidate.app_id || "").toLowerCase();
            return (appId.startsWith("zen") || appId === "firefox")
                && (title.indexOf("picture-in-picture") >= 0 || title.indexOf("bild-im-bild") >= 0);
        });
        const nextId = win ? Number(win.id) : -1;
        root.active = nextId >= 0;
        root.floating = Boolean(win && win.is_floating);
        if (nextId >= 0 && nextId !== root.windowId) {
            root.windowId = nextId;
            root.run("apply");
        } else if (nextId < 0) {
            root.windowId = -1;
        }
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

    Component.onCompleted: root.refresh()

    Connections {
        target: Niri
        function onWindowsChanged() { root.updateFromNiri(); }
    }

    Timer {
        id: refreshTimer
        interval: 180
        onTriggered: root.refresh()
    }
}
