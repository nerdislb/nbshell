pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// nbshell itself updates only from published GitHub release artifacts. The
// helper verifies their SHA-256 checksum before the normal installer runs;
// user configuration, themes, plugins and data keep the installer's existing
// preservation guarantees. System packages remain a separate service.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/nbshell-update.py").toString().replace("file://", "")
    readonly property string channel: Config.value("shellUpdateChannel", "beta")
    readonly property string terminal: Config.value("terminal", "") || Quickshell.env("TERMINAL") || "xterm"
    property string current: ""
    property string latest: ""
    property string releaseUrl: ""
    property string releaseNotes: ""
    property string error: ""
    property bool checking: false
    property bool ready: false
    property bool updateAvailable: false
    property bool installable: false
    property bool prerelease: false

    function refresh() {
        if (checking)
            return;
        checking = true;
        checkProc.command = ["python3", root.script, "check", "--channel", root.channel];
        checkProc.running = true;
    }

    function install() {
        const line = "python3 '" + root.script + "' install --channel '" + root.channel
            + "'; code=$?; echo; read -n1 -r -p 'done — press any key to close the window'; exit $code";
        Quickshell.execDetached([root.terminal, "-e", "sh", "-c", line]);
    }

    function openNotes() {
        if (releaseUrl !== "")
            Quickshell.execDetached(["xdg-open", releaseUrl]);
    }

    Process {
        id: checkProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.current = data.current ?? "";
                    root.latest = data.latest ?? root.current;
                    root.releaseUrl = data.url ?? "";
                    root.releaseNotes = data.notes ?? "";
                    root.error = data.error ?? "";
                    root.updateAvailable = data.available === true;
                    root.installable = data.installable === true;
                    root.prerelease = data.prerelease === true;
                    root.ready = true;
                } catch (e) {
                    root.error = "Release check returned unreadable data";
                }
                root.checking = false;
            }
        }
        onExited: code => {
            if (code !== 0 && root.error === "")
                root.error = "Release check could not be started";
            root.checking = false;
        }
    }

    Timer {
        interval: 90000
        running: true
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 14400000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
