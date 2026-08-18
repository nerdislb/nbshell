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

    property int selected: 0
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

    screen: Quickshell.screens[0] ?? null
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

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: box

        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.10)
        width: Math.min(parent.width - Theme.cellW * 8, Theme.cellW * 96)
        height: Math.min(parent.height * 0.20 + Theme.cellH * 34, Theme.cellH * 44)

        radius: Theme.radius
        color: Theme.bg
        border.width: Theme.borderWidth
        border.color: Theme.accent

        DragHandler {
            acceptedModifiers: Qt.MetaModifier
            cursorShape: Qt.ClosedHandCursor
            target: box
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.cellW * 2
            spacing: Theme.cellH * 0.55

            // ── Kopfbereich ────────────────────────────────────────────────
            Item {
                width: parent.width
                height: Theme.cellH * 1.6

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.cellW

                    Text {
                        text: Icons.habit
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                        color: Theme.accent
                    }

                    Text {
                        text: "HABITS"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                        color: Theme.fg
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.cellW

                    Rectangle {
                        radius: Theme.radius
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: Theme.muted
                        width: themeLabel.width + Theme.cellW * 1.5
                        height: Theme.cellH * 1.4
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: themeLabel
                            anchors.centerIn: parent
                            text: Config.theme.toUpperCase()
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.fgDim
                        }
                    }

                    Text {
                        text: "[ ESC CLOSE ]"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                        color: Theme.red
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }
            }

            // ── Status & Fortschrittsbalken ────────────────────────────────
            Rectangle {
                width: parent.width
                height: Theme.cellH * 3.4
                color: "transparent"

                Column {
                    anchors.fill: parent
                    spacing: Theme.cellH * 0.15

                    Item {
                        width: parent.width
                        height: Theme.cellH

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "STATUS  ·  " + Habits.todayString
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.fgDim
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.shortPath !== "" ? root.shortPath : "Sync active"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.fgDim
                        }
                    }

                    Text {
                        text: Habits.doneCount + " / " + Habits.count + " DONE  ·  " + Habits.progressPercent + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Habits.progressPercent >= 100 ? Theme.green : Theme.accent
                    }

                    // Progress Bar
                    Rectangle {
                        width: parent.width
                        height: Theme.borderWidth
                        color: Theme.muted

                        Rectangle {
                            width: Math.round(parent.width * (Habits.progressPercent / 100.0))
                            height: parent.height
                            color: Habits.progressPercent >= 100 ? Theme.green : Theme.accent
                        }
                    }
                }
            }

            // ── Contribution Matrix Heatmap ────────────────────────────────
            Rectangle {
                width: parent.width
                height: Theme.cellH * 6.2
                color: "transparent"

                Column {
                    anchors.fill: parent
                    spacing: Theme.cellH * 0.35

                    Item {
                        width: parent.width
                        height: Theme.cellH

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "HISTORY  ·  20 WEEKS"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgDim
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "WENIG  ░ ▒ ▓ █  VIEL"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.fgDim
                        }
                    }

                    Grid {
                        columns: 20
                        rows: 7
                        rowSpacing: Math.max(2, Math.round(Theme.cellH * 0.14))
                        columnSpacing: Math.max(2, Math.round(Theme.cellW * 0.35))
                        flow: Grid.TopToBottom

                        Repeater {
                            model: Habits.matrixCells

                            Rectangle {
                                required property var modelData

                                width: Math.max(7, Math.round(Theme.cellW * 0.75))
                                height: Math.max(7, Math.round(Theme.cellH * 0.48))
                                radius: 0

                                color: {
                                    if (modelData.level === 4) return Theme.accent;
                                    if (modelData.level === 3) return Theme.cyan;
                                    if (modelData.level === 2) return Theme.green;
                                    if (modelData.level === 1) return Theme.alpha(Theme.accent, 0.5);
                                    return Theme.alpha(Theme.fg, 0.1);
                                }
                                border.width: modelData.isToday ? 1 : 0
                                border.color: Theme.fg
                            }
                        }
                    }
                }
            }

            // ── Routine Tabs ───────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: Theme.cellW * 0.5

                readonly property var routines: [
                    { id: "all", label: "ALL" },
                    { id: "morning", label: "MORNING" },
                    { id: "workout", label: "TRAINING" },
                    { id: "work", label: "ARBEIT" },
                    { id: "evening", label: "ABEND" },
                    { id: "general", label: "ALLGEMEIN" }
                ]

                Repeater {
                    model: parent.routines

                    Rectangle {
                        required property var modelData

                        width: tabText.width + Theme.cellW * 2
                        height: Theme.cellH * 1.45
                        radius: Theme.radius
                        color: root.selectedRoutine === modelData.id ? Theme.alpha(Theme.accent, 0.24) : Theme.bgLight
                        border.width: Theme.borderWidth
                        border.color: root.selectedRoutine === modelData.id ? Theme.accent : Theme.muted

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: root.selectedRoutine === modelData.id ? Theme.on(Theme.selection) : Theme.fgDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedRoutine = modelData.id;
                                root.selected = 0;
                            }
                        }
                    }
                }
            }

            // ── Gewohnheiten-Liste ─────────────────────────────────────────
            ListView {
                id: habitList
                width: parent.width
                // Der Rest der Spalte belegt rund 17,7 Textzeilen. So bleibt
                // die Eingabe auch auf kleineren Displays innerhalb des
                // Rahmens, statt unter ihm zu verschwinden.
                height: Math.max(Theme.cellH * 4, parent.height - Theme.cellH * 17.7)
                clip: true
                spacing: 0
                model: root.filteredHabits
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property var todayEntry: Habits.todayMap[String(modelData.id)]
                    readonly property bool isDone: todayEntry ? todayEntry.isCompleted : false
                    readonly property real curVal: todayEntry ? todayEntry.currentValue : 0.0
                    readonly property var streakData: Habits.calculateStreak(modelData.id)

                    width: habitList.width
                    height: Theme.cellH * 2.5
                    color: root.selected === index ? Theme.selection : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selected = index
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW * 0.5
                        anchors.right: actionRow.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.cellW

                        Text {
                            text: root.selected === index ? "▸" : " "
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: root.selected === index ? Theme.on(Theme.selection) : Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Icon
                        Text {
                            text: row.isDone ? "[x]" : "[ ]"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: row.isDone ? Theme.green : (root.selected === index ? Theme.on(Theme.selection) : Theme.fgDim)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Info Spalte
                        Column {
                            width: parent.width - Theme.cellW * 7
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Row {
                                spacing: 8
                                Text {
                                    text: modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.strikeout: row.isDone
                                    color: row.isDone ? Theme.muted : (root.selected === index ? Theme.on(Theme.selection) : Theme.fg)
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 260)
                                }

                                Text {
                                    text: "· " + String(modelData.routine || "all").toUpperCase()
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.fgDim
                                }

                                Text {
                                    text: "SERIE " + row.streakData.current + "T"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.yellow
                                }

                                Text {
                                    text: "SCHILD " + (modelData.shields || 2)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.fgDim
                                }
                            }

                            Row {
                                spacing: 6
                                visible: modelData.mode === "COUNTER" || modelData.mode === "NUMBER" || modelData.mode === "DURATION" || modelData.mode === "TIMER"

                                Text {
                                    text: row.curVal + " / " + modelData.targetValue + " " + (modelData.unit || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.fgDim
                                }
                            }
                        }
                    }

                    // Interaktive Knoepfe
                    Row {
                        id: actionRow
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW * 0.5
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.cellW * 0.5

                            // Kompakte Stepper fuer Counter.
                            Rectangle {
                                visible: modelData.mode === "COUNTER"
                                width: Theme.cellW * 4
                                height: Theme.cellH * 1.5
                                color: Theme.bgLight
                                border.width: Theme.borderWidth
                                border.color: Theme.muted

                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 13
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.fgDim
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.increment(modelData.id, -1)
                                }
                            }

                            Rectangle {
                                visible: modelData.mode === "COUNTER"
                                width: Theme.cellW * 5
                                height: Theme.cellH * 1.5
                                color: Theme.alpha(Theme.accent, 0.16)
                                border.width: Theme.borderWidth
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "+1"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.increment(modelData.id, 1)
                                }
                            }

                            // Dauer-Schnellknoepfe
                            Rectangle {
                                visible: modelData.mode === "DURATION"
                                width: Theme.cellW * 6
                                height: Theme.cellH * 1.5
                                color: Theme.alpha(Theme.accent, 0.16)
                                border.width: Theme.borderWidth
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "+15m"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.increment(modelData.id, 15)
                                }
                            }

                            // TIMER (Focus): der Pomodoro laeuft in der App --
                            // hier markiert der Knopf die Fokus-Session erledigt
                            // (ersetzt fuer diesen Modus die Checkbox).
                            Rectangle {
                                visible: modelData.mode === "TIMER"
                                width: Theme.cellW * 11
                                height: Theme.cellH * 1.5
                                color: Theme.alpha(Theme.magenta, 0.16)
                                border.width: Theme.borderWidth
                                border.color: Theme.magenta

                                Text {
                                    anchors.centerIn: parent
                                    text: row.isDone ? "FOCUS ✓" : "FOCUS"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : Theme.magenta
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.toggle(modelData.id)
                                }
                            }

                            // Checkbox Button
                            Rectangle {
                                visible: modelData.mode !== "TIMER"
                                width: Theme.cellW * 9
                                height: Theme.cellH * 1.5
                                color: Theme.alpha(row.isDone ? Theme.green : Theme.accent, 0.14)
                                border.width: Theme.borderWidth
                                border.color: row.isDone ? Theme.green : Theme.muted

                                Text {
                                    anchors.centerIn: parent
                                    text: row.isDone ? "DONE" : "ERLEDIGEN"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: root.selected === index ? Theme.on(Theme.selection) : (row.isDone ? Theme.green : Theme.fgDim)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.toggle(modelData.id)
                                }
                            }

                            // Delete Button
                            Text {
                                text: "×"
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                color: root.selected === index ? Theme.on(Theme.selection) : Theme.red
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.remove(modelData.id)
                                }
                            }
                        }
                    }
                }

            // ── Eingabezeile fuer neue Gewohnheiten ─────────────────────────
            Rectangle {
                width: parent.width
                height: Theme.cellH * 2.2
                radius: Theme.radius
                color: "transparent"
                border.width: Theme.borderWidth
                border.color: input.activeFocus ? Theme.accent : Theme.muted

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: "> "
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.green
                }

                TextInput {
                    id: input
                    anchors.left: prompt.right
                    anchors.leftMargin: Theme.cellW * 0.5
                    anchors.right: hintText.left
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.fg
                    focus: true
                    selectByMouse: true
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.on(Theme.selection)

                    Keys.onReturnPressed: root.accept()
                    Keys.onEnterPressed: root.accept()
                    Keys.onEscapePressed: {
                        if (input.text !== "") {
                            input.text = "";
                        } else {
                            root.close();
                        }
                    }
                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    Keys.onTabPressed: (event) => {
                        event.accepted = true;
                        root.toggleCurrent();
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === ""
                        text: "new habit, optional // routine"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgDim
                    }
                }

                Text {
                    id: hintText
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: "[ ENTER ]"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.accent
                }
            }
        }
    }
}
