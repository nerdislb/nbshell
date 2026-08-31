import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false

    readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "{{ID}}"

    function open(payloadJson) {
        opened = true;
        Qt.callLater(() => {
            surface.enter();
            focusScope.forceActiveFocus();
        });
    }

    function close() {
        opened = false;
    }

    function requestClose() {
        surface.dismiss(() => {
            if (shell && typeof shell.hide === "function")
                shell.hide(pluginId);
            else
                close();
        });
    }

    PanelWindow {
        visible: root.opened
        color: "transparent" // nbshell-design: allow-hardcoded-color
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "nbshell:plugin:{{SLUG}}"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            opacity: surface.opacity
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.requestClose()
        }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: root.opened
            Keys.onEscapePressed: root.requestClose()

            OverlaySurface {
                id: surface
                autoEnter: false
                preferredWidth: Theme.overlayWidthMedium
                preferredHeight: Theme.overlayHeightMedium

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => mouse.accepted = true
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.panelPadding
                    spacing: Theme.spaceLg

                    PanelHead {
                        width: parent.width
                        title: "{{NAME}}"
                        subtitle: "Built with the nbshell design contract"
                    }

                    Line {
                        width: parent.width
                        text: "Replace this content with the plugin's primary task."
                        color: Theme.fgDim
                        wrapMode: Text.WordWrap
                    }

                    ControlButton {
                        text: "Close"
                        onTriggered: root.requestClose()
                    }
                }
            }
        }
    }
}
