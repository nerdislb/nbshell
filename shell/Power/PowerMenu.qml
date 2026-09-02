import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Power-Menue.
//
// Wie der Starter ein Vollbildfenster mit exklusiver Tastatur, nur kleiner:
// eine Liste, Pfeile waehlen, Enter bestaetigt. Destruktive Sitzungsaktionen
// brauchen zwei absichtliche Aktivierungen; Esc bleibt jederzeit verfuegbar.
PanelWindow {
    id: root

    property int selected: 0
    property int confirmIndex: -1
    property var afterClose: null

    visible: true

    screen: Compositor.focusedScreen
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
    function requestClose(done) {
        box.dismiss(() => {
            const next = root.afterClose;
            root.afterClose = null;
            if (!Runtime.powerOpen && next) next();
            done();
        });
    }
    function requestOpen() {
        afterClose = null;
        box.enter();
    }

    function accept() {
        const action = Session.actions[selected];
        if (!action)
            return;
        if (root.confirmIndex !== root.selected) {
            root.confirmIndex = root.selected;
            confirmReset.restart();
            return;
        }
        confirmReset.stop();
        root.confirmIndex = -1;
        root.afterClose = () => {
            Session.run(action.id);
        };
        close();
    }

    onVisibleChanged: {
        if (visible) {
            selected = 0;
            confirmIndex = -1;
            keys.forceActiveFocus();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
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
        Keys.onUpPressed: { root.selected = Math.max(0, root.selected - 1); root.confirmIndex = -1; }
        Keys.onDownPressed: { root.selected = Math.min(Session.actions.length - 1, root.selected + 1); root.confirmIndex = -1; }
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

        MotionSurface {
            id: box

            anchors.centerIn: parent
            width: Theme.cellW * 34
            height: column.implicitHeight + Theme.cellH * 2

            accentBorder: true

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

                    PanelRow {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        title: root.confirmIndex === row.index ? "Confirm " + row.modelData.label : row.modelData.label
                        value: root.confirmIndex === row.index ? "ENTER" : row.modelData.key.toUpperCase()
                        selected: row.index === root.selected
                        interactive: true
                        accessibleDescription: "Session action; shortcut " + value
                        onHoveredChanged: if (hovered && root.selected !== row.index) {
                            root.selected = row.index;
                            root.confirmIndex = -1;
                        }
                        onTriggered: {
                            root.selected = row.index;
                            root.accept();
                        }
                    }
                }

                Line {
                    text: root.confirmIndex >= 0
                        ? "Enter again confirms · Esc cancels"
                        : "Esc closes · ↑/↓ selects · Enter arms"
                    color: Theme.muted
                    topPadding: Theme.cellH * 0.4
                }
            }
        }
    }

    Timer {
        id: confirmReset
        interval: 3500
        onTriggered: root.confirmIndex = -1
    }
}
