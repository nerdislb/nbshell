import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    required property real rowWidth
    property real sectionSpacing: Theme.cellH * 0.2
    property bool active: false

    readonly property bool available: Phone.available

    width: root.rowWidth
    spacing: root.sectionSpacing

    onActiveChanged: {
        if (root.active)
            Phone.refresh();
    }

    Rule {
        rowWidth: root.rowWidth
        label: "PHONE MIRROR · NBPHONE"
    }

    Line {
        width: root.rowWidth
        text: {
            if (!Phone.available)
                return "nbphone is not installed — see github.com/nerdislb/nbphone";
            if (!Phone.scrcpyAvailable)
                return "scrcpy is missing — sudo pacman -S scrcpy";
            if (!Phone.connected)
                return "No ADB device — enable USB debugging or run nbphone connect";
            const name = Phone.model !== "" ? Phone.model : Phone.serial;
            return name + "  •  " + (Phone.wireless ? "WLAN" : "USB") + "  •  " + (Phone.mirroring ? "mirror running" : "ready");
        }
        color: Phone.connected && Phone.scrcpyAvailable ? Theme.fg : Theme.yellow
        wrapMode: Text.WordWrap
    }

    Row {
        spacing: Theme.cellW
        visible: Phone.available

        ActionButton {
            text: Phone.mirroring ? "Stop" : "Open"
            busy: Phone.busy
            enabled: Phone.mirroring || (Phone.connected && Phone.scrcpyAvailable)
            onTriggered: Phone.mirroring ? Phone.stop() : Phone.start(false)
        }

        ActionButton {
            text: "Private"
            busy: Phone.busy
            enabled: !Phone.mirroring && Phone.connected && Phone.scrcpyAvailable
            onTriggered: Phone.start(true)
        }

        ActionButton {
            text: "Refresh"
            enabled: !Phone.busy
            onTriggered: Phone.refresh()
        }

        ActionButton {
            text: Phone.wireless ? "WI-FI ✓" : "WI-FI"
            busy: Phone.busy
            enabled: !Phone.busy && !Phone.mirroring
            onTriggered: Phone.connectWireless()
        }
    }

    Line {
        visible: Phone.status !== ""
        width: root.rowWidth
        text: Phone.status
        color: Phone.status.indexOf("fehlt") !== -1 || Phone.status.indexOf("none") !== -1 ? Theme.yellow : Theme.green
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSize - 1
    }

    Rule {
        rowWidth: root.rowWidth
        label: "PHONE CAMERA · WEBCAM"
    }

    Line {
        width: root.rowWidth
        text: {
            if (!Phone.available)
                return "Install nbphone to use the phone camera";
            if (!Phone.webcamReady)
                return "One-time setup required for Phone Camera";
            if (Phone.cameraActive)
                return Phone.cameraMode.toUpperCase() + " CAMERA  •  LIVE  •  " + Phone.cameraDevice;
            if (!Phone.connected)
                return "Connect the phone through USB or wireless ADB";
            return "Phone Camera  •  " + Phone.cameraDevice + "  •  ready for OBS";
        }
        color: Phone.cameraActive ? Theme.green : (Phone.webcamReady && Phone.connected ? Theme.fg : Theme.yellow)
        wrapMode: Text.WordWrap
    }

    Row {
        spacing: Theme.cellW
        visible: Phone.available

        ActionButton {
            text: "Back"
            busy: Phone.busy
            enabled: Phone.connected && Phone.webcamReady && (!Phone.cameraActive || Phone.cameraMode !== "back")
            onTriggered: Phone.camera("back")
        }

        ActionButton {
            text: "Front"
            busy: Phone.busy
            enabled: Phone.connected && Phone.webcamReady && (!Phone.cameraActive || Phone.cameraMode !== "front")
            onTriggered: Phone.camera("front")
        }

        ActionButton {
            text: "Stop"
            busy: Phone.busy
            enabled: Phone.cameraActive
            onTriggered: Phone.camera("off")
        }

        ActionButton {
            text: "Preview"
            enabled: Phone.cameraActive && !Phone.busy
            onTriggered: Phone.previewCamera()
        }

        ActionButton {
            text: Phone.webcamReady ? "OBS" : "Setup"
            enabled: !Phone.busy
            onTriggered: Phone.webcamReady ? Phone.openObs() : Phone.setupCamera()
        }
    }
}
