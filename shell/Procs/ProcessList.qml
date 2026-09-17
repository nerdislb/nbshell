import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "ProcessSelection.js" as ProcessSelection

// Native process identity and signalling remain behind Procs. Confirm each
// explicit stop against the selected PID and start time, never the row index.
PanelWindow {
    id: root

    property string pendingSignal: ""
    onSelectedPidChanged: pendingSignal = ""
    onSelectedStartedChanged: pendingSignal = ""
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
        const key = pid + ":" + started + ":" + (hard ? "kill" : "term");
        if (pendingSignal !== key) { pendingSignal = key; return; }
        pendingSignal = "";
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

    Rectangle { anchors.fill: parent; color: Theme.scrim; z: -1 }

    MotionSurface {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(Theme.panelPadding, (parent.height - height) / 2)

        width: Math.min(parent.width - Theme.panelPadding * 2, Theme.cellW * 86)
        height: header.height + list.height + footer.height + Theme.cellH

        accentBorder: false
        readonly property bool compact: width < Theme.cellW * 66
        Keys.onEscapePressed: root.close()

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            height: Theme.cellH * 5

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
                anchors.right: parent.right
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
                            if (!event.isAutoRepeat) root.killSelected(Boolean(event.modifiers & Qt.ShiftModifier));
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
                anchors.top: filterInput.bottom
                text: "CPU " + SysInfo.cpuPercent + "%   RAM " + SysInfo.memPercent + "%   " + Procs.list.length + " processes"
                color: Theme.fgDim
            }

            // Spaltenkopf, mit Markierung, wonach gerade sortiert wird.
            Line {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.cellH * 0.3
                width: parent.width
                elide: Text.ElideRight
                text: box.compact ? "Process · PID / CPU · RAM · RSS" : "    PID   " + (Procs.sort === "cpu" ? "▾" : " ") + "CPU     " + (Procs.sort === "mem" ? "▾" : " ") + "RAM        RSS   " + (Procs.sort === "name" ? "▾" : " ") + "NAME"
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

            height: Math.max(rowHeight, Math.min(rowHeight * 16, root.height - header.height - footer.height - Theme.cellH - Theme.panelPadding * 2))
            readonly property real rowHeight: box.compact ? Theme.cellH * 2.7 : Theme.rowHeight

            clip: true
            model: Procs.shown
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: InteractiveSurface {
                id: row

                required property var modelData
                required property int index
                accessibleName: modelData.name + " · PID " + modelData.pid
                accessibleDescription: "CPU " + modelData.cpu.toFixed(1) + "%, RAM " + modelData.mem.toFixed(1) + "%, RSS " + (modelData.rss / 1024).toFixed(0) + " MB"
                accessibleSelected: root.selectedPid === modelData.pid
                onTriggered: root.selectProcess(modelData.pid, modelData.started)
                onActiveFocusChanged: if (activeFocus) list.positionViewAtIndex(index,ListView.Contain)
                border.width: visualFocus ? Theme.borderWidth : 0
                border.color: Theme.focusBorder

                width: list.width
                height: list.rowHeight
                radius: Theme.radius
                color: index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"

                function pad(value, width) {
                    return String(value).padStart(width, " ");
                }

                Line {
                    visible: !box.compact
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // Feste Spaltenbreiten: bei Monospace reicht dafuer das
                    // Auffuellen mit Leerzeichen, kein Tabellenlayout noetig.
                    text: (row.index === root.selected ? "▸ " : "  ") + row.pad(row.modelData.pid, 7) + "  " + row.pad(row.modelData.cpu.toFixed(1), 5) + "%  " + row.pad(row.modelData.mem.toFixed(1), 5) + "%  " + row.pad((row.modelData.rss / 1024).toFixed(0), 7) + "M   " + row.modelData.name
                    // Die CPU-Warnung ist eine Aussage ueber den Prozess, keine
                    // Gestaltung: sie muss auch in der ausgewaehlten Zeile
                    // sichtbar bleiben. Vorher ersetzte die Auswahl sie durch
                    // die Auswahlfarbe -- mit dem neutralen Wash faellt das
                    // nicht mehr auf, der Informationsverlust bleibt aber.
                    color: row.modelData.cpu >= 50
                        ? Theme.readable(Theme.red, row.index === root.selected ? Theme.selectedSurface(Theme.accent) : Theme.bg, 4.5)
                        : (row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg)
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }

                Column {
                    visible: box.compact
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    Line {
                        width: parent.width
                        text: (row.index === root.selected ? "▸ " : "") + row.modelData.name + " · " + row.modelData.pid
                        color: row.modelData.cpu >= 50
                            ? Theme.readable(Theme.red, row.index === root.selected ? Theme.selectedSurface(Theme.accent) : Theme.bg, 4.5)
                            : (row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg)
                        elide: Text.ElideRight
                    }
                    Line {
                        width: parent.width
                        text: "CPU " + row.modelData.cpu.toFixed(1) + "% · RAM " + row.modelData.mem.toFixed(1) + "% · " + (row.modelData.rss / 1024).toFixed(0) + "M"
                        color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { row.forceActiveFocus(Qt.MouseFocusReason); row.activate(); }
                    onEntered: {
                        if (row.modelData?.pid && row.modelData?.started)
                            root.selectProcess(row.modelData.pid, row.modelData.started);
                    }
                }
            }
        }

        Column {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            spacing: Theme.spaceXs
            Flow {
                width: parent.width
                spacing: Theme.spaceSm
                ControlButton { text: "Sort: " + Procs.sort; onTriggered: Procs.toggleSort() }
                ControlButton { text: root.pendingSignal.endsWith(":term") ? "Confirm stop" : "Stop"; enabled: root.selectedPid > 0; onTriggered: root.killSelected(false) }
                ControlButton { text: root.pendingSignal.endsWith(":kill") ? "Confirm force" : "Force stop"; danger: true; enabled: root.selectedPid > 0; onTriggered: root.killSelected(true) }
                ControlButton { text: "Close"; onTriggered: root.close() }
            }
            Line {
                width: parent.width
                text: root.pendingSignal !== "" ? "Stop PID " + root.selectedPid + "? Repeat the action to confirm" : "↑↓ select · Ctrl-K stop · Ctrl-Shift-K force · Ctrl-S sort · Esc close"
                color: root.pendingSignal !== "" ? Theme.readable(Theme.yellow,Theme.panelSurface) : Theme.fgDim
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontCaption
            }
        }
    }
}
