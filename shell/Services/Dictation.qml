pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voxtype/state"
    property string state: "idle"
    readonly property bool active: state === "recording" || state === "transcribing"
    readonly property string label: state === "recording" ? "LISTENING" : (state === "transcribing" ? "TRANSCRIBING" : "")

    function toggle() {
        Quickshell.execDetached(["voxtype", "record", "toggle"]);
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.state = String(text()).trim() || "idle"
        onLoadFailed: root.state = "idle"
    }
}
