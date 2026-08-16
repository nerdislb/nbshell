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
        if (command.indexOf("xdg-open ") === 0)
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
                                    Rectangle {
                                        id: row
                                        required property var modelData
                                        width: group.width
                                        height: Theme.cellH * 2
                                        radius: Theme.radius
                                        color: hover.hovered ? Theme.hover : Theme.bgLight
                                        border.width: Theme.borderWidth
                                        border.color: Theme.muted

                                        Rectangle {
                                            width: Theme.borderWidth * 2
                                            height: parent.height * 0.55
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: row.modelData.state === "ok" ? Theme.green : (row.modelData.state === "warn" ? Theme.yellow : Theme.muted)
                                        }
                                        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 1.5; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.34; text: row.modelData.label; color: Theme.fg; elide: Text.ElideRight }
                                        Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.58; horizontalAlignment: Text.AlignRight; text: row.modelData.detail + (row.modelData.command ? "  ›" : ""); color: row.modelData.state === "off" ? Theme.muted : Theme.fgDim; elide: Text.ElideRight }
                                        HoverHandler { id: hover; cursorShape: row.modelData.command ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler { enabled: !!row.modelData.command; onTapped: root.run(row.modelData.command) }
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
