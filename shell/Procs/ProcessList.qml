import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Prozessliste -- der Ersatz fuer DMS' Mod+M.
//
// Aufgebaut wie der Starter: Vollbildfenster, exklusive Tastatur, oben ein
// Filterfeld, darunter die Liste. Statt zu starten wird hier beendet: `k`
// schickt SIGTERM, `Shift+K` SIGKILL. Die Nachfrage spart man sich -- wer
// gezielt eine PID auswaehlt und `k` drueckt, meint es.
PanelWindow {
    id: root

    property int selected: 0

    visible: Runtime.procsOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:procs"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.procsOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.procsOpen = false;
    }

    function move(delta) {
        const max = Procs.shown.length - 1;
        if (max < 0)
            return;
        selected = Math.max(0, Math.min(max, selected + delta));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function killSelected(hard) {
        const entry = Procs.shown[selected];
        if (entry)
            Procs.kill(entry.pid, hard);
    }

    onVisibleChanged: {
        if (visible) {
            selected = 0;
            Procs.filter = "";
            filterInput.text = "";
            filterInput.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.14)

        width: Math.round(Theme.cellW * 76)
        height: header.height + list.height + footer.height + Theme.cellH

        color: Theme.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.accent

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            height: Theme.cellH * 3.2

            Line {
                id: prompt

                anchors.left: parent.left
                anchors.top: parent.top
                text: "/ "
                color: Theme.accent
            }

            TextInput {
                id: filterInput

                anchors.left: prompt.right
                anchors.right: totals.left
                anchors.top: parent.top
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                focus: true

                onTextChanged: {
                    Procs.filter = text;
                    root.selected = 0;
                }

                Keys.onEscapePressed: root.close()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)
                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_N) {
                            root.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_P) {
                            root.move(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_K) {
                            // Ctrl-K beendet, damit das Filterfeld die Taste
                            // "k" weiter zum Tippen behaelt.
                            root.killSelected(event.modifiers & Qt.ShiftModifier);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_S) {
                            Procs.toggleSort();
                            event.accepted = true;
                        }
                    }
                }

                Line {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filterInput.text === ""
                    text: "filtern nach Name oder PID"
                    color: Theme.muted
                }
            }

            Line {
                id: totals

                anchors.right: parent.right
                anchors.top: parent.top
                text: "CPU " + SysInfo.cpuPercent + "%   RAM " + SysInfo.memPercent + "%   " + Procs.list.length + " Prozesse"
                color: Theme.fgDim
            }

            // Spaltenkopf, mit Markierung, wonach gerade sortiert wird.
            Line {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.cellH * 0.3
                text: "    PID   " + (Procs.sort === "cpu" ? "▾" : " ") + "CPU     " + (Procs.sort === "mem" ? "▾" : " ") + "RAM        RSS   " + (Procs.sort === "name" ? "▾" : " ") + "NAME"
                color: Theme.fgDim
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.borderWidth
                color: Theme.muted
            }
        }

        ListView {
            id: list

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            anchors.topMargin: Theme.cellH * 0.3

            height: rowHeight * 16
            readonly property real rowHeight: Theme.cellH * 1.3

            clip: true
            model: Procs.shown
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: list.rowHeight
                color: index === root.selected ? Theme.selection : "transparent"

                function pad(value, width) {
                    return String(value).padStart(width, " ");
                }

                Line {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // Feste Spaltenbreiten: bei Monospace reicht dafuer das
                    // Auffuellen mit Leerzeichen, kein Tabellenlayout noetig.
                    text: (row.index === root.selected ? "▸ " : "  ") + row.pad(row.modelData.pid, 7) + "  " + row.pad(row.modelData.cpu.toFixed(1), 5) + "%  " + row.pad(row.modelData.mem.toFixed(1), 5) + "%  " + row.pad((row.modelData.rss / 1024).toFixed(0), 7) + "M   " + row.modelData.name
                    color: row.index === root.selected ? Theme.on(Theme.selection) : (row.modelData.cpu >= 50 ? Theme.red : Theme.fg)
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selected = row.index
                }
            }
        }

        Line {
            id: footer

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.4
            verticalAlignment: Text.AlignVCenter
            text: "↑↓ waehlen · Ctrl-K beenden · Ctrl-Shift-K erzwingen · Ctrl-S sortieren · Esc schliessen"
            color: Theme.muted
        }
    }
}
