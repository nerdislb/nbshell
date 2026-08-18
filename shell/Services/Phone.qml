pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Android-Spiegelung ueber das eigenstaendige `nbphone`-Werkzeug.
// Die Shell kennt nur dessen stabile JSON-Schnittstelle; ADB- und scrcpy-
// Details bleiben damit ausserhalb der Oberflaeche testbar.
Singleton {
    id: root

    readonly property string tool: Quickshell.env("HOME") + "/.local/bin/nbphone"

    property bool available: false
    property bool adbAvailable: false
    property bool scrcpyAvailable: false
    property bool connected: false
    property bool wireless: false
    property bool mirroring: false
    property string serial: ""
    property string model: ""
    property string status: ""
    property bool busy: false

    function refresh() {
        statusProc.command = [root.tool, "status", "--json"];
        statusProc.running = true;
    }

    function run(action, extra) {
        if (root.busy)
            return;
        var command = [root.tool, action];
        if (extra)
            command = command.concat(extra);
        actionProc.command = command;
        root.busy = true;
        actionProc.running = true;
    }

    function start(privateMode) {
        root.run("start", privateMode ? ["--private"] : []);
    }

    function stop() {
        root.run("stop", []);
    }

    function connectWireless() {
        root.run("wireless", []);
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 5000
        running: root.available || root.connected || root.mirroring
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.available = true;
                    root.adbAvailable = Boolean(data.available && data.available.adb);
                    root.scrcpyAvailable = Boolean(data.available && data.available.scrcpy);
                    root.connected = Boolean(data.connected);
                    root.wireless = Boolean(data.wireless);
                    root.mirroring = Boolean(data.mirroring);
                    const selected = data.selected || null;
                    root.serial = selected ? String(selected.serial || "") : "";
                    root.model = selected ? String(selected.model || "") : "";
                } catch (error) {
                    root.available = false;
                    root.connected = false;
                    root.wireless = false;
                    root.mirroring = false;
                }
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const message = String(text || "").trim();
                if (message !== "")
                    root.status = message;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = String(text || "").trim();
                if (message !== "")
                    root.status = message.split("\n")[0];
            }
        }
        onExited: {
            root.busy = false;
            root.refresh();
            clearStatus.restart();
        }
    }

    Timer {
        id: clearStatus
        interval: 5000
        onTriggered: root.status = ""
    }
}
