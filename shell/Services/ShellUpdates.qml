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
    readonly property string compositorScript: Qt.resolvedUrl("../scripts/umbriel-update.py").toString().replace("file://", "")
    readonly property string channel: Config.value("shellUpdateChannel", "beta") === "stable" ? "stable" : "beta"
    readonly property string terminalScript: Qt.resolvedUrl("../scripts/update-terminal.sh").toString().replace("file://", "")
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
    property bool compositorChecking: false
    property bool compositorReady: false
    property bool compositorInstalled: false
    property bool compositorUpdateAvailable: false
    property bool compositorInstallable: false
    property string compositorBlockedReason: ""
    property string compositorError: ""
    property var compositorProjects: ({})

    readonly property bool anyUpdateAvailable: updateAvailable || compositorUpdateAvailable
    readonly property bool allCurrent: Updates.ready && ready && compositorReady
        && compositorInstalled && !Updates.checking && !checking && !compositorChecking
        && Updates.error === "" && error === "" && compositorError === ""
        && compositorBlockedReason === "" && !anyUpdateAvailable && Updates.count === 0
    readonly property string summary: {
        if (Updates.checking || checking || compositorChecking)
            return qsTr("Checking all sources …");
        if (Updates.error !== "" || error !== "" || compositorError !== "")
            return qsTr("Update check needs attention");
        if (compositorBlockedReason !== "")
            return qsTr("Umbriel automatic update paused");
        if (!Updates.ready || !ready || !compositorReady)
            return qsTr("Not all sources checked yet");
        if (!compositorInstalled)
            return qsTr("Umbriel sources unavailable");
        if (anyUpdateAvailable || Updates.count > 0)
            return qsTr("Updates available — review sources");
        return qsTr("System, nbshell and Umbriel current");
    }

    function launchUpdateTerminal(command, title) {
        // The installer deliberately restarts nbshell.service. A terminal
        // launched as a direct Quickshell child would share that cgroup and be
        // killed halfway through the update. Give it its own transient user
        // unit, and force a separate Ghostty process so the window remains in
        // that unit instead of being handed to a singleton process.
        const terminal = [root.terminal];
        const binary = String(root.terminal).split("/").pop();
        if (binary === "ghostty")
            terminal.push("--gtk-single-instance=false", "--class=dev.nerdi.nbshell.updater", "--title=" + title);
        terminal.push("-e");
        const unit = "nbshell-update-" + Date.now();
        Quickshell.execDetached([
            "systemd-run", "--user", "--quiet", "--collect",
            "--unit=" + unit, "--property=Type=exec", "--"
        ].concat(terminal, command));
    }

    function refresh() {
        if (checking)
            return;
        checking = true;
        checkProc.command = ["python3", root.script, "check", "--channel", root.channel];
        checkProc.running = true;
        if (!compositorChecking) {
            compositorChecking = true;
            compositorCheck.running = true;
        }
    }

    function install() {
        root.launchUpdateTerminal(["bash", root.terminalScript, "shell", root.channel], "nbshell Update");
    }

    function installCompositor() {
        if (compositorChecking || !compositorReady || !compositorInstallable
                || !compositorUpdateAvailable || compositorBlockedReason !== "" || compositorError !== "")
            return;
        root.launchUpdateTerminal(["bash", root.terminalScript, "compositor"], "Umbriel Update");
    }

    function installAll() {
        if (root.updateAvailable && root.installable && root.compositorUpdateAvailable && root.compositorInstallable) {
            root.launchUpdateTerminal(["bash", root.terminalScript, "desktop", root.channel], "Desktop Update");
        } else if (root.updateAvailable && root.installable) {
            root.install();
        } else if (root.compositorUpdateAvailable && root.compositorInstallable) {
            root.installCompositor();
        }
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
                    root.ready = false;
                    root.updateAvailable = false;
                    root.installable = false;
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

    Process {
        id: compositorCheck
        command: ["python3", root.compositorScript, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.compositorInstalled = data.installed === true;
                    root.compositorUpdateAvailable = data.available === true;
                    root.compositorInstallable = data.installable === true;
                    root.compositorBlockedReason = data.blockedReason ?? "";
                    root.compositorProjects = data.projects ?? ({});
                    root.compositorError = data.error ?? "";
                    root.compositorReady = true;
                } catch (e) {
                    root.compositorReady = false;
                    root.compositorUpdateAvailable = false;
                    root.compositorInstallable = false;
                    root.compositorBlockedReason = "";
                    root.compositorError = "Umbriel update check returned unreadable data";
                }
                root.compositorChecking = false;
            }
        }
        onExited: code => {
            if (code !== 0 && root.compositorError === "")
                root.compositorError = "Umbriel update check could not be started";
            root.compositorChecking = false;
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
