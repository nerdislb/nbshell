import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    readonly property var pit: Plugins.serviceFor("pit-wall")
    readonly property var state: pit ? pit.raceState : ({ status: "off" })
    readonly property var race: state && state.race ? state.race : null

    label: "F1"
    icon: String.fromCodePoint(0xF023B)
    text: pit ? pit.label : "—"
    color: pit && pit.isLive ? Theme.green : Theme.text
    active: pit && pit.isLive
    interactive: true
    slotChars: 10

    onRightClicked: if (pit) pit.refresh()

    function localTime(ms) {
        return Qt.formatDateTime(new Date(ms), "ddd dd MMM  HH:mm");
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null
            // The upstream Omarchy panel targets roughly 420 px. That is too
            // tight for nbshell's 14 px monospace type once both standings
            // tables are shown side by side, so give the native port room to
            // keep names and points in separate columns.
            readonly property real panelWidth: Theme.cellW * 68
            readonly property real standingsGap: Theme.cellW * 3
            readonly property real standingsWidth: (panelWidth - standingsGap) / 2
            readonly property var pit: root.pit
            readonly property var state: root.state
            readonly property var race: root.race
            readonly property var sessions: race ? race.sessions : []
            readonly property var liveRows: pit ? pit.liveRows : []
            readonly property var drivers: pit ? pit.driverRows.slice(0, pit.standingsLimit) : []
            readonly property var constructors: pit ? pit.constructorRows.slice(0, pit.standingsLimit) : []

            width: panelWidth
            spacing: Theme.cellH * 0.5

            component Line: Text {
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                renderType: Text.QtRendering
                textFormat: Text.PlainText
            }

            component Section: Text {
                width: panel.panelWidth
                color: Theme.readable(Theme.accent, Theme.bg)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                font.bold: true
                renderType: Text.QtRendering
                textFormat: Text.PlainText
            }

            Row {
                width: panel.panelWidth
                spacing: Theme.cellW

                Column {
                    width: panel.panelWidth - openButton.width - refreshButton.width - parent.spacing * 2
                    spacing: 0

                    Section {
                        width: parent.width
                        text: panel.race ? panel.race.name.toUpperCase() : "PIT WALL"
                        elide: Text.ElideRight
                    }

                    Line {
                        width: parent.width
                        text: panel.race
                            ? ("ROUND " + panel.race.round + "  ·  " + panel.race.circuit)
                            : (panel.pit && panel.pit.loading ? "Loading Formula 1 data…" : "No upcoming session")
                        color: Theme.fgDim
                        elide: Text.ElideRight
                    }
                }

                ControlButton {
                    id: openButton
                    text: "Open window"
                    onTriggered: {
                        if (panel.closePopout)
                            panel.closePopout();
                        Plugins.summon("pit-wall", "{}");
                    }
                }

                ControlButton {
                    id: refreshButton
                    text: panel.pit && panel.pit.loading ? "Loading…" : "Refresh"
                    enabled: panel.pit && !panel.pit.loading
                    onTriggered: panel.pit.refresh()
                }
            }

            Rectangle {
                width: panel.panelWidth
                height: Theme.borderWidth
                color: Theme.muted
            }

            Line {
                visible: panel.pit && panel.pit.errorText !== ""
                width: panel.panelWidth
                text: panel.pit ? panel.pit.errorText : ""
                color: Theme.yellow
            }

            Section {
                visible: panel.pit && panel.pit.isLive
                text: "LIVE TIMING" + (panel.pit.trackTag !== "" ? "  ·  " + panel.pit.trackTag : "")
            }

            Repeater {
                model: panel.pit && panel.pit.isLive ? panel.liveRows : []

                Row {
                    required property var modelData
                    required property int index
                    width: panel.panelWidth
                    spacing: Theme.cellW

                    Line { width: Theme.cellW * 3; text: String(modelData.pos).padStart(2, " ") }
                    Line {
                        width: Theme.cellW * 8
                        text: modelData.acronym
                        color: index === 0 ? Theme.green : Theme.fg
                        font.bold: index === 0
                    }
                    Line { width: Theme.cellW * 36; text: modelData.team; color: Theme.fgDim; elide: Text.ElideRight }
                    Line { width: Theme.cellW * 18; text: modelData.gap; horizontalAlignment: Text.AlignRight }
                }
            }

            Section { text: "RACE WEEKEND" }

            Repeater {
                model: panel.sessions

                Row {
                    required property var modelData
                    width: panel.panelWidth
                    spacing: Theme.cellW

                    readonly property bool next: panel.state && panel.state.session
                        && panel.state.session.startMs === modelData.startMs
                    readonly property bool past: modelData.endMs < Date.now()

                    Line {
                        width: Theme.cellW * 22
                        text: modelData.label.toUpperCase()
                        color: parent.next ? Theme.readable(Theme.accent, Theme.bg)
                            : (parent.past ? Theme.muted : Theme.fg)
                        font.bold: parent.next
                    }
                    Line {
                        width: Theme.cellW * 44
                        text: root.localTime(modelData.startMs)
                        color: parent.next ? Theme.fg : (parent.past ? Theme.muted : Theme.fgDim)
                    }
                }
            }

            Rectangle {
                width: panel.panelWidth
                height: Theme.borderWidth
                color: Theme.muted
            }

            Row {
                width: panel.panelWidth
                spacing: panel.standingsGap

                Column {
                    width: panel.standingsWidth
                    spacing: Theme.cellH * 0.3

                    Section { width: parent.width; text: "DRIVERS" }

                    Repeater {
                        model: panel.drivers
                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: Theme.cellW
                            Line { width: Theme.cellW * 3; text: String(modelData.pos) }
                            Line { width: Theme.cellW * 9; text: modelData.code || modelData.name.slice(0, 8); elide: Text.ElideRight }
                            Line { width: parent.width - Theme.cellW * 14; text: modelData.points + " PTS"; color: Theme.fgDim; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                Column {
                    width: panel.standingsWidth
                    spacing: Theme.cellH * 0.3

                    Section { width: parent.width; text: "CONSTRUCTORS" }

                    Repeater {
                        model: panel.constructors
                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: Theme.cellW
                            Line { width: Theme.cellW * 3; text: String(modelData.pos) }
                            Line { width: Theme.cellW * 18; text: modelData.name; elide: Text.ElideRight }
                            Line { width: parent.width - Theme.cellW * 23; text: modelData.points; color: Theme.fgDim; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }
            }

            Line {
                width: panel.panelWidth
                text: panel.pit && panel.pit.lastUpdated.getTime() > 0
                    ? "Updated " + Qt.formatDateTime(panel.pit.lastUpdated, "HH:mm") + "  ·  right-click the bar widget to refresh"
                    : "Data: Jolpica + OpenF1"
                color: Theme.muted
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
