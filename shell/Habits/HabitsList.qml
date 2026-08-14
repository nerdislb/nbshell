import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Der Gewohnheiten-Tracker (nbHabits) als Vollbild-Overlay-Fenster.
//
// Terminal-Aesthetik nach Vorbild von init.Habits:
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
        width: Math.min(parent.width - 40, 720)
        height: Math.min(parent.height * 0.80, 800)

        radius: Theme.radius + 2
        color: Theme.bg
        border.width: 1
        border.color: Theme.muted

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
            anchors.margins: 18
            spacing: 12

            // ── Kopfbereich ────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 24

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        text: "[h]"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                        color: Theme.accent
                    }

                    Text {
                        text: "init.habits"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                        color: Theme.fg
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Rectangle {
                        radius: 3
                        color: Theme.alpha(Theme.accent, 0.15)
                        border.width: 1
                        border.color: Theme.accent
                        width: themeLabel.width + 12
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: themeLabel
                            anchors.centerIn: parent
                            text: Config.theme.toUpperCase()
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: Theme.accent
                        }
                    }

                    Text {
                        text: "[ × CLOSE ]"
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
                height: 54
                radius: Theme.radius
                color: Theme.bgDark
                border.width: 1
                border.color: Theme.alpha(Theme.fg, 0.12)

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    Item {
                        width: parent.width
                        height: 16

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "$ status --today // " + Habits.todayString
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.cyan
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.shortPath !== "" ? root.shortPath : "Sync aktiv"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgDim
                        }
                    }

                    Text {
                        text: Habits.doneCount + " of " + Habits.count + " COMPLETED (" + Habits.progressPercent + "%)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: Habits.progressPercent >= 100 ? Theme.green : Theme.accent
                    }

                    // Progress Bar
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.fg, 0.15)

                        Rectangle {
                            width: Math.round(parent.width * (Habits.progressPercent / 100.0))
                            height: parent.height
                            radius: 2
                            color: Habits.progressPercent >= 100 ? Theme.green : Theme.accent
                        }
                    }
                }
            }

            // ── Contribution Matrix Heatmap ────────────────────────────────
            Rectangle {
                width: parent.width
                height: 110
                radius: Theme.radius
                color: Theme.bgDark
                border.width: 1
                border.color: Theme.alpha(Theme.fg, 0.12)

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 16

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "$ matrix --heatmap // 20-WEEK CONTRIBUTION MATRIX"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.cyan
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "less ░ ▒ ▓ █ more"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.fgDim
                        }
                    }

                    Grid {
                        columns: 20
                        rows: 7
                        rowSpacing: 3
                        columnSpacing: 3
                        flow: Grid.TopToBottom

                        Repeater {
                            model: Habits.matrixCells

                            Rectangle {
                                required property var modelData

                                width: 9
                                height: 9
                                radius: 1

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
                spacing: 6

                readonly property var routines: [
                    { id: "all", label: "📋 ALL" },
                    { id: "morning", label: "🌅 MORNING" },
                    { id: "workout", label: "💪 WORKOUT" },
                    { id: "work", label: "💻 WORK" },
                    { id: "evening", label: "🌙 EVENING" },
                    { id: "general", label: "✨ GENERAL" }
                ]

                Repeater {
                    model: parent.routines

                    Rectangle {
                        required property var modelData

                        width: tabText.width + 16
                        height: 24
                        radius: Theme.radius
                        color: root.selectedRoutine === modelData.id ? Theme.alpha(Theme.accent, 0.2) : "transparent"
                        border.width: 1
                        border.color: root.selectedRoutine === modelData.id ? Theme.accent : Theme.alpha(Theme.fg, 0.15)

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: root.selectedRoutine === modelData.id
                            color: root.selectedRoutine === modelData.id ? Theme.accent : Theme.fgDim
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
                height: parent.height - 330
                clip: true
                spacing: 6
                model: root.filteredHabits

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property var todayEntry: Habits.todayMap[String(modelData.id)]
                    readonly property bool isDone: todayEntry ? todayEntry.isCompleted : false
                    readonly property real curVal: todayEntry ? todayEntry.currentValue : 0.0
                    readonly property var streakData: Habits.calculateStreak(modelData.id)

                    width: habitList.width
                    height: 54
                    radius: Theme.radius
                    color: root.selected === index ? Theme.hover : Theme.bgDark
                    border.width: 1
                    border.color: isDone ? Theme.green : (root.selected === index ? Theme.accent : Theme.alpha(Theme.fg, 0.12))

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.selected = index
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: actionRow.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        // Icon
                        Text {
                            text: modelData.icon || "✨"
                            font.pixelSize: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Info Spalte
                        Column {
                            width: parent.width - 40
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Row {
                                spacing: 8
                                Text {
                                    text: modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.strikeout: row.isDone
                                    color: row.isDone ? Theme.fgDim : Theme.fg
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 260)
                                }

                                Text {
                                    text: "// " + (modelData.routine || "all")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.cyan
                                }

                                Text {
                                    text: "🔥 " + row.streakData.current + "d"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.yellow
                                }

                                Text {
                                    text: "🛡️ " + (modelData.shields || 2)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgDim
                                }
                            }

                            Row {
                                spacing: 6
                                visible: modelData.mode === "COUNTER" || modelData.mode === "NUMBER" || modelData.mode === "DURATION"

                                Text {
                                    text: row.curVal + " / " + modelData.targetValue + " " + (modelData.unit || "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgDim
                                }
                            }
                        }
                    }

                    // Interaktive Knoepfe
                    Row {
                        id: actionRow
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                            // Stepper fuer Counter: [ - ] und [ +1 ]
                            Rectangle {
                                visible: modelData.mode === "COUNTER"
                                width: 28
                                height: 26
                                radius: 3
                                color: Theme.bg
                                border.width: 1
                                border.color: Theme.muted

                                Text {
                                    anchors.centerIn: parent
                                    text: "-"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 13
                                    color: Theme.fg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.increment(modelData.id, -1)
                                }
                            }

                            Rectangle {
                                visible: modelData.mode === "COUNTER"
                                width: 36
                                height: 26
                                radius: 3
                                color: Theme.alpha(Theme.accent, 0.2)
                                border.width: 1
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "+1"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: Theme.accent
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
                                width: 44
                                height: 26
                                radius: 3
                                color: Theme.alpha(Theme.accent, 0.2)
                                border.width: 1
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "+15m"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: Theme.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Habits.increment(modelData.id, 15)
                                }
                            }

                            // Checkbox Button
                            Rectangle {
                                width: row.isDone ? 74 : 64
                                height: 26
                                radius: 3
                                color: row.isDone ? Theme.alpha(Theme.green, 0.2) : Theme.bg
                                border.width: 1
                                border.color: row.isDone ? Theme.green : Theme.muted

                                Text {
                                    anchors.centerIn: parent
                                    text: row.isDone ? "[ ✔ DONE ]" : "[ DONE ]"
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: row.isDone ? Theme.green : Theme.fg
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
                                color: Theme.red
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
                height: 38
                radius: Theme.radius
                color: Theme.bgDark
                border.width: 1
                border.color: input.activeFocus ? Theme.accent : Theme.alpha(Theme.fg, 0.15)

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: ">"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.green
                }

                TextInput {
                    id: input
                    anchors.left: prompt.right
                    anchors.leftMargin: 8
                    anchors.right: hintText.left
                    anchors.rightMargin: 12
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
                        text: "Neue Gewohnheit eintragen (z.B. joggen // workout)..."
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgDim
                    }
                }

                Text {
                    id: hintText
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↵ Hinzufuegen"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.accent
                }
            }
        }
    }
}
