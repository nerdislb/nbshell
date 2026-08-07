import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Aufgaben: die Zahl der offenen in der Leiste, die Liste im Popout.
//
// Heisst `Tasks` und nicht `Todo`, weil der Dienst in qs.Services schon so
// heisst -- wie Clip neben Clipboard. In der Config steht der Baustein
// trotzdem als "todo".
//
// Eingetragen wird hier nichts -- dafuer braucht es ein Eingabefeld und damit
// die Tastatur, und die gehoert in einem Popout dem Fenster darunter. Das
// macht das Fenster (Todo/TodoList.qml, Mod+T); hier klickt man ab und wirft
// weg.
Cell {
    id: root

    shown: Todo.enabled
    quiet: Todo.count === 0
    slotChars: 2
    interactive: true
    label: "TODO"
    icon: Icons.todo
    text: Todo.count
    color: Todo.count > 0 ? Theme.text : Theme.textDim

    // Rechtsklick oeffnet die grosse Liste -- der kurze Weg zum Eintragen.
    onRightClicked: Runtime.todoOpen = true

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            // Breit genug fuer die Hinweiszeile darunter -- schmaler wuerde
            // sie abgeschnitten, und dann steht dort "Mod+T …".
            readonly property real rowWidth: 54 * Theme.cellW

            spacing: Theme.cellH * 0.2

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.4

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AUFGABEN  (" + Todo.count + (Todo.doneCount > 0 ? " offen, " + Todo.doneCount + " erledigt" : "") + ")"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Todo.doneCount > 0
                    text: "[ aufraeumen ]"
                    color: Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Todo.clearDone()
                    }
                }
            }

            Text {
                visible: Todo.list.length === 0
                text: "nichts vorgemerkt"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: Todo.list.slice(0, 12)

                Rectangle {
                    id: row

                    required property var modelData

                    width: panel.rowWidth
                    height: Theme.cellH * 1.4
                    radius: Theme.radius
                    color: mouse.hovered ? Theme.hover : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: (row.modelData.done ? "[x]  " : "[ ]  ") + row.modelData.text
                        color: row.modelData.done ? Theme.muted : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.strikeout: row.modelData.done
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    HoverHandler {
                        id: mouse

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onTapped: (point, button) => {
                            if (button === Qt.RightButton)
                                Todo.remove(row.modelData.id);
                            else
                                Todo.toggle(row.modelData.id);
                        }
                    }
                }
            }

            Text {
                width: panel.rowWidth
                text: (Todo.list.length > 12 ? "… und " + (Todo.list.length - 12) + " weitere  ·  " : "") + "Klick hakt ab · Rechtsklick loescht · Mod+T eintragen"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
        }
    }
}
