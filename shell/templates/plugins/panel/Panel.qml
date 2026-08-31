import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false
    property bool closingFromHost: false

    readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "{{ID}}"

    function open(payloadJson) {
        closingFromHost = false;
        opened = true;
        Qt.callLater(() => focusScope.forceActiveFocus());
    }

    function close() {
        closingFromHost = true;
        opened = false;
        closingFromHost = false;
    }

    function requestClose() {
        if (shell && typeof shell.hide === "function")
            shell.hide(pluginId);
        else
            close();
    }

    FloatingWindow {
        visible: root.opened
        title: "{{NAME}}"
        color: Theme.panelSurface
        implicitWidth: Theme.cellW * 56
        implicitHeight: Theme.cellH * 22
        minimumSize: Qt.size(Theme.cellW * 40, Theme.cellH * 16)

        onVisibleChanged: {
            if (!visible && root.opened && !root.closingFromHost)
                root.requestClose();
        }

        PanelSurface {
            anchors.fill: parent

            FocusScope {
                id: focusScope
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                focus: true
                Keys.onEscapePressed: root.requestClose()

                Column {
                    anchors.fill: parent
                    spacing: Theme.spaceLg

                    PanelHead {
                        width: parent.width
                        title: "{{NAME}}"
                        subtitle: "Built with the nbshell design contract"
                    }

                    SectionHeader {
                        width: parent.width
                        text: "Overview"
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
