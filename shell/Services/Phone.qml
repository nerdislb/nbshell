pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Android mirroring and phone-camera streaming through the standalone
// `nbphone` tool. The shell only consumes its stable JSON interface.
Singleton {
    id: root

    readonly property string tool: Quickshell.env("HOME") + "/.local/bin/nbphone"

    property bool available: false
    property bool adbAvailable: false
    property bool scrcpyAvailable: false
    property bool connected: false
    property bool wireless: false
    property bool mirroring: false
    property bool webcamReady: false
    property bool cameraActive: false
    property string cameraMode: "off"
    property string cameraDevice: "/dev/video10"
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

    function camera(mode) {
        // A camera restart invalidates the current V4L2 reader. Close the
        // managed preview first; the user can reopen it after the new stream
        // reports active.
        Quickshell.execDetached(["systemctl", "--user", "stop", "nbphone-preview.service"]);
        root.run("camera", [mode]);
    }

    function setupCamera() {
        Quickshell.execDetached([Apps.terminal, "-e", "sh", "-lc",
            root.tool + " camera setup; printf '\nPress Enter to close… '; read -r _"]);
    }

    function openObs() {
        Quickshell.execDetached(["obs"]);
    }

    function previewCamera() {
        if (!root.cameraActive)
            return;
        Quickshell.execDetached([
            "systemd-run",
            "--user",
            "--unit=nbphone-preview",
            "--collect",
            "--property=TimeoutStopSec=2s",
            "mpv",
            "--title=Phone Camera Preview",
            "--profile=low-latency",
            "--untimed",
            "--no-audio",
            "--autofit=48%x48%",
            "av://v4l2:" + root.cameraDevice
        ]);
    }

    Component.onCompleted: refresh()

    Timer {
        // Keep active mirroring responsive. Merely having nbphone installed
        // must not run a Python/ADB status check every five seconds forever.
        interval: root.connected || root.mirroring || root.cameraActive ? 5000 : 60000
        running: root.available || root.connected || root.mirroring || root.cameraActive
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
                    const camera = data.camera || {};
                    root.webcamReady = Boolean(camera.ready);
                    root.cameraActive = Boolean(camera.active);
                    root.cameraMode = String(camera.mode || "off");
                    root.cameraDevice = String(camera.device || "/dev/video10");
                    const selected = data.selected || null;
                    root.serial = selected ? String(selected.serial || "") : "";
                    root.model = selected ? String(selected.model || "") : "";
                } catch (error) {
                    root.available = false;
                    root.connected = false;
                    root.wireless = false;
                    root.mirroring = false;
                    root.webcamReady = false;
                    root.cameraActive = false;
                    root.cameraMode = "off";
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
