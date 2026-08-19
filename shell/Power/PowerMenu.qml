import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

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

        PanelSurface {
            id: box

            anchors.centerIn: parent
            width: Theme.cellW * 34
            height: column.implicitHeight + Theme.cellH * 2

            accentBorder: false

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 2
                spacing: Theme.cellH * 0.2

                SectionHeader {
                    width: column.width
                    text: "Session"
                    detail: "Choose an action"
                }

                Repeater {
                    model: Session.actions

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        height: Theme.rowHeight
                        radius: Theme.radius
                        color: row.index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"
                        border.width: row.index === root.selected ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
                            font.pixelSize: Theme.fontBody
                        }

                        Line {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spaceLg
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.key.toUpperCase()
                            color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.muted
                            font.pixelSize: Theme.fontCaption
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

                Line {
                    text: "Esc closes · ↑/↓ selects · Enter confirms"
                    color: Theme.muted
                    topPadding: Theme.cellH * 0.4
                }
            }
        }
    }
}
