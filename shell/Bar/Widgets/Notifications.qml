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
            property string query: ""

            readonly property var shownNotifications: Notify.history.filter(e => {
                const needle = panel.query.trim().toLowerCase();
                if (needle === "") return true;
                return ((e.appName || "") + " " + (e.summary || "") + " " + (e.body || "")).toLowerCase().indexOf(needle) >= 0;
            }).slice(0, 20)

            readonly property real rowWidth: 46 * Theme.cellW

            spacing: Theme.cellH * 0.3

            Item {
                width: panel.rowWidth
                height: Theme.cellH

                Line {
                    anchors.left: parent.left
                    text: "BENACHRICHTIGUNGEN  (" + Notify.count + ")"
                    color: Theme.fgDim
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.cellW * 2

                    Line {
                        text: Notify.dnd ? "[ nicht stoeren ]" : "[ stumm ]"
                        color: Notify.dnd ? Theme.yellow : Theme.fgDim

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notify.setDnd(!Notify.dnd)
                        }
                    }

                    Line {
                        visible: Notify.count > 0
                        text: "[ leeren ]"
                        color: Theme.red

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notify.clear()
                        }
                    }
                }
            }

            Line {
                visible: Notify.count === 0
                text: "nichts da"
                color: Theme.muted
            }

            Rectangle {
                width: panel.rowWidth
                height: Theme.cellH * 1.5
                visible: Notify.count > 0
                radius: Theme.radius
                color: Theme.bgLight
                border.width: Theme.borderWidth
                border.color: search.activeFocus ? Theme.accent : Theme.muted

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: Theme.cellW
                    anchors.rightMargin: Theme.cellW
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    text: panel.query
                    onTextChanged: panel.query = text

                    Line {
                        anchors.fill: parent
                        visible: parent.text === "" && !parent.activeFocus
                        verticalAlignment: Text.AlignVCenter
                        text: "suchen …"
                        color: Theme.muted
                    }
                }
            }

            Line {
                visible: Notify.count > 0 && panel.shownNotifications.length === 0
                text: "kein Treffer"
                color: Theme.muted
            }

            Repeater {
                model: panel.shownNotifications

                Rectangle {
                    id: row

                    required property var modelData

                    width: panel.rowWidth
                    height: content.implicitHeight + Theme.cellH * 0.6
                    radius: Theme.radius
                    color: mouse.hovered ? Theme.hover : "transparent"

                    Column {
                        id: content

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.cellW / 2
                        spacing: 0

                        Line {
                            width: parent.width
                            text: (row.modelData.appName || "System")
                                + ((row.modelData.repeat ?? 1) > 1 ? ("  ×" + row.modelData.repeat) : "")
                                + "  ·  " + Notify.ago(row.modelData.time)
                            color: Theme.fgDim
                            elide: Text.ElideRight
                        }

                        Line {
                            width: parent.width
                            text: (row.modelData.summary ?? "") + (row.modelData.body ? ("  —  " + String(row.modelData.body).replace(/<[^>]*>/g, "")) : "")
                            color: Theme.fg
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler {
                        id: mouse

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: Notify.drop(row.modelData.key)
                    }
                }
            }
        }
    }
}
