import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

PanelWindow {
    id: root
    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:displays"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.displayOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var display: Displays.selected
    readonly property var currentDisplayMode: display?.modes?.find(mode => mode.current) ?? null
    readonly property var reference: Displays.outputs.find(row => row.name !== display?.name) ?? null
    property bool resolutionOpen: false

    function modeLabel(mode) {
        if (!mode) return "No mode available";
        return mode.width + "×" + mode.height + "  "
            + mode.refresh.toFixed(mode.refresh % 1 ? 3 : 0) + " Hz"
            + (mode.preferred ? "  · preferred" : "");
    }
    function setValue(key, value) {
        if (display) Displays.setValue(display.name, key, value);
    }
    function selectMode(label) {
        setValue("mode", label);
        resolutionOpen = false;
        Qt.callLater(modeButton.forceActiveFocus);
    }
    function close() { resolutionOpen = false; Runtime.displayOpen = false; }
    function requestClose(done) { resolutionOpen = false; box.dismiss(done); }
    function requestOpen() { Displays.refresh(); box.enter(); Qt.callLater(refresh.forceActiveFocus); }
    function reveal(item) {
        let ancestor = item;
        while (ancestor && ancestor !== content) ancestor = ancestor.parent;
        if (!ancestor) return;
        const p = item.mapToItem(body.contentItem, 0, 0);
        body.contentY = FocusScroll.contentYForFocus(p.y, item.height, body.contentY,
            body.height, body.contentHeight, Theme.spaceSm);
    }
    function revealFocus() {
        const item = keys.Window.window?.activeFocusItem;
        if (item) reveal(item);
    }
    onDisplayChanged: {
        resolutionOpen = false;
        Qt.callLater(() => {
            if (!keys.Window.window?.activeFocusItem || keys.Window.window.activeFocusItem === keys)
                refresh.forceActiveFocus();
        });
    }
    Component.onCompleted: { Displays.refresh(); Qt.callLater(refresh.forceActiveFocus); }

    // Scoped adaptation of the established controls; no shared token changes.
    component DisplayButton: ControlButton {
        onActiveFocusChanged: if (activeFocus) root.reveal(this)
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: {
            if (root.resolutionOpen) { root.resolutionOpen = false; modeButton.forceActiveFocus(); }
            else root.close();
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { Displays.refresh(); event.accepted = true; }
        }
        OverlaySurface {
            id: box
            preferredWidth: Theme.overlayWidthMedium
            preferredHeight: Theme.cellH * 40
            color: Theme.bg
            accentBorder: false
            border.color: Theme.panelBorder
            motionEnabled: false
            MouseArea { anchors.fill: parent }
            Column {
                id: layout
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                spacing: Theme.spaceMd
                Row {
                    id: header
                    width: parent.width
                    height: Math.max(title.height, refresh.height)
                    spacing: Theme.spaceMd
                    PanelHead { id: title; rowWidth: parent.width - refresh.width - parent.spacing; title: "Displays" }
                    ControlButton { id: refresh; text: Displays.loading ? "Refreshing…" : "Refresh"; onTriggered: Displays.refresh() }
                }
                Flickable {
                    id: body
                    width: parent.width
                    height: Math.max(0, layout.height - header.height - footer.height - layout.spacing * 2)
                    contentWidth: width
                    contentHeight: content.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    onContentHeightChanged: Qt.callLater(root.revealFocus)
                    onHeightChanged: Qt.callLater(root.revealFocus)
                    Column {
                        id: content
                        width: body.width - Theme.spaceMd
                        spacing: Theme.spaceMd
                        Line { width: parent.width; visible: Displays.error !== ""; text: Displays.error; color: Theme.red; wrapMode: Text.Wrap }
                        Flow {
                            width: parent.width
                            spacing: Theme.spaceSm
                            Repeater {
                                id: outputButtons
                                model: Displays.outputs
                                DisplayButton {
                                    required property var modelData
                                    width: Math.min(implicitWidth, content.width)
                                    text: modelData.name + (modelData.focused ? " · focused" : "")
                                    selected: modelData.name === root.display?.name
                                    onTriggered: Displays.selectedName = modelData.name
                                }
                            }
                        }
                        Column {
                            width: parent.width
                            spacing: Theme.spaceXs
                            Line { width: parent.width; text: root.display?.name ?? "No display connected"; color: Theme.fg; font.pixelSize: Theme.fontTitle; font.bold: true; elide: Text.ElideRight }
                            Line { width: parent.width; visible: !!root.display; text: root.display ? (root.display.make + "  " + root.display.model).trim() : ""; color: Theme.fgDim; wrapMode: Text.Wrap }
                            Line { width: parent.width; visible: !!root.display; text: root.display ? (root.display.width + " × " + root.display.height + " logical · " + root.display.scale + "× · " + (root.display.enabled ? "enabled" : "disabled")) : ""; color: Theme.fgDim; wrapMode: Text.Wrap }
                        }
                        Column {
                            width: parent.width
                            visible: !!root.display
                            spacing: Theme.spaceMd
                            Rule { rowWidth: parent.width }
                            SectionHeader { width: parent.width; text: "Resolution" }
                            DisplayButton {
                                id: modeButton
                                width: parent.width
                                text: root.modeLabel(root.currentDisplayMode) + ((root.display?.modes?.length ?? 0) > 1 ? (root.resolutionOpen ? "  ⌃" : "  ⌄") : "")
                                selected: root.resolutionOpen
                                enabled: (root.display?.modes?.length ?? 0) > 1
                                onTriggered: root.resolutionOpen = !root.resolutionOpen
                            }
                            Column {
                                width: parent.width
                                spacing: Theme.spaceXs
                                visible: root.resolutionOpen
                                Repeater {
                                    id: modeButtons
                                    model: root.resolutionOpen ? (root.display?.modes ?? []) : []
                                    DisplayButton {
                                        required property var modelData
                                        width: parent.width
                                        text: root.modeLabel(modelData)
                                        selected: modelData.current
                                        onTriggered: root.selectMode(modelData.label)
                                    }
                                }
                            }
                            SectionHeader { width: parent.width; text: "Scale"; detail: root.display ? root.display.scale + "×" : "" }
                            Flow {
                                width: parent.width
                                spacing: Theme.spaceSm
                                Repeater {
                                    model: [1, 1.25, 1.5, 1.75, 2, 2.5, 3]
                                    DisplayButton {
                                        required property real modelData
                                        text: modelData + "×"
                                        selected: root.display && Math.abs(root.display.scale - modelData) < 0.01
                                        onTriggered: root.setValue("scale", modelData)
                                    }
                                }
                            }
                            SectionHeader { width: parent.width; text: "Orientation"; detail: root.display?.transform ?? "" }
                            Flow {
                                width: parent.width
                                spacing: Theme.spaceSm
                                Repeater {
                                    model: [{id:"normal",label:"Landscape"},{id:"90",label:"Left 90°"},{id:"180",label:"Upside down"},{id:"270",label:"Right 90°"}]
                                    DisplayButton {
                                        required property var modelData
                                        text: modelData.label
                                        selected: root.display?.transform === modelData.id
                                        onTriggered: root.setValue("transform", modelData.id)
                                    }
                                }
                            }
                            SectionHeader { width: parent.width; text: "Position"; detail: root.display ? root.display.x + ", " + root.display.y : ""; visible: !!root.reference }
                            Flow {
                                width: parent.width
                                visible: !!root.reference
                                spacing: Theme.spaceSm
                                Repeater {
                                    model: [{id:"left",label:"Left of"},{id:"right",label:"Right of"},{id:"above",label:"Above"},{id:"below",label:"Below"},{id:"same",label:"Mirror position"}]
                                    DisplayButton {
                                        required property var modelData
                                        text: modelData.label
                                        onTriggered: if (root.display && root.reference) Displays.place(root.display.name, modelData.id, root.reference.name)
                                    }
                                }
                            }
                            Line { width: parent.width; visible: !!root.reference; text: "Relative to " + (root.reference?.name ?? ""); color: Theme.fgDim; wrapMode: Text.Wrap }
                            SectionHeader { width: parent.width; text: "Output" }
                            DisplayButton {
                                id: toggleOutput
                                text: root.display?.enabled ? "Turn off" : "Turn on"
                                danger: root.display?.enabled ?? false
                                enabled: !!root.display && (!root.display.enabled || Displays.outputs.filter(row => row.enabled).length > 1)
                                onTriggered: if (enabled && root.display) root.setValue("enabled", !root.display.enabled)
                            }
                            Line { id: outputHint; width: parent.width; text: root.display?.enabled && Displays.outputs.filter(row => row.enabled).length <= 1 ? "The only active output cannot be turned off." : "Changes apply live and persist across Umbriel restarts."; color: Theme.fgDim; wrapMode: Text.Wrap }
                        }
                    }
                }
                Row {
                    id: footer
                    width: parent.width
                    height: Math.max(hints.implicitHeight, closeButton.height)
                    spacing: Theme.spaceMd
                    Line { id: hints; width: parent.width - closeButton.width - parent.spacing; text: "Tab select · Enter apply · F5 refresh · Esc back/close"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; wrapMode: Text.Wrap }
                    ActionButton { id: closeButton; text: "Close"; onTriggered: root.close() }
                }
            }
        }
    }
}
