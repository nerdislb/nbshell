import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Notifications
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
            })

            readonly property real rowWidth: 54 * Theme.cellW

            spacing: Theme.cellH * 0.3

            Item {
                width: panel.rowWidth
                height: Theme.cellH

                Line {
                    anchors.left: parent.left
                    text: "NOTIFICATIONS  (" + Notify.count + ")"
                    color: Theme.fgDim
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.cellW

                    ActionButton {
                        text: Notify.dnd ? "DND on" : "Muted"
                        tone: Notify.dnd ? "primary" : "secondary"
                        accentColor: Theme.yellow
                        compact: true
                        onTriggered: Notify.setDnd(!Notify.dnd)
                    }

                    ActionButton {
                        visible: Notify.count > 0
                        text: "Clear"
                        tone: "danger"
                        compact: true
                        onTriggered: Notify.clear()
                    }
                }
            }

            Line {
                visible: Notify.count === 0
                text: "nothing here"
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    text: panel.query
                    onTextChanged: panel.query = text

                    Line {
                        anchors.fill: parent
                        visible: parent.text === "" && !parent.activeFocus
                        verticalAlignment: Text.AlignVCenter
                        text: "search …"
                        color: Theme.muted
                    }
                }
            }

            Line {
                visible: Notify.count > 0 && panel.shownNotifications.length === 0
                text: "no results"
                color: Theme.muted
            }

            Flickable {
                id: historyView
                width: panel.rowWidth
                height: Notify.count > 0 ? Theme.cellH * 20 : 0
                visible: Notify.count > 0
                contentHeight: historyCards.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    width: Math.max(Theme.borderWidth * 3, 4)
                    policy: historyView.contentHeight > historyView.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                    contentItem: Rectangle { color: Theme.accent; radius: Theme.radius }
                    background: Rectangle { color: Theme.muted; radius: Theme.radius }
                }

                Column {
                    id: historyCards
                    width: historyView.width - (historyView.contentHeight > historyView.height ? Theme.cellW : 0)
                    spacing: Theme.cellH * 0.3

                    Repeater {
                        model: panel.shownNotifications

                        NotificationCard {
                            required property var modelData

                            width: historyCards.width
                            entry: modelData
                            detailed: false
                            onOpened: { Notify.open(modelData); panel.closePopout?.(); }
                            onRemoved: Notify.drop(modelData.key)
                        }
                    }
                }
            }
        }
    }
}
