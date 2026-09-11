import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

BarPreview {
    id: root
    title: "Next three days"
    subtitle: !CalendarAgenda.available ? "Enable Calendar to see your events"
        : CalendarAgenda.busy ? "Updating…"
        : CalendarAgenda.error ? "Could not update · open Calendar to retry"
        : CalendarAgenda.stale ? "Offline · showing the last update" : "Click the clock to open Calendar"

    function calendarFor(key) {
        return CalendarAgenda.backend ? CalendarAgenda.backend.calendars.find(c => c.key === key) : null;
    }
    // Same theme-derived calendar order as the full Calendar window.
    function calendarTone(key) {
        const tones = [Theme.accent, Theme.green, Theme.yellow, Theme.blue, Theme.magenta];
        const calendars = CalendarAgenda.backend ? CalendarAgenda.backend.calendars : [];
        return tones[Math.max(0, calendars.findIndex(c => c.key === key)) % tones.length];
    }

    content: [
        Repeater {
            model: CalendarAgenda.available ? CalendarAgenda.days : []
            PanelSurface {
                id: dayGroup
                required property var modelData
                required property int index
                readonly property var entries: CalendarAgenda.eventsOn(modelData)
                width: root.rowWidth
                height: dayContent.implicitHeight + Theme.spaceMd * 2
                accentBorder: index === 0
                raised: true

                Column {
                    id: dayContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spaceMd }
                    spacing: Theme.spaceSm
                    Item {
                        width: parent.width
                        height: Theme.cellH
                        Line {
                            anchors.left: parent.left
                            text: dayGroup.index === 0 ? "Today" : dayGroup.index === 1 ? "Tomorrow" : dayGroup.modelData.toLocaleDateString(Qt.locale(Config.value("locale", "en_US")), "dddd")
                            color: dayGroup.index === 0 ? Theme.accent : Theme.fg
                            font.bold: true
                            font.pixelSize: Theme.fontCaption
                        }
                        Line {
                            anchors.right: parent.right
                            text: dayGroup.modelData.toLocaleDateString(Qt.locale(Config.value("locale", "en_US")), "d MMM")
                            color: Theme.fgDim
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                    Line {
                        width: parent.width
                        visible: dayGroup.entries.length === 0
                        text: CalendarAgenda.busy ? "Loading…" : CalendarAgenda.error || CalendarAgenda.stale ? "No current data" : "No events"
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                    }
                    Repeater {
                        model: dayGroup.entries.slice(0, 3)
                        PanelSurface {
                            id: eventTile
                            required property var modelData
                            readonly property color tone: root.calendarTone(modelData.calendarKey)
                            readonly property var calendar: root.calendarFor(modelData.calendarKey)
                            width: dayContent.width
                            height: eventText.implicitHeight + Theme.spaceSm * 2
                            color: Theme.mix(Theme.panelSurface, tone, 0.10)
                            border.width: 0
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: Theme.spaceXs
                                color: Theme.readable(eventTile.tone, eventTile.color, 3)
                            }
                            Column {
                                id: eventText
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spaceSm; leftMargin: Theme.spaceMd + Theme.spaceXs }
                                spacing: 0
                                Line {
                                    width: parent.width
                                    text: eventTile.modelData.title || "Untitled event"
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontCaption
                                }
                                Line {
                                    width: parent.width
                                    text: (eventTile.modelData.allDay ? "All day" : CalendarAgenda.parse(eventTile.modelData.start).toLocaleTimeString(Qt.locale(), "HH:mm"))
                                        + (eventTile.calendar ? " · " + eventTile.calendar.name : "")
                                    color: Theme.readable(eventTile.tone, eventTile.color, 4.5)
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontCaption
                                }
                            }
                        }
                    }
                    Line {
                        visible: dayGroup.entries.length > 3
                        text: "+" + (dayGroup.entries.length - 3) + " more"
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }
        }
    ]
}
