import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    property var groups: []
    property bool loading: false
    property string error: ""
    property string expandedId: ""
    readonly property string script: Qt.resolvedUrl("../scripts/system-hub.py").toString().replace("file://", "")

    visible: Runtime.hubOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:hub"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function refresh() {
        if (status.running) return;
        loading = true;
        error = "";
        status.running = true;
    }

    function run(command) {
        if (!command) return;
        Runtime.hubOpen = false;
        if (command.indexOf("detached:") === 0)
            Quickshell.execDetached(["sh", "-c", command.slice(9)]);
        else if (command.indexOf("xdg-open ") === 0)
            Quickshell.execDetached(["sh", "-c", command]);
        else
            Quickshell.execDetached([Apps.terminal, "-e", "sh", "-c", command + "; printf '\n[Enter] schliesst … '; read -r _"]);
    }

    onVisibleChanged: if (visible) { refresh(); keys.forceActiveFocus(); }

    Process {
        id: status
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try { root.groups = JSON.parse(text).groups ?? []; }
                catch (e) { root.error = "Status konnte nicht gelesen werden"; root.groups = []; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.error = String(text).trim() }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: Runtime.hubOpen = false
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { root.refresh(); event.accepted = true; }
        }
        MouseArea { anchors.fill: parent; onClicked: Runtime.hubOpen = false }

        Rectangle {
            width: Math.min(parent.width - Theme.cellW * 8, Theme.cellW * 96)
            height: Math.min(parent.height - Theme.cellH * 8, Theme.cellH * 42)
            anchors.centerIn: parent
            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.5

                Row {
                    width: parent.width
                    Line { width: parent.width - reload.width; text: Icons.matrix + "  SYSTEM & PLUGINS"; color: Theme.fg; font.pixelSize: Theme.fontSize + 3 }
                    Line {
                        id: reload
                        text: root.loading ? "…" : "[ F5 aktualisieren ]"
                        color: Theme.accent
                        TapHandler { onTapped: root.refresh() }
                    }
                }
                Line { visible: root.error !== ""; text: root.error; color: Theme.red }

                Flickable {
                    width: parent.width
                    height: parent.height - Theme.cellH * 4
                    contentHeight: content.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: content
                        width: parent.width
                        spacing: Theme.cellH * 0.8

                        Repeater {
                            model: root.groups
                            Column {
                                id: group
                                required property var modelData
                                width: content.width
                                spacing: Theme.cellH * 0.15
                                Line { text: group.modelData.title; color: Theme.fgDim }

                                Repeater {
                                    model: group.modelData.items
                                    Column {
                                        id: itemBlock
                                        required property var modelData
                                        width: group.width
                                        spacing: Theme.cellH * 0.12
                                        readonly property bool expanded: root.expandedId === modelData.id
                                        readonly property bool hasDetails: modelData.details && modelData.details.length > 0

                                        Rectangle {
                                            id: row
                                            width: itemBlock.width
                                            height: Theme.cellH * 2
                                            radius: Theme.radius
                                            color: hover.hovered ? Theme.hover : Theme.bgLight
                                            border.width: Theme.borderWidth
                                            border.color: itemBlock.expanded ? Theme.accent : Theme.muted

                                            Rectangle {
                                                width: Theme.borderWidth * 2
                                                height: parent.height * 0.55
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: itemBlock.modelData.state === "ok" ? Theme.green : (itemBlock.modelData.state === "warn" ? Theme.yellow : Theme.muted)
                                            }
                                            Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 1.5; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.34; text: itemBlock.modelData.label; color: Theme.fg; elide: Text.ElideRight }
                                            Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.58; horizontalAlignment: Text.AlignRight; text: itemBlock.modelData.detail + (itemBlock.hasDetails ? (itemBlock.expanded ? "  ⌃" : "  ⌄") : (itemBlock.modelData.command ? "  ›" : "")); color: itemBlock.modelData.state === "off" ? Theme.muted : Theme.fgDim; elide: Text.ElideRight }
                                            HoverHandler { id: hover; cursorShape: itemBlock.hasDetails || itemBlock.modelData.command ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                            TapHandler {
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onTapped: (point, button) => {
                                                    if (button === Qt.RightButton && itemBlock.modelData.command) root.run(itemBlock.modelData.command);
                                                    else if (itemBlock.hasDetails) root.expandedId = itemBlock.expanded ? "" : itemBlock.modelData.id;
                                                    else if (itemBlock.modelData.command) root.run(itemBlock.modelData.command);
                                                }
                                            }
                                        }

                                        Repeater {
                                            model: itemBlock.expanded ? itemBlock.modelData.details : []
                                            Rectangle {
                                                id: detailRow
                                                required property var modelData
                                                width: itemBlock.width
                                                height: Theme.cellH * 1.65
                                                radius: Theme.radius
                                                color: Theme.alpha(Theme.bgLight, 0.65)
                                                Rectangle { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: Theme.borderWidth * 2; height: parent.height * 0.45; color: detailRow.modelData.state === "warn" ? Theme.yellow : Theme.green }
                                                Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 2; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.35; text: detailRow.modelData.label; color: Theme.fg; elide: Text.ElideRight }
                                                Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.56; horizontalAlignment: Text.AlignRight; text: detailRow.modelData.detail; color: Theme.fgDim; elide: Text.ElideRight }
                                                HoverHandler { cursorShape: detailRow.modelData.command ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                                TapHandler { enabled: !!detailRow.modelData.command; onTapped: root.run(detailRow.modelData.command) }
                                            }
                                        }

                                        Line {
                                            visible: itemBlock.expanded && !!itemBlock.modelData.command
                                            text: "  Extern oeffnen: Rechtsklick auf den Kopf"
                                            color: Theme.muted
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Line { text: "Esc schliesst · F5 aktualisiert · Klick oeffnet Details"; color: Theme.muted }
            }
        }
    }
}
