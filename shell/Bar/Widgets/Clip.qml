import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Zwischenablage: Anzahl in der Leiste, Verlauf im Popout.
Cell {
    id: root

    shown: Clipboard.enabled
    quiet: Clipboard.entries.length === 0 && Clipboard.images.length === 0
    slotChars: 3
    interactive: true
    label: "CLP"
    icon: Icons.clipboard
    text: Clipboard.entries.length + Clipboard.images.length
    color: Clipboard.entries.length + Clipboard.images.length > 0 ? Theme.text : Theme.textDim

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

                Line {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CLIPBOARD  (" + (Clipboard.entries.length + Clipboard.images.length) + ")"
                    color: Theme.fgDim
                }

                ActionButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Clipboard.entries.length + Clipboard.images.length > 0
                    text: "Clear"
                    tone: "danger"
                    compact: true
                    onTriggered: Clipboard.clear()
                }
            }

            Line {
                visible: Clipboard.entries.length === 0 && Clipboard.images.length === 0
                text: "nothing copied yet"
                color: Theme.muted
            }

            Flow {
                width: panel.rowWidth
                spacing: Theme.cellW
                visible: Clipboard.images.length > 0

                Repeater {
                    model: Clipboard.images.slice(0, 8)

                    Rectangle {
                        id: imageRow
                        required property var modelData
                        width: Theme.cellW * 12
                        height: Theme.cellH * 5
                        radius: Theme.radius
                        color: imageHover.hovered ? Theme.hover : Theme.bgLight
                        border.width: Theme.borderWidth
                        border.color: Theme.muted
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: Theme.borderWidth
                            source: Clipboard.imagePath(imageRow.modelData)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }

                        HoverHandler { id: imageHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (point, button) => {
                                if (button === Qt.RightButton)
                                    Clipboard.removeImage(imageRow.modelData);
                                else {
                                    Clipboard.copyImage(imageRow.modelData);
                                    if (panel.closePopout) panel.closePopout();
                                }
                            }
                        }
                    }
                }
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
                    color: mouse.hovered ? Theme.hover : "transparent"

                    Line {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        // Die ersten neun bekommen eine Nummer -- so sieht man
                        // beim Hinsehen, wie weit man zurueckgreift.
                        text: (row.index < 9 ? (row.index + 1) + "  " : "   ") + Clipboard.preview(row.modelData, 46)
                        color: row.index === 0 ? Theme.readable(Theme.accent, Theme.bg) : Theme.fg
                        elide: Text.ElideRight
                    }

                    HoverHandler {
                        id: mouse

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onTapped: (point, button) => {
                            if (button === Qt.RightButton) {
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
