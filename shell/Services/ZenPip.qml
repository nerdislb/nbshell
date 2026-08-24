pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellDir + "/scripts/zen-pip.py"
    property bool active: false
    property bool floating: false
    property string windowId: ""
    property string sizeName: "small"
    property string cornerName: "bottom-right"

    function refresh() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    function updateFromCompositor() {
        const win = Compositor.windows.find(candidate => {
            const title = String(candidate.title || "").toLowerCase();
            const appId = String(candidate.app_id || "").toLowerCase();
            return (appId.startsWith("zen") || appId === "firefox")
                && (title.indexOf("picture-in-picture") >= 0 || title.indexOf("bild-im-bild") >= 0);
        });
        const nextId = win ? String(win.id) : "";
        root.active = nextId !== "";
        root.floating = Boolean(win && win.is_floating);
        if (nextId !== "" && nextId !== root.windowId) {
            root.windowId = nextId;
            root.run("apply");
        } else if (nextId === "") {
            root.windowId = "";
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
                    const newId = value.id === null ? "" : String(value.id);
                    if (newId !== "" && newId !== root.windowId) {
                        root.windowId = newId;
                        root.run("apply");
                    } else if (newId === "") {
                        root.windowId = "";
                    }
                } catch (e) {
                    root.active = false;
                    root.windowId = "";
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
        target: Compositor
        function onWindowsChanged() { root.updateFromCompositor(); }
    }

    Timer {
        id: refreshTimer
        interval: 180
        onTriggered: root.refresh()
    }
}
