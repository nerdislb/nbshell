import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Gewohnheiten (nbHabits): Erledigte/Gesamt in der Leiste, Liste im Popout.
//
// Rechtsklick oeffnet das grosse Vollbildfenster mit 20-Wochen-Heatmap Matrix.
Cell {
    id: root

    shown: Habits.enabled
    quiet: Habits.count === 0
    slotChars: 4
    interactive: true
    label: "HABITS"
    icon: Icons.habit
    text: Habits.doneCount + "/" + Habits.count
    color: Habits.progressPercent >= 100 ? Theme.green : (Habits.doneCount > 0 ? Theme.barAccent : Theme.textDim)

    onRightClicked: Runtime.habitsOpen = true

    popout: Component {
        Column {
            id: panel

            property var closePopout: null
            readonly property real rowWidth: 56 * Theme.cellW

            spacing: Theme.cellH * 0.2

            // Header
            Item {
                width: panel.rowWidth
                height: Theme.denseRowHeight

                Line {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "HABITS (" + Habits.doneCount + "/" + Habits.count + " — " + Habits.progressPercent + "%)"
                    color: Theme.accent
                }

                ActionButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Open matrix"
                    tone: "primary"
                    accentColor: Theme.cyan
                    compact: true
                    onTriggered: {
                        if (panel.closePopout) panel.closePopout();
                        Runtime.habitsOpen = true;
                    }
                }
            }

            // Mini Progress Bar
            Rectangle {
                width: panel.rowWidth
                height: 3
                radius: 1
                color: Theme.muted

                Rectangle {
                    width: Math.round(parent.width * (Habits.progressPercent / 100.0))
                    height: parent.height
                    radius: 1
                    color: Habits.progressPercent >= 100 ? Theme.green : Theme.accent
                }
            }

            Line {
                visible: Habits.habits.length === 0
                text: "No habits configured"
                color: Theme.muted
            }

            // Habit Items
            Repeater {
                model: Habits.habits.slice(0, 8)

                Rectangle {
                    id: row
                    required property var modelData

                    readonly property var todayEntry: Habits.todayMap[String(modelData.id)]
                    readonly property bool isDone: todayEntry ? todayEntry.isCompleted : false
                    readonly property real curVal: todayEntry ? todayEntry.currentValue : 0.0
                    readonly property var streakData: Habits.calculateStreak(modelData.id)

                    width: panel.rowWidth
                    height: Theme.cellH * 1.6
                    radius: Theme.radius
                    color: mouse.hovered ? Theme.hover : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.right: actionRow.left
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.icon || "✨"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Line {
                            text: modelData.name
                            color: row.isDone ? Theme.muted : Theme.fg
                            font.strikeout: row.isDone
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 220)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Line {
                            text: "🔥" + row.streakData.current + "d"
                            color: Theme.yellow
                            visible: row.streakData.current > 0
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Line {
                            visible: modelData.mode === "COUNTER" || modelData.mode === "NUMBER" || modelData.mode === "DURATION" || modelData.mode === "TIMER"
                            text: "(" + row.curVal + "/" + modelData.targetValue + (modelData.mode === "TIMER" || modelData.mode === "DURATION" ? " min" : "") + ")"
                            color: Theme.fgDim
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        id: actionRow
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceXs

                        // Geteilte Knoepfe statt gebauter Kaestchen: die
                        // frueheren 24x20-Rectangles mit nackter MouseArea
                        // hatten weder Fokus noch Tastatur noch eine
                        // Accessibility-Rolle. `ActionButton` bringt alles drei
                        // mit und ist die dichte Variante fuer Popout-Zeilen.
                        ActionButton {
                            visible: modelData.mode === "COUNTER"
                            compact: true
                            text: "+1"
                            accessibleName: "Increase " + modelData.name
                            onTriggered: Habits.increment(modelData.id, 1)
                        }

                        // TIMER (Focus): der eigentliche Pomodoro laeuft in der
                        // App; hier markiert die Aktion die Fokus-Session als
                        // erledigt (ersetzt fuer diesen Modus die Checkbox).
                        ActionButton {
                            visible: modelData.mode === "TIMER"
                            compact: true
                            text: row.isDone ? "Focus done" : "Focus"
                            tone: row.isDone ? "primary" : "secondary"
                            accessibleName: "Toggle focus session for " + modelData.name
                            onTriggered: Habits.toggle(modelData.id)
                        }

                        ActionButton {
                            visible: modelData.mode !== "TIMER"
                            compact: true
                            text: row.isDone ? "Done" : "Complete"
                            tone: row.isDone ? "primary" : "secondary"
                            accessibleName: "Toggle " + modelData.name
                            onTriggered: Habits.toggle(modelData.id)
                        }
                    }

                    HoverHandler {
                        id: mouse
                    }
                }
            }

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 0.4
            }

            Line {
                text: "Right-click: full-screen heatmap and management"
                color: Theme.fgDim
                font.pixelSize: 10
            }
        }
    }
}
