import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Power-Menue.
//
// Wie der Starter ein Vollbildfenster mit exklusiver Tastatur, nur kleiner:
// eine Liste, Pfeile waehlen, Enter bestaetigt. Jede Zeile hat zusaetzlich
// einen Buchstaben -- `x` schaltet aus, ohne dass man zaehlen muss.
//
// Bewusst OHNE Rueckfrage: das Menue selbst ist die Rueckfrage. Wer es
// aufmacht, hat sich schon entschieden, und Esc ist immer da.
PanelWindow {
    id: root

    property int selected: 0

    visible: Runtime.powerOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:power"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.powerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.powerOpen = false;
    }

    function accept() {
        const action = Session.actions[selected];
        close();
        if (action)
            Session.run(action.id);
    }

    onVisibleChanged: {
        if (visible) {
            selected = 0;
            keys.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.accept()
        Keys.onEnterPressed: root.accept()
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(Session.actions.length - 1, root.selected + 1)
        Keys.onPressed: event => {
            // Der Buchstabe vor der Zeile waehlt und fuehrt sofort aus.
            const letter = event.text.toLowerCase();
            for (var i = 0; i < Session.actions.length; i++) {
                if (Session.actions[i].key === letter) {
                    root.selected = i;
                    root.accept();
                    event.accepted = true;
                    return;
                }
            }
        }

        Rectangle {
            id: box

            anchors.centerIn: parent
            width: Theme.cellW * 34
            height: column.implicitHeight + Theme.cellH * 2

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.red

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 2
                spacing: Theme.cellH * 0.2

                Text {
                    text: "SITZUNG"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    bottomPadding: Theme.cellH * 0.4
                }

                Repeater {
                    model: Session.actions

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        height: Theme.cellH * 1.6
                        radius: Theme.radius
                        color: row.index === root.selected ? Theme.selection : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.index === root.selected ? "▸ " : "  ") + "[" + row.modelData.key + "]  " + row.modelData.label
                            color: row.index === root.selected ? Theme.fgBright : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = row.index
                            onClicked: root.accept()
                        }
                    }
                }

                Text {
                    text: "Esc schliesst"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    topPadding: Theme.cellH * 0.4
                }
            }
        }
    }
}
