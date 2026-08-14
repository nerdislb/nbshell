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
    color: Habits.progressPercent >= 100 ? Theme.green : (Habits.doneCount > 0 ? Theme.accent : Theme.textDim)

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
                height: Theme.cellH * 1.4

                Line {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "GEWOHNHEITEN (" + Habits.doneCount + "/" + Habits.count + " — " + Habits.progressPercent + "%)"
                    color: Theme.accent
                }

                Line {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "[ matrix öffnen ]"
                    color: Theme.cyan

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (panel.closePopout) panel.closePopout();
                            Runtime.habitsOpen = true;
                        }
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
                text: "Keine Gewohnheiten eingerichtet"
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
                            visible: modelData.mode === "COUNTER" || modelData.mode === "NUMBER"
                            text: "(" + row.curVal + "/" + modelData.targetValue + ")"
                            color: Theme.fgDim
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        id: actionRow
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            visible: modelData.mode === "COUNTER"
                            width: 24
                            height: 20
                            radius: 2
                            color: Theme.alpha(Theme.accent, 0.2)
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "+1"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: Theme.accent
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Habits.increment(modelData.id, 1)
                            }
                        }

                        Rectangle {
                            width: 22
                            height: 20
                            radius: 2
                            color: row.isDone ? Theme.green : "transparent"
                            border.width: 1
                            border.color: row.isDone ? Theme.green : Theme.muted

                            Text {
                                anchors.centerIn: parent
                                text: row.isDone ? "✔" : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: Theme.bg
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Habits.toggle(modelData.id)
                            }
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
                text: "Rechtsklick: Vollbild-Heatmap & Verwaltung"
                color: Theme.fgDim
                font.pixelSize: 10
            }
        }
    }
}
