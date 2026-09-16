import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Der Gewohnheiten-Tracker (nbHabits) als Vollbild-Overlay-Fenster.
//
// nbshell-TUI statt App-Karten: dieselbe Zeichenraster-, Auswahl- und
// Aktionssprache wie Aufgaben, Menues und System-Hub.
// - GitHub-Style Heatmap Contribution Matrix (140 Tage / 20 Wochen)
// - Routine-Filter (ALL, MORNING, WORKOUT, WORK, EVENING)
// - Checkboxen, Counter-Stepper ([ - ], [ +1 ]), Streak-Anzeige (🔥 3d) und Schilde (🛡️)
// - Schnelleingabe fuer neue Gewohnheiten
PanelWindow {
    id: root

    property string pendingDelete: ""
    onSelectedRoutineChanged: pendingDelete = ""
    property int selected: 0
    onSelectedChanged: pendingDelete = ""
    property string selectedRoutine: "all"
    property string editing: ""

    readonly property var allHabits: Habits.habits
    readonly property var filteredHabits: {
        if (selectedRoutine === "all")
            return allHabits;
        return allHabits.filter(h => (h.routine || "all").toLowerCase() === selectedRoutine.toLowerCase());
    }

    readonly property string shortPath: {
        const home = Quickshell.env("HOME");
        return Habits.file.indexOf(home) === 0 ? "~" + Habits.file.substring(home.length) : Habits.file;
    }

    visible: Runtime.habitsOpen

    screen: Compositor.focusedScreen
    color: "transparent"

    WlrLayershell.namespace: "nbshell:habits"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.habitsOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.habitsOpen = false;
    }

    function current() {
        return root.filteredHabits[root.selected] ?? null;
    }

    function move(delta) {
        if (filteredHabits.length === 0)
            return;
        selected = Math.max(0, Math.min(filteredHabits.length - 1, selected + delta));
        habitList.positionViewAtIndex(selected, ListView.Contain);
    }

    function toggleCurrent() {
        const h = current();
        if (h) {
            if (h.mode === "COUNTER") {
                Habits.increment(h.id, 1);
            } else {
                Habits.toggle(h.id);
            }
        }
    }

    function accept() {
        const text = input.text.trim();
        if (text === "")
            return;

        var name = text;
        var routine = selectedRoutine === "all" ? "general" : selectedRoutine;
        var mode = "CHECKBOX";
        var target = 1.0;
        var unit = "times";
        var icon = "✨";

        if (text.indexOf("//") !== -1) {
            const parts = text.split("//");
            name = parts[0].trim();
            const tag = parts[1].trim().toLowerCase();
            if (["morning", "workout", "work", "evening", "general"].indexOf(tag) !== -1) {
                routine = tag;
            }
        }

        if (routine === "morning") icon = "🌅";
        else if (routine === "workout") icon = "💪";
        else if (routine === "work") icon = "💻";
        else if (routine === "evening") icon = "🌙";

        Habits.add(name, icon, routine, mode, target, unit, 2);
        input.text = "";
        selected = filteredHabits.length - 1;
    }

    onVisibleChanged: {
        if (!visible)
            return;
        input.text = "";
        selected = 0;
        Habits.foldConflicts();
        input.forceActiveFocus();
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        OverlaySurface {
            id: box
            preferredWidth: Theme.cellW * 96
            preferredHeight: Theme.cellH * 42
            accentBorder: false
            MouseArea { anchors.fill: parent }
            Column {
                id: body
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                spacing: Theme.spaceMd
                Row {
                    id: header
                    width: parent.width
                    Line { width: parent.width - closeButton.width; text: "Habits"; font.pixelSize: Theme.fontTitle; color: Theme.fg }
                    ControlButton { id: closeButton; text: "Close"; onTriggered: root.close() }
                }
                Line {
                    id: status
                    width: parent.width
                    text: Habits.doneCount + " / " + Habits.count + " completed · " + Habits.progressPercent + "% · " + Habits.todayString
                    color: Habits.progressPercent >= 100 ? Theme.readable(Theme.green, Theme.panelSurface) : Theme.fgDim
                    wrapMode: Text.WordWrap
                }
                LevelBar { id: progress; width: parent.width; value: Habits.progressPercent; interactive: false }
                Column {
                    id: history
                    width: parent.width
                    spacing: Theme.spaceXs
                    Line { width: parent.width; text: "History · 20 weeks"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                    Grid {
                        id: matrix
                        readonly property bool compact: body.height < Theme.cellH * 30
                        columns: 20; rows: 7; flow: Grid.TopToBottom
                        spacing: matrix.compact ? Theme.spaceXs / 2 : Theme.spaceXs
                        Repeater {
                            model: Habits.matrixCells
                            Rectangle {
                                required property var modelData
                                width: Math.max(1, Math.min(Theme.cellW * (matrix.compact ? .65 : 1), (body.width - matrix.spacing * 19) / 20))
                                height: width
                                color: Theme.alpha(Theme.accent, modelData.level > 0 ? .2 + modelData.level * .2 : .08)
                                border.width: modelData.isToday ? Theme.borderWidth : 0
                                border.color: Theme.fg
                            }
                        }
                    }
                }
                Flow {
                    id: routines
                    width: parent.width
                    spacing: Theme.spaceXs
                    Repeater {
                        model: ["all", "morning", "workout", "work", "evening", "general"]
                        ControlButton {
                            required property string modelData
                            text: modelData === "workout" ? "Training" : modelData.charAt(0).toUpperCase() + modelData.slice(1)
                            selected: root.selectedRoutine === modelData
                            onTriggered: { root.selectedRoutine = modelData; root.selected = 0; }
                        }
                    }
                }
                ListView {
                    id: habitList
                    width: parent.width
                    height: Math.max(Theme.rowHeight, body.height - header.height - status.height - progress.height - history.height - routines.height - input.height - hint.height - body.spacing * 7)
                    clip: true
                    model: root.filteredHabits
                    spacing: Theme.spaceSm
                    boundsBehavior: Flickable.StopAtBounds
                    Line { visible: habitList.count === 0; text: "No habits in this routine"; color: Theme.fgDim }
                    delegate: PanelSurface {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property var todayEntry: Habits.todayMap[String(modelData.id)]
                        readonly property bool isDone: todayEntry ? todayEntry.isCompleted : false
                        readonly property real curVal: todayEntry ? todayEntry.currentValue : 0
                        readonly property var streakData: Habits.calculateStreak(modelData.id)
                        width: habitList.width
                        height: details.implicitHeight + Theme.spaceMd * 2
                        color: root.selected === index ? Theme.selectedSurface() : "transparent"
                        border.width: 0
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { root.selected = row.index; input.forceActiveFocus(Qt.MouseFocusReason); }
                        }
                        Column {
                            id: details
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: Theme.spaceMd
                            spacing: Theme.spaceXs
                            Line { width: parent.width; text: row.modelData.name; font.strikeout: row.isDone; wrapMode: Text.WordWrap; color: root.selected === row.index ? Theme.selectedForeground() : Theme.fg }
                            Line {
                                width: parent.width
                                text: String(row.modelData.routine || "general") + " · Streak " + row.streakData.current + "d · Shields " + (row.modelData.shields ?? 2)
                                    + (["COUNTER","NUMBER","DURATION","TIMER"].includes(row.modelData.mode) ? " · " + row.curVal + "/" + row.modelData.targetValue + " " + (row.modelData.unit || "") : "")
                                wrapMode: Text.WordWrap
                                color: root.selected === row.index ? Theme.selectedForeground() : Theme.fgDim
                                font.pixelSize: Theme.fontCaption
                            }
                            Flow {
                                width: parent.width; spacing: Theme.spaceXs
                                ControlButton { visible: row.modelData.mode === "COUNTER"; text: "−"; accessibleName: "Decrease " + row.modelData.name; onTriggered: Habits.increment(row.modelData.id, -1) }
                                ControlButton { visible: row.modelData.mode === "COUNTER"; text: "+1"; accessibleName: "Increase " + row.modelData.name; onTriggered: Habits.increment(row.modelData.id, 1) }
                                ControlButton { visible: row.modelData.mode === "DURATION"; text: "+15m"; accessibleName: "Add 15 minutes to " + row.modelData.name; onTriggered: Habits.increment(row.modelData.id, 15) }
                                ControlButton { text: row.modelData.mode === "TIMER" ? (row.isDone ? "Focus done" : "Focus") : (row.isDone ? "Done" : "Complete"); selected: row.isDone; accessibleName: "Toggle " + row.modelData.name; onTriggered: Habits.toggle(row.modelData.id) }
                                ControlButton {
                                    text: root.pendingDelete === String(row.modelData.id) ? "Confirm delete" : "Delete"
                                    danger: true
                                    onTriggered: {
                                        if (root.pendingDelete !== String(row.modelData.id)) { root.pendingDelete = String(row.modelData.id); return; }
                                        Habits.remove(row.modelData.id); root.pendingDelete = "";
                                    }
                                }
                            }
                        }
                    }
                }
                TextField {
                    id: input
                    width: parent.width
                    accessibleName: "New habit"
                    placeholderText: "New habit, optional // routine"
                    focus: true
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.accept(); }
                    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.accept(); }
                    Keys.onEscapePressed: { if (text !== "") text = ""; else root.close(); }
                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    // Keep the existing editing shortcut; Shift+Tab reaches buttons.
                    Keys.onTabPressed: event => { event.accepted = true; if (!event.isAutoRepeat) root.toggleCurrent(); }
                }
                Line {
                    id: hint
                    width: parent.width
                    text: "Enter adds · Tab toggles · Shift+Tab actions · " + root.shortPath
                    wrapMode: Text.WordWrap
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                }
            }
            Connections {
                target: root.contentItem.Window.window
                function onActiveFocusItemChanged() {
                    const item = root.contentItem.Window.window.activeFocusItem;
                    if (!item) return;
                    for (let p = item; p; p = p.parent) {
                        if (p.parent === habitList.contentItem) {
                            root.selected = p.index;
                            const pos = item.mapToItem(habitList.contentItem, 0, 0);
                            habitList.contentY = Math.max(0, Math.min(habitList.contentHeight - habitList.height,
                                Math.min(pos.y, Math.max(habitList.contentY, pos.y + item.height - habitList.height))));
                            return;
                        }
                    }
                }
            }
        }
    }
}
