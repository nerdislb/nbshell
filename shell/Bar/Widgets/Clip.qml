import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Zwischenablage: Anzahl in der Leiste, Verlauf im Popout.
Cell {
    id: root

    shown: Clipboard.enabled
    quiet: Clipboard.entries.length === 0
    slotChars: 3
    interactive: true
    label: "CLP"
    icon: Icons.clipboard
    text: Clipboard.entries.length
    color: Clipboard.entries.length > 0 ? Theme.text : Theme.textDim

    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.clipOpen = root.popoutVisible

    Connections {
        target: Runtime

        function onClipOpenChanged() {
            root.setPopout(Runtime.clipOpen);
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 52 * Theme.cellW

            spacing: Theme.cellH * 0.2

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.4

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ZWISCHENABLAGE  (" + Clipboard.entries.length + ")"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Clipboard.entries.length > 0
                    text: "[ leeren ]"
                    color: Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Clipboard.clear()
                    }
                }
            }

            Text {
                visible: Clipboard.entries.length === 0
                text: "noch nichts kopiert"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: Clipboard.entries.slice(0, 15)

                Rectangle {
                    id: row

                    required property var modelData
                    required property int index

                    width: panel.rowWidth
                    height: Theme.cellH * 1.4
                    radius: Theme.radius
                    color: mouse.containsMouse ? Theme.hover : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        // Die ersten neun bekommen eine Nummer -- so sieht man
                        // beim Hinsehen, wie weit man zurueckgreift.
                        text: (row.index < 9 ? (row.index + 1) + "  " : "   ") + Clipboard.preview(row.modelData, 46)
                        color: row.index === 0 ? Theme.readable(Theme.accent, Theme.bg) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouseEvent => {
                            if (mouseEvent.button === Qt.RightButton) {
                                Clipboard.remove(row.modelData);
                                return;
                            }
                            Clipboard.copy(row.modelData);
                            if (panel.closePopout)
                                panel.closePopout();
                        }
                    }
                }
            }
        }
    }
}
