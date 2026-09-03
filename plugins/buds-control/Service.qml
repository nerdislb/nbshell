import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string helper: Qt.resolvedUrl("budsctl.py").toString().replace("file://", "")
    readonly property var device: devices.length > 0 ? devices[0] : null
    readonly property bool connected: device !== null
    readonly property bool controlsAvailable: connected
        && device.state.toggle1Visible === true
        && device.modes.length > 0
    readonly property int currentMode: controlsAvailable ? Number(device.state.toggle1State || 0) : 0
    readonly property int batteryLevel: connected ? Number(device.state.computedBatteryLevel || 0) : 0

    property bool backendAvailable: false
    property bool loading: false
    property bool actionPending: false
    property bool actionSucceeded: false
    property bool actionConfirmed: false
    property int pendingMode: 0
    property string backend: ""
    property string version: ""
    property string statusText: ""
    property string errorText: ""
    property var devices: []

    function modeLabel(value) {
        if (!device)
            return "Disconnected";
        const option = device.modes.find(row => Number(row.value) === Number(value));
        return option ? String(option.label) : "Unknown";
    }

    function battery(label, levelKey, statusKey) {
        if (!device)
            return { "label": label, "level": 0, "status": "not-reported", "available": false };
        const state = device.state;
        const status = String(state[statusKey] || "not-reported");
        return {
            "label": label,
            "level": Number(state[levelKey] || 0),
            "status": status,
            "available": status !== "not-reported" && status !== "disconnected"
        };
    }

    function refresh() {
        if (refreshProc.running)
            return;
        loading = true;
        refreshProc.command = ["python3", helper, "status"];
        refreshProc.running = true;
    }

    function applyStatus(text) {
        let result = null;
        try {
            result = JSON.parse(String(text || "{}"));
        } catch (error) {
            backendAvailable = false;
            devices = [];
            errorText = "BudsLink returned unreadable data.";
            loading = false;
            return;
        }
        backendAvailable = result.available === true;
        backend = String(result.backend || "");
        devices = Array.isArray(result.devices) ? result.devices : [];
        version = String(result.version || "");
        errorText = result.ok === true ? "" : String(result.error || "BudsLink is not available.");
        loading = false;
    }

    function setMode(value) {
        if (!controlsAvailable || actionProc.running)
            return;
        const selected = Number(value);
        if (selected < 1 || selected > 4 || selected === currentMode)
            return;
        actionPending = true;
        actionSucceeded = false;
        actionConfirmed = false;
        pendingMode = selected;
        statusText = "Applying " + modeLabel(selected) + "…";
        actionProc.command = ["python3", helper, "mode", String(device.path), String(selected)];
        actionProc.running = true;
    }

    function openBudsLink() {
        Quickshell.execDetached(["flatpak", "run", "io.github.maniacx.BudsLink"]);
    }

    function openInstallPage() {
        Quickshell.execDetached(["xdg-open", "https://flathub.org/apps/io.github.maniacx.BudsLink"]);
    }

    Component.onCompleted: refresh()

    Process {
        id: refreshProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyStatus(text)
        }
        onExited: function(code) {
            root.loading = false;
            if (code !== 0 && root.errorText === "")
                root.errorText = "BudsLink could not be reached.";
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const result = JSON.parse(String(text || "{}"));
                    root.actionSucceeded = result.ok === true;
                    root.actionConfirmed = result.confirmed === true;
                    if (!root.actionSucceeded)
                        root.errorText = String(result.error || "The mode could not be changed.");
                } catch (error) {
                    root.actionSucceeded = false;
                    root.errorText = "The mode change returned unreadable data.";
                }
            }
        }
        onExited: function(code) {
            root.actionPending = false;
            if (code === 0 && root.actionSucceeded)
                root.statusText = root.actionConfirmed ? "Noise control confirmed." : "Noise control request sent.";
            else
                root.statusText = "Noise control could not be changed.";
            settle.restart();
            statusClear.restart();
        }
    }

    Timer {
        id: settle
        interval: 350
        onTriggered: root.refresh()
    }

    Timer {
        id: statusClear
        interval: 4000
        onTriggered: root.statusText = ""
    }

    Timer {
        interval: 110000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: signalDebounce
        interval: 250
        onTriggered: root.refresh()
    }

    Process {
        command: ["dbus-monitor", "--session", "type='signal',path_namespace='/io/github/maniacx/BudsLink'"]
        running: true
        stdout: SplitParser {
            onRead: signalDebounce.restart()
        }
    }
}
