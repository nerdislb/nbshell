import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Services
import qs.Common
import qs.Widgets

ShellRoot {
    id: root
    readonly property string store: Quickshell.env("NBSHELL_GAMING_STORE") || "battlenet"
    readonly property string workerPath: decodeURIComponent(Qt.resolvedUrl(root.store === "minecraft" ? "scripts/gaming_minecraft.py" : "scripts/gaming_faugus.py").toString().replace("file://", ""))
    property string action: Quickshell.env("NBSHELL_GAMING_ACTION") || "install"
    property string phase: "checking"
    property string message: "Preparing gaming setup…"
    property string detail: ""
    property bool cancelling: false
    property string jobToken: ""
    readonly property bool busy: worker.running
    readonly property string storeTitle: ({battlenet: "Battle.net", gog: "GOG Galaxy", epic: "Epic Games", minecraft: "Minecraft"})[store] || "Gaming"

    function cancel() {
        if (!root.busy) { Qt.quit(); return; }
        if (root.cancelling) return;
        root.cancelling = true;
        root.message = "Cancelling safely…";
        if (root.jobToken) cancelWorker.running = true;
    }

    Process {
        id: worker
        command: ["python3", root.workerPath, root.action, root.store]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = JSON.parse(data);
                    if (event.phase === "started") {
                        root.jobToken = event.job;
                        if (root.cancelling) cancelWorker.running = true;
                        return;
                    }
                    root.phase = event.phase;
                    if (!root.cancelling) root.message = event.message;
                    root.detail = event.total > 0
                        ? Math.floor(event.received * 100 / event.total) + "% downloaded"
                        : (event.detail || "");
                } catch (error) { /* Ignore non-protocol library output. */ }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("Gaming worker: " + data) }
        onExited: (exitCode, exitStatus) => {
            if (root.phase === "launched") { Qt.quit(); return; }
            if (root.cancelling) {
                root.phase = "error";
                root.message = "Cancelled. Installation files were kept for retry.";
            } else if (exitCode !== 0 && root.phase !== "error") {
                root.phase = "error";
                root.message = "Setup stopped unexpectedly. See the gaming install log.";
            }
            if (root.phase !== "done") root.detail = "";
            if (exitCode === 0 && root.action === "install" && root.phase === "done" && root.store !== "minecraft") {
                Qt.callLater(() => {
                    root.action = "launch";
                    root.jobToken = "";
                    root.phase = "launching";
                    root.message = "Starting " + root.storeTitle + "…";
                    worker.running = true;
                });
            }
        }
    }
    Process {
        id: cancelWorker
        command: ["python3", root.workerPath, "cancel", root.store, "--job", root.jobToken]
    }
    PanelWindow {
        id: window
        visible: root.phase !== "launched"
        screen: Compositor.focusedScreen
        implicitWidth: Math.min(Theme.cellW * 64, (screen ? screen.width : 800) - Theme.spaceXl * 2)
        implicitHeight: content.implicitHeight + Theme.panelPadding * 2
        color: Theme.panelSurface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "nbshell:gaming-setup"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        PanelSurface { anchors.fill: parent }
        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Theme.panelPadding
            spacing: Theme.spaceMd
            focus: true
            Keys.onEscapePressed: root.cancel()
            Text {
                text: root.storeTitle
                textFormat: Text.PlainText
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitle
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            Text {
                text: root.message
                textFormat: Text.PlainText
                color: root.phase === "error" ? Theme.readable(Theme.red, Theme.panelSurface, 4.5) : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            Text {
                text: root.detail || (root.busy ? "Installer windows stay in the background." : "")
                textFormat: Text.PlainText
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontCaption
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }
            RowLayout {
                spacing: Theme.spaceSm
                ControlButton {
                    text: root.busy ? (root.cancelling ? "Cancelling…" : "Cancel") : "Close"
                    enabled: !root.cancelling || !root.busy
                    onTriggered: root.cancel()
                }
                ControlButton {
                    visible: !root.busy && root.phase === "done"
                    text: "Open " + root.storeTitle
                    onTriggered: {
                        root.action = "launch";
                        root.jobToken = "";
                        root.phase = "launching";
                        root.message = "Starting " + root.storeTitle + "…";
                        worker.running = true;
                    }
                }
                ControlButton {
                    visible: !root.busy && root.phase === "error"
                    text: "Retry"
                    onTriggered: {
                        root.cancelling = false;
                        root.jobToken = "";
                        root.phase = "checking";
                        root.message = "Preparing gaming setup…";
                        worker.running = true;
                    }
                }
            }
        }
    }
}
