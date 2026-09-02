import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "ProcessSelection.js" as ProcessSelection

// Prozessliste -- der Ersatz fuer DMS' Mod+M.
//
// Aufgebaut wie der Starter: Vollbildfenster, exklusive Tastatur, oben ein
// Filterfeld, darunter die Liste. Statt zu starten wird hier beendet: `k`
// schickt SIGTERM, `Shift+K` SIGKILL. Die Nachfrage spart man sich -- wer
// gezielt eine PID auswaehlt und `k` drueckt, meint es.
PanelWindow {
    id: root

    property int selected: -1
    property int selectedPid: -1
    property string selectedStarted: ""

    visible: Runtime.procsOpen

    screen: Compositor.focusedScreen
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

    function clearSelection() {
        selected = -1;
        selectedPid = -1;
        selectedStarted = "";
    }

    function selectIndex(index) {
        const entry = ProcessSelection.entryAt(Procs.shown, index);
        if (!entry) {
            clearSelection();
            return;
        }
        selected = index;
        selectedPid = entry.pid;
        selectedStarted = entry.started;
    }

    function selectProcess(pid, started) {
        const index = ProcessSelection.indexForProcess(Procs.shown, pid, started);
        if (index < 0) {
            clearSelection();
            return;
        }
        selected = index;
        selectedPid = pid;
        selectedStarted = started;
    }

    function syncSelection() {
        if (selectedPid < 1)
            return;
        const index = ProcessSelection.indexForProcess(Procs.shown, selectedPid, selectedStarted);
        if (index < 0) {
            clearSelection();
            return;
        }
        selected = index;
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function move(delta) {
        const entry = ProcessSelection.movedEntry(Procs.shown, selectedPid, selectedStarted, delta);
        if (!entry) {
            clearSelection();
            return;
        }
        selectProcess(entry.pid, entry.started);
        if (selected >= 0)
            list.positionViewAtIndex(selected, ListView.Contain);
    }

    function killSelected(hard) {
        const pid = selectedPid;
        const started = selectedStarted;
        if (ProcessSelection.indexForProcess(Procs.shown, pid, started) < 0) {
            clearSelection();
            return;
        }
        Procs.kill(pid, started, hard);
    }

    onVisibleChanged: {
        if (visible) {
            Procs.filter = "";
            filterInput.text = "";
            selectIndex(0);
            filterInput.forceActiveFocus();
        }
    }

    Connections {
        target: Procs
        function onShownChanged() { root.syncSelection(); }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    PanelSurface {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.14)

        width: Math.round(Theme.cellW * 76)
        height: header.height + list.height + footer.height + Theme.cellH

        accentBorder: true

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

            TextField {
                id: filterInput

                anchors.left: prompt.right
                anchors.right: totals.left
                anchors.top: parent.top
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                background: null
                horizontalPadding: 0
                accessibleName: "Filter processes"
                accessibleDescription: "Type to filter; arrow keys move through matching processes"
                focus: true

                onTextChanged: {
                    Procs.filter = text;
                    root.selectIndex(0);
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
                    text: "filter by name or PID"
                    color: Theme.muted
                }
            }

            Line {
                id: totals

                anchors.right: parent.right
                anchors.top: parent.top
                text: "CPU " + SysInfo.cpuPercent + "%   RAM " + SysInfo.memPercent + "%   " + Procs.list.length + " processes"
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
            readonly property real rowHeight: Theme.rowHeight

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
                radius: Theme.radius
                color: index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"

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
                    color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : (row.modelData.cpu >= 50 ? Theme.red : Theme.fg)
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        if (row.modelData?.pid && row.modelData?.started)
                            root.selectProcess(row.modelData.pid, row.modelData.started);
                    }
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
            text: "↑↓ select · Ctrl-K stop · Ctrl-Shift-K force · Ctrl-S sort · Esc close"
            color: Theme.muted
        }
    }
}
