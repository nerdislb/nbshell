import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root

    visible: Runtime.displayOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:displays"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var display: Displays.selected
    property bool resolutionOpen: false
    readonly property var currentDisplayMode: display?.modes?.find(mode => mode.current) ?? null
    function modeLabel(mode) {
        if (!mode) return "NO MODE AVAILABLE";
        return mode.width + "×" + mode.height + "  "
            + mode.refresh.toFixed(mode.refresh % 1 ? 3 : 0) + " Hz"
            + (mode.preferred ? "  · PREFERRED" : "");
    }
    function close() {
        resolutionOpen = false;
        Runtime.displayOpen = false;
    }

    onDisplayChanged: resolutionOpen = false

    onVisibleChanged: if (visible) {
        Displays.refresh();
        keys.forceActiveFocus();
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { Displays.refresh(); event.accepted = true; }
        }

        OverlaySurface {
            preferredWidth: Theme.overlayWidthMedium
            preferredHeight: Theme.cellH * 40

            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                spacing: Theme.spaceLg

                Row {
                    width: parent.width
                    spacing: Theme.spaceLg
                    Line { width: parent.width - refresh.implicitWidth - parent.spacing; text: (Displays.outputs.length > 1 ? Icons.monitors : Icons.monitor) + "  DISPLAYS"; color: Theme.fg; font.pixelSize: Theme.fontHeading; font.bold: true }
                    ControlButton { id: refresh; text: Displays.loading ? "…" : "F5  REFRESH"; onTriggered: Displays.refresh() }
                }

                Line {
                    visible: Displays.error !== ""
                    width: parent.width
                    text: Displays.error
                    color: Theme.red
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    spacing: Theme.spaceLg

                    Repeater {
                        model: Displays.outputs
                        ControlButton {
                            required property var modelData
                            text: modelData.name + (modelData.focused ? "  · FOCUSED" : "")
                            selected: modelData.name === Displays.selectedName
                            onTriggered: Displays.selectedName = modelData.name
                        }
                    }
                }

                Flickable {
                    width: parent.width
                    height: parent.height - Theme.cellH * 5
                    contentHeight: content.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: content
                        width: parent.width
                        spacing: Theme.spaceLg

                        PanelSurface {
                            width: parent.width
                            height: Theme.cellH * 5.4
                            raised: true
                            accentBorder: false

                            Column {
                                anchors.left: parent.left; anchors.leftMargin: Theme.spaceXl
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceXs
                                Line { text: root.display ? root.display.name : "NO DISPLAY"; color: Theme.accent; font.pixelSize: Theme.fontDisplay; font.bold: true }
                                Line { text: root.display ? (root.display.make + "  " + root.display.model).trim() : ""; color: Theme.fgDim; font.pixelSize: Theme.fontSubtitle }
                            }

                            Column {
                                anchors.right: parent.right; anchors.rightMargin: Theme.spaceXl
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spaceXs
                                Line { anchors.right: parent.right; text: root.display ? (root.display.currentMode || "disabled") : ""; color: Theme.fg }
                                Line { anchors.right: parent.right; text: root.display ? (root.display.width + " × " + root.display.height + " logical  ·  " + root.display.scale + "×") : ""; color: Theme.fgDim }
                            }
                        }

                        SectionHeader { width: parent.width; text: "Resolution"; detail: root.display?.currentMode ?? "" }
                        Column {
                            width: parent.width
                            spacing: Theme.spaceSm

                            ControlButton {
                                width: parent.width
                                text: root.modeLabel(root.currentDisplayMode)
                                    + ((root.display?.modes?.length ?? 0) > 1
                                        ? (root.resolutionOpen ? "  ⌃" : "  ⌄") : "")
                                selected: root.resolutionOpen
                                enabled: (root.display?.modes?.length ?? 0) > 1
                                onTriggered: root.resolutionOpen = !root.resolutionOpen
                            }

                            Column {
                                width: parent.width
                                spacing: Theme.spaceXs
                                visible: root.resolutionOpen && (root.display?.modes?.length ?? 0) > 1

                                Repeater {
                                    model: root.resolutionOpen ? (root.display?.modes ?? []) : []
                                    ControlButton {
                                        required property var modelData
                                        width: parent.width
                                        text: root.modeLabel(modelData)
                                        selected: modelData.current
                                        onTriggered: {
                                            Displays.setValue(root.display.name, "mode", modelData.label);
                                            // Closing the list destroys this delegate. Do it only
                                            // after the selected mode has been handed to Displays.
                                            root.resolutionOpen = false;
                                        }
                                    }
                                }
                            }
                        }

                        SectionHeader { width: parent.width; text: "Scale"; detail: root.display ? root.display.scale + "×" : "" }
                        Row {
                            spacing: Theme.spaceSm
                            Repeater {
                                model: [1, 1.25, 1.5, 1.75, 2, 2.5, 3]
                                ControlButton {
                                    required property real modelData
                                    text: modelData + "×"
                                    selected: root.display && Math.abs(root.display.scale - modelData) < 0.01
                                    onTriggered: Displays.setValue(root.display.name, "scale", modelData)
                                }
                            }
                        }

                        SectionHeader { width: parent.width; text: "Orientation"; detail: root.display?.transform ?? "" }
                        Row {
                            spacing: Theme.spaceSm
                            Repeater {
                                model: [{ "id": "normal", "label": "LANDSCAPE" }, { "id": "90", "label": "LEFT 90°" }, { "id": "180", "label": "UPSIDE DOWN" }, { "id": "270", "label": "RIGHT 90°" }]
                                ControlButton {
                                    required property var modelData
                                    text: modelData.label
                                    selected: root.display && root.display.transform === modelData.id
                                    onTriggered: Displays.setValue(root.display.name, "transform", modelData.id)
                                }
                            }
                        }

                        SectionHeader { width: parent.width; text: "Position"; detail: root.display ? (root.display.x + ", " + root.display.y) : ""; visible: Displays.outputs.length > 1 }
                        Row {
                            visible: Displays.outputs.length > 1
                            spacing: Theme.spaceSm
                            property var reference: Displays.outputs.find(row => row.name !== Displays.selectedName) ?? null
                            Repeater {
                                model: [{ "id": "left", "label": "LEFT OF" }, { "id": "right", "label": "RIGHT OF" }, { "id": "above", "label": "ABOVE" }, { "id": "below", "label": "BELOW" }, { "id": "same", "label": "MIRROR POSITION" }]
                                ControlButton {
                                    required property var modelData
                                    text: modelData.label
                                    onTriggered: if (parent.reference) Displays.place(root.display.name, modelData.id, parent.reference.name)
                                }
                            }
                            Line { anchors.verticalCenter: parent.verticalCenter; text: parent.reference ? parent.reference.name : ""; color: Theme.fgDim }
                        }

                        SectionHeader { width: parent.width; text: "Output" }
                        Row {
                            spacing: Theme.spaceSm
                            ControlButton {
                                text: root.display?.enabled ? "TURN OFF" : "TURN ON"
                                danger: root.display?.enabled ?? false
                                enabled: root.display && (!root.display.enabled || Displays.outputs.filter(row => row.enabled).length > 1)
                                onTriggered: Displays.setValue(root.display.name, "enabled", !root.display.enabled)
                            }
                            Line { anchors.verticalCenter: parent.verticalCenter; text: Displays.outputs.filter(row => row.enabled).length <= 1 ? "The only active output cannot be turned off." : "Changes apply live and persist across Niri restarts."; color: Theme.fgDim }
                        }
                    }
                }
            }
        }
    }
}
