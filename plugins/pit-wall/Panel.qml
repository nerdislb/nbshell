import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

Item {
    id: root

    property var shell: null
    property var manifest: null
    property var service: null
    property bool opened: false
    property bool closingFromHost: false

    readonly property string pluginId: manifest && manifest.id
        ? String(manifest.id) : "pit-wall"
    readonly property var state: service ? service.raceState : ({ status: "off" })
    readonly property var race: state && state.race ? state.race : null
    readonly property var session: state && state.session ? state.session : null

    function open(payloadJson) {
        closingFromHost = false;
        opened = true;
        if (service)
            service.liveTick();
        Qt.callLater(function() { focusScope.forceActiveFocus(); });
    }

    function close() {
        closingFromHost = true;
        opened = false;
        closingFromHost = false;
    }

    function requestClose() {
        if (shell && typeof shell.hide === "function")
            shell.hide(pluginId);
        else
            close();
    }

    function localTime(ms) {
        return Qt.formatDateTime(new Date(ms), "ddd dd MMM  HH:mm");
    }

    function sectorColor(state) {
        if (state === "overall") return Theme.magenta;
        if (state === "personal") return Theme.green;
        if (state === "complete") return Theme.yellow;
        return Theme.muted;
    }

    function tyreColor(compound) {
        const value = String(compound || "").toUpperCase();
        if (value === "SOFT") return Theme.red;
        if (value === "MEDIUM") return Theme.yellow;
        if (value === "INTERMEDIATE") return Theme.green;
        if (value === "WET") return Theme.blue;
        return Theme.fg;
    }

    function tyreLabel(details) {
        const value = String(details && details.compound ? details.compound : "").toUpperCase();
        const shortName = value === "INTERMEDIATE" ? "INT" : (value ? value.slice(0, 4) : "—");
        return shortName + (details && details.tyreLaps ? " " + details.tyreLaps : "");
    }

    FloatingWindow {
        id: window

        visible: root.opened
        title: "Pit Wall"
        color: Theme.bg
        implicitWidth: Theme.cellW * 92
        implicitHeight: Theme.cellH * 34
        minimumSize: Qt.size(Theme.cellW * 72, Theme.cellH * 25)

        onVisibleChanged: {
            if (!visible && root.opened && !root.closingFromHost)
                root.requestClose();
        }

        PanelSurface {
            anchors.fill: parent
            accentBorder: service && service.isLive

            FocusScope {
                id: focusScope
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                focus: true

                Keys.onEscapePressed: root.requestClose()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_R && service) {
                        service.refresh();
                        event.accepted = true;
                    }
                }

                Column {
                    id: content
                    anchors.fill: parent
                    spacing: Theme.cellH * 0.55

                    component Label: Text {
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBody
                        renderType: Text.QtRendering
                        textFormat: Text.PlainText
                    }

                    component Heading: Text {
                        color: Theme.readable(Theme.accent, Theme.bg)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitle
                        font.bold: true
                        renderType: Text.QtRendering
                        textFormat: Text.PlainText
                    }

                    Row {
                        width: content.width
                        spacing: Theme.cellW * 2

                        Column {
                            width: content.width - actions.width - parent.spacing
                            spacing: Theme.spaceXs

                            Heading {
                                width: parent.width
                                text: root.race ? root.race.name.toUpperCase() : "PIT WALL"
                                elide: Text.ElideRight
                            }

                            Label {
                                width: parent.width
                                text: root.race
                                    ? ("ROUND " + root.race.round + "  ·  " + root.race.circuit)
                                    : (service && service.loading ? "Loading Formula 1 data…" : "No active race weekend")
                                color: Theme.fgDim
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: actions
                            spacing: Theme.cellW

                            ControlButton {
                                text: service && service.loading ? "Loading…" : "Refresh"
                                enabled: service && !service.loading
                                onTriggered: service.refresh()
                            }

                            ControlButton {
                                text: "Close"
                                onTriggered: root.requestClose()
                            }
                        }
                    }

                    Rectangle {
                        visible: service && service.isLive && service.errorText !== ""
                        width: content.width
                        height: Theme.cellH * 4
                        color: Theme.mix(Theme.bg, Theme.yellow, 0.08)
                        border.width: Theme.borderWidth
                        border.color: Theme.yellow

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - Theme.cellW * 4
                            spacing: Theme.cellH * 0.35

                            Heading {
                                width: parent.width
                                text: "LIVE TIMING UNAVAILABLE"
                                color: Theme.yellow
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label {
                                width: parent.width
                                text: service ? service.errorText : ""
                                color: Theme.fgDim
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Rectangle {
                        width: content.width
                        height: Theme.borderWidth
                        color: Theme.muted
                    }

                    Row {
                        width: content.width
                        spacing: Theme.cellW * 2

                        Heading {
                            width: Theme.cellW * 20
                            text: service && service.isLive ? "LIVE TIMING" : "NEXT SESSION"
                            color: service && service.isLive ? Theme.green : Theme.readable(Theme.accent, Theme.bg)
                        }

                        Label {
                            width: Theme.cellW * 10
                            text: service && service.trackTag !== "" ? service.trackTag : ""
                            color: Theme.yellow
                            font.bold: true
                        }

                        Label {
                            width: parent.width - Theme.cellW * 32 - parent.spacing * 2
                            text: service && service.isLive
                                ? "AUTO REFRESH · " + (service.bridgeAvailable ? "2 S" : "20 S")
                                : (root.session ? root.session.label.toUpperCase() + "  ·  " + root.localTime(root.session.startMs) : "SEASON COMPLETE")
                            color: Theme.fgDim
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Row {
                        width: content.width
                        spacing: Theme.cellW

                        Label { width: Theme.cellW * 4; text: "POS"; color: Theme.muted }
                        Label { width: Theme.cellW * 9; text: "DRIVER"; color: Theme.muted }
                        Label { width: Theme.cellW * 8; text: "TYRE"; color: Theme.muted }
                        Label { width: Theme.cellW * 9; text: "S1"; color: Theme.muted; horizontalAlignment: Text.AlignRight }
                        Label { width: Theme.cellW * 9; text: "S2"; color: Theme.muted; horizontalAlignment: Text.AlignRight }
                        Label { width: Theme.cellW * 9; text: "S3"; color: Theme.muted; horizontalAlignment: Text.AlignRight }
                        Label { width: Theme.cellW * 12; text: "BEST"; color: Theme.muted; horizontalAlignment: Text.AlignRight }
                        Label { width: content.width - Theme.cellW * 60 - parent.spacing * 7; text: "GAP"; color: Theme.muted; horizontalAlignment: Text.AlignRight }
                    }

                    Rectangle {
                        visible: !service || !service.isLive
                        width: content.width
                        height: Theme.cellH * 8
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: Theme.muted

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - Theme.cellW * 4
                            spacing: Theme.cellH * 0.5

                            Heading {
                                width: parent.width
                                text: "WAITING FOR LIVE TIMING"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label {
                                width: parent.width
                                text: root.session
                                    ? root.session.label.toUpperCase() + " starts " + root.localTime(root.session.startMs)
                                    : "No upcoming Formula 1 session"
                                color: Theme.fgDim
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    Repeater {
                        model: service && service.isLive && service.errorText === "" ? service.liveRows : []

                        Rectangle {
                            required property var modelData
                            required property int index
                            width: content.width
                            height: Theme.cellH * 1.55
                            color: index === 0 ? Theme.mix(Theme.bg, Theme.green, 0.12)
                                : (index % 2 ? Theme.mix(Theme.bg, Theme.fg, 0.035) : "transparent")
                            border.width: index === 0 ? Theme.borderWidth : 0
                            border.color: Theme.green

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.cellW
                                anchors.rightMargin: Theme.cellW
                                spacing: Theme.cellW

                                Label { width: Theme.cellW * 3; text: String(modelData.pos).padStart(2, " "); font.bold: index === 0 }
                                Label { width: Theme.cellW * 9; text: modelData.acronym; color: index === 0 ? Theme.green : Theme.fg; font.bold: true }
                                Label {
                                    width: Theme.cellW * 8
                                    text: root.tyreLabel(modelData.details)
                                    color: root.tyreColor(modelData.details ? modelData.details.compound : "")
                                    font.bold: true
                                }
                                Repeater {
                                    model: modelData.details && modelData.details.sectors
                                        ? modelData.details.sectors : [{}, {}, {}]
                                    Label {
                                        required property var modelData
                                        width: Theme.cellW * 9
                                        text: modelData.value || "—"
                                        color: root.sectorColor(modelData.state || "")
                                        horizontalAlignment: Text.AlignRight
                                        font.bold: modelData.state === "overall"
                                    }
                                }
                                Label {
                                    width: Theme.cellW * 12
                                    text: modelData.details && modelData.details.bestLap
                                        ? modelData.details.bestLap : "—"
                                    horizontalAlignment: Text.AlignRight
                                }
                                Label {
                                    width: parent.width - Theme.cellW * 59 - parent.spacing * 7
                                    text: modelData.details && modelData.details.inPit ? "PIT" : modelData.gap
                                    color: modelData.details && modelData.details.inPit ? Theme.yellow : Theme.fg
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }

                    Item { width: 1; height: Theme.cellH * 0.2 }

                    Row {
                        width: content.width
                        spacing: Theme.cellW * 2

                        Label {
                            width: parent.width * 0.55
                            text: "DATA · JOLPICA F1 + F1 LIVE TIMING"
                            color: Theme.muted
                        }

                        Label {
                            width: parent.width * 0.45 - parent.spacing
                            text: service && service.lastUpdated.getTime() > 0
                                ? "UPDATED " + Qt.formatDateTime(service.lastUpdated, "HH:mm:ss") + "  ·  R TO REFRESH"
                                : "LOADING…"
                            color: Theme.muted
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
}
