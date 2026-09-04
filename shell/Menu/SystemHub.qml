import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

PanelWindow {
    id: root

    property var groups: []
    property bool loading: false
    property string error: ""
    property string expandedId: ""
    readonly property string script: Qt.resolvedUrl("../scripts/system-hub.py").toString().replace("file://", "")

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:hub"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.hubOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.hubOpen = false; }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }

    function refresh() {
        if (status.running) return;
        loading = true;
        error = "";
        status.running = true;
    }

    function run(command) {
        if (!command) return;
        Runtime.hubOpen = false;
        if (Array.isArray(command))
            Quickshell.execDetached(command.map(value => String(value)));
        else if (command.indexOf("detached:") === 0)
            Quickshell.execDetached(["sh", "-c", command.slice(9)]);
        else if (command.indexOf("xdg-open ") === 0)
            Quickshell.execDetached(["sh", "-c", command]);
        else
            Quickshell.execDetached([Apps.terminal, "-e", "sh", "-c", command + "; printf '\nEnter closes this window … '; read -r _"]);
    }

    function revealFocusedItem(item) {
        if (!item)
            return;
        const mapped = item.mapToItem(content, 0, 0);
        systemScroll.contentY = FocusScroll.contentYForFocus(
            mapped.y, item.height, systemScroll.contentY, systemScroll.height,
            systemScroll.contentHeight, Theme.spaceMd);
    }

    onVisibleChanged: if (visible) { refresh(); keys.forceActiveFocus(); }

    Process {
        id: status
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try { root.groups = JSON.parse(text).groups ?? []; }
                catch (e) { root.error = "Could not read status"; root.groups = []; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.error = String(text).trim() }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { root.refresh(); event.accepted = true; }
        }
        Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        OverlaySurface {
            id: box
            preferredWidth: Theme.cellW * 96
            preferredHeight: Theme.cellH * 42
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.5

                Row {
                    width: parent.width
                    Line { width: parent.width - reload.width; text: Icons.matrix + "  SYSTEM & PLUGINS"; color: Theme.fg; font.pixelSize: Theme.fontHeading; font.bold: true }
                    ActionButton {
                        id: reload
                        text: "REFRESH"
                        compact: true
                        busy: root.loading
                        accessibleDescription: "Refresh system and plugin status"
                        onTriggered: root.refresh()
                    }
                }
                Line { visible: root.error !== ""; text: root.error; color: Theme.red }

                Flickable {
                    id: systemScroll
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

                                        InteractiveSurface {
                                            id: row
                                            interactive: itemBlock.hasDetails || !!itemBlock.modelData.command
                                            accessibilityIgnored: !interactive
                                            accessibleName: itemBlock.modelData.label
                                            accessibleDescription: itemBlock.modelData.detail
                                                + (itemBlock.hasDetails ? (itemBlock.expanded ? ", expanded" : ", collapsed") : "")
                                            width: itemBlock.width
                                            height: Theme.cellH * 2
                                            radius: Theme.radius
                                            color: hover.hovered || visualFocus ? Theme.hover : Theme.panelSurfaceRaised
                                            border.width: Theme.borderWidth
                                            border.color: itemBlock.expanded || visualFocus ? Theme.focusBorder : Theme.panelBorder
                                            onTriggered: {
                                                if (itemBlock.hasDetails)
                                                    root.expandedId = itemBlock.expanded ? "" : itemBlock.modelData.id;
                                                else if (itemBlock.modelData.command)
                                                    root.run(itemBlock.modelData.command);
                                            }
                                            onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(row)

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
                                                    row.forceActiveFocus(Qt.MouseFocusReason);
                                                    if (button === Qt.RightButton && itemBlock.modelData.command)
                                                        root.run(itemBlock.modelData.command);
                                                    else
                                                        row.activate();
                                                }
                                            }
                                        }

                                        Repeater {
                                            model: itemBlock.expanded ? itemBlock.modelData.details : []
                                            InteractiveSurface {
                                                id: detailRow
                                                required property var modelData
                                                interactive: !!modelData.command
                                                accessibilityIgnored: !interactive
                                                accessibleName: modelData.label
                                                accessibleDescription: modelData.detail
                                                width: itemBlock.width
                                                height: Theme.cellH * 1.65
                                                radius: Theme.radius
                                                color: detailHover.hovered || visualFocus ? Theme.hover : Theme.panelSurfaceRaised
                                                border.width: visualFocus ? Theme.borderWidth : 0
                                                border.color: Theme.focusBorder
                                                onTriggered: if (modelData.command) root.run(modelData.command)
                                                onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(detailRow)
                                                Rectangle { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: Theme.borderWidth * 2; height: parent.height * 0.45; color: detailRow.modelData.state === "warn" ? Theme.yellow : Theme.green }
                                                Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 2; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.35; text: detailRow.modelData.label; color: Theme.fg; elide: Text.ElideRight }
                                                Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.56; horizontalAlignment: Text.AlignRight; text: detailRow.modelData.detail; color: Theme.fgDim; elide: Text.ElideRight }
                                                HoverHandler { id: detailHover; cursorShape: detailRow.modelData.command ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                                TapHandler {
                                                    enabled: !!detailRow.modelData.command
                                                    onTapped: {
                                                        detailRow.forceActiveFocus(Qt.MouseFocusReason);
                                                        detailRow.activate();
                                                    }
                                                }
                                            }
                                        }

                                        ActionButton {
                                            id: externalAction
                                            visible: itemBlock.expanded && !!itemBlock.modelData.command
                                            text: "OPEN EXTERNALLY"
                                            compact: true
                                            accessibleDescription: "Open " + itemBlock.modelData.label
                                            onTriggered: root.run(itemBlock.modelData.command)
                                            onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(externalAction)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Line { text: "Esc closes · F5 refreshes · Enter opens details"; color: Theme.muted }
            }
        }
    }
}
