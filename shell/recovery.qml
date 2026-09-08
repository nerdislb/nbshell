//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell.recovery

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import "Widgets/FocusScroll.js" as FocusScroll

// Deliberately independent of the main shell's services and plugin loaders.
ShellRoot {
    id: root
    property string token: ""
    property string message: "Checking configuration…"
    property var backups: []
    property string action: "inspect"
    property string configPath: ""
    readonly property string scriptDir: Qt.resolvedUrl("scripts/").toString().replace("file://", "")

    function reveal(item) {
        Qt.callLater(() => {
            const top = item.mapToItem(content, 0, 0).y;
            viewport.contentY = FocusScroll.contentYForFocus(top, item.height, viewport.contentY,
                viewport.height, viewport.contentHeight, Theme.spaceSm);
        });
    }

    function run(action, argument) {
        if (worker.running)
            return;
        root.action = action;
        if (action === "preview")
            root.token = "";
        worker.command = action === "retry"
            ? ["timeout", "--kill-after=2", "20", "python3", scriptDir + "config-migrations.py", "apply", "--json"]
            : ["timeout", "--kill-after=2", "20", "python3", scriptDir + "config-repair.py", action].concat(argument ? [argument] : []);
        worker.running = true;
    }
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        run("inspect", "");
    }

    Process {
        id: worker
        property string result: ""
        onStarted: result = ""
        stdout: StdioCollector { onStreamFinished: worker.result = text }
        onExited: code => {
            let response;
            try { response = JSON.parse(result); }
            catch (e) { root.message = "Could not confirm the operation. Check again before retrying."; return; }
            if (root.action === "inspect") {
                root.backups = response.backups || [];
                root.configPath = response.configPath || "";
                root.token = response.pendingRepair?.token || "";
                root.message = root.token ? "An interrupted repair is pending. Resume the reviewed restoration below."
                    : response.ok ? "Configuration is valid. Retry startup to load it."
                    : (response.error || "Configuration needs attention.");
            } else if (!response.ok) {
                root.message = response.error || "Configuration needs attention.";
            } else if (root.action === "preview") {
                root.token = response.token;
                root.message = response.message + "\nCandidate: " + response.candidate
                    + "\nSettings: " + response.settingCount + "\nOriginals: " + response.backup;
                restore.forceActiveFocus();
            } else if (root.action === "apply") {
                root.token = "";
                root.message = response.message + "\nOriginals: " + response.backup;
                retry.forceActiveFocus();
            } else if (root.action === "retry") {
                Quickshell.execDetached(["nbshell", "restart"]);
                root.message = "Starting nbshell… You can close this recovery window.";
            }
        }
    }

    FloatingWindow {
        id: window
        title: "nbshell configuration recovery"
        visible: true
        implicitWidth: Theme.cellW * 72
        implicitHeight: Theme.rowHeight * 24
        color: Theme.panelSurface

        Flickable {
            id: viewport
            anchors.fill: parent
            anchors.margins: Theme.panelPadding
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Keys.onEscapePressed: Quickshell.quit()
            Column {
                id: content
                width: viewport.width
                spacing: Theme.spaceMd
                PanelHead {
                    rowWidth: content.width
                    title: "Configuration recovery"
                    subtitle: "Existing files are preserved until you restore a reviewed candidate"
                }
                Line {
                    width: parent.width
                    text: root.message
                    wrapMode: Text.Wrap
                    color: Theme.readable(Theme.fg, Theme.panelSurface)
                }
                Flow {
                    width: parent.width
                    spacing: Theme.spaceSm
                    ControlButton {
                        onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        id: retry
                        text: "Retry startup"
                        enabled: !worker.running && !root.token
                        onTriggered: root.run("retry", "")
                        Component.onCompleted: forceActiveFocus()
                    }
                    ControlButton {
                        onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        text: "Check again"
                        enabled: !worker.running
                        onTriggered: root.run("inspect", "")
                    }
                }
                Line {
                    width: parent.width
                    text: "Correct config.json in your editor, then retry startup. Or enter a known-good JSON file below, preview it, and explicitly restore it. Restoration replaces all settings with that candidate."
                    wrapMode: Text.Wrap
                }
                TextField {
                    onActiveFocusChanged: if (activeFocus) root.reveal(this)
                    id: candidate
                    width: parent.width
                    placeholderText: "Absolute path to a configuration or migration backup"
                    accessibleName: "Configuration candidate path"
                    enabled: !worker.running && !root.token
                    onAccepted: if (text.trim()) root.run("preview", text.trim())
                }
                Flow {
                    width: parent.width
                    spacing: Theme.spaceSm
                    ControlButton {
                        onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        text: "Preview candidate"
                        enabled: !worker.running && !root.token && candidate.text.trim() !== ""
                        onTriggered: root.run("preview", candidate.text.trim())
                    }
                    ControlButton {
                        onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        text: "Preview current file"
                        enabled: !worker.running && !root.token && root.configPath !== ""
                        onTriggered: {
                            candidate.text = root.configPath;
                            root.run("preview", root.configPath);
                        }
                    }
                    ControlButton {
                        onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        id: restore
                        text: "Restore reviewed candidate"
                        danger: true
                        enabled: !worker.running && root.token !== ""
                        onTriggered: root.run("apply", root.token)
                    }
                }
                Line {
                    width: parent.width
                    text: root.backups.length ? "Available migration backups:\n" + root.backups.join("\n")
                        : "No migration backups found. Select your own saved copy or repair the file in your editor."
                    wrapMode: Text.Wrap
                    color: Theme.fgDim
                }
            }
        }
    }
}
