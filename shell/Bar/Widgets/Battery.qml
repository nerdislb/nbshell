import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Akku. In Ruhe der Ladestand, unter der Maus die Restzeit -- die will man
// selten, aber dann sofort. Ein Klick oeffnet die Energieeinstellungen.
Cell {
    id: root

    shown: PowerService.available
    // Platz fuer die Restzeit, die beim Ueberfahren an die Stelle des
    // Ladestands tritt -- sonst zoege die halbe Leiste mit.
    slotChars: 7
    interactive: true

    // Das Symbol fuellt sich mit dem Ladestand, beim Laden steht der Blitz
    // da -- den Pfeil davor braucht es dann nicht mehr.
    label: PowerService.charging ? "BAT ↑" : "BAT"
    icon: PowerService.charging ? Icons.batteryCharging : Icons.battery(PowerService.percent)
    text: hovered ? PowerService.timeText : (PowerService.percent + "%")

    color: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.text)

    onClicked: PowerService.refreshProfile()

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 38 * Theme.cellW

            spacing: Theme.cellH * 0.2

            Text {
                text: "ENERGIE"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Text {
                width: panel.rowWidth
                text: PowerService.percent + " %   " + PowerService.stateText + (PowerService.full ? "" : "   noch " + PowerService.timeText)
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            LevelBar {
                cells: 30
                value: PowerService.percent
                interactive: false
                fillColor: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.accent)
            }

            Text {
                width: panel.rowWidth
                visible: PowerService.health > 0
                text: "Zustand " + PowerService.health + " %" + (PowerService.rate > 0 ? "   " + PowerService.rate.toFixed(1) + " W" : "")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                bottomPadding: Theme.cellH * 0.4
            }

            Text {
                text: "PROFIL  (tuned)"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: PowerService.profiles

                delegate: Rectangle {
                    id: row

                    required property var modelData

                    readonly property bool current: modelData === PowerService.activeProfile

                    width: panel.rowWidth
                    height: Theme.cellH * 1.4
                    radius: Theme.radius
                    color: mouse.hovered ? Theme.hover : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: (row.current ? "▸ " : "  ") + row.modelData
                        color: row.current ? Theme.readable(Theme.accent, Theme.bg) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }

                    HoverHandler {
                        id: mouse

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: PowerService.setProfile(row.modelData)
                    }
                }
            }

            Text {
                width: panel.rowWidth
                text: "weitere Profile: tuned-adm list"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                topPadding: Theme.cellH * 0.3
            }
        }
    }
}
