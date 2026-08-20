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
                                ? "AUTO REFRESH · 20 S"
                                : (root.session ? root.session.label.toUpperCase() + "  ·  " + root.localTime(root.session.startMs) : "SEASON COMPLETE")
                            color: Theme.fgDim
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Row {
                        width: content.width
                        spacing: Theme.cellW

                        Label { width: Theme.cellW * 4; text: "POS"; color: Theme.muted }
                        Label { width: Theme.cellW * 10; text: "DRIVER"; color: Theme.muted }
                        Label { width: content.width - Theme.cellW * 38; text: "TEAM"; color: Theme.muted }
                        Label { width: Theme.cellW * 21; text: "INTERVAL"; color: Theme.muted; horizontalAlignment: Text.AlignRight }
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
                        model: service && service.isLive ? service.liveRows : []

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
                                Label { width: Theme.cellW * 10; text: modelData.acronym; color: index === 0 ? Theme.green : Theme.fg; font.bold: true }
                                Label { width: parent.width - Theme.cellW * 38; text: modelData.team; color: Theme.fgDim; elide: Text.ElideRight }
                                Label { width: Theme.cellW * 20; text: modelData.gap; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }

                    Item { width: 1; height: Theme.cellH * 0.2 }

                    Row {
                        width: content.width
                        spacing: Theme.cellW * 2

                        Label {
                            width: parent.width * 0.55
                            text: "DATA · JOLPICA F1 + OPENF1"
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
