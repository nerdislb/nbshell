import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Benachrichtigungen in der Leiste: Anzahl, und das Archiv im Popout.
Cell {
    id: root

    interactive: true
    quiet: Notify.count === 0 && !Notify.dnd
    slotChars: 3
    label: Notify.dnd ? "DND" : "MSG"
    icon: Notify.dnd ? Icons.bellOff : Icons.bell
    text: Notify.count
    color: Notify.dnd ? Theme.fgDim : (Notify.count > 0 ? Theme.text : Theme.textDim)

    // Rechtsklick schaltet "Nicht stoeren" -- die Handbewegung, die man am
    // haeufigsten braucht.
    onRightClicked: Notify.setDnd(!Notify.dnd)

    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.notifyOpen = root.popoutVisible

    Connections {
        target: Runtime

        function onNotifyOpenChanged() {
            root.setPopout(Runtime.notifyOpen);
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 46 * Theme.cellW

            spacing: Theme.cellH * 0.3

            Item {
                width: panel.rowWidth
                height: Theme.cellH

                Text {
                    anchors.left: parent.left
                    text: "BENACHRICHTIGUNGEN  (" + Notify.count + ")"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.cellW * 2

                    Text {
                        text: Notify.dnd ? "[ nicht stoeren ]" : "[ stumm ]"
                        color: Notify.dnd ? Theme.yellow : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notify.setDnd(!Notify.dnd)
                        }
                    }

                    Text {
                        visible: Notify.count > 0
                        text: "[ leeren ]"
                        color: Theme.red
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notify.clear()
                        }
                    }
                }
            }

            Text {
                visible: Notify.count === 0
                text: "nichts da"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: Notify.history.slice(0, 12)

                Rectangle {
                    id: row

                    required property var modelData

                    readonly property var n: modelData.notification

                    width: panel.rowWidth
                    height: content.implicitHeight + Theme.cellH * 0.6
                    radius: Theme.radius
                    color: mouse.containsMouse ? Theme.hover : "transparent"

                    Column {
                        id: content

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.cellW / 2
                        spacing: 0

                        Text {
                            width: parent.width
                            text: (row.n?.appName || "System") + "  ·  " + Notify.ago(row.modelData.time)
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: (row.n?.summary ?? "") + (row.n?.body ? ("  —  " + String(row.n.body).replace(/<[^>]*>/g, "")) : "")
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notify.drop(row.modelData.id)
                    }
                }
            }
        }
    }
}
