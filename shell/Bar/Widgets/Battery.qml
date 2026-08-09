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

            // Der Ladestand als Marke rechts oben: die eine Zahl, die man
            // ohne Lesen erkennen will.
            PanelHead {
                rowWidth: panel.rowWidth
                icon: PowerService.charging ? Icons.batteryCharging : Icons.battery(PowerService.percent)
                title: PowerService.stateText
                subtitle: "Energie"
                badge: PowerService.percent + " %"
                badgeColor: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.fgDim)
            }

            LevelBar {
                cells: 30
                value: PowerService.percent
                interactive: false
                fillColor: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.accent)
            }

            Facts {
                rowWidth: panel.rowWidth
                pairs: [
                    {
                        "label": PowerService.charging ? "Voll in" : "Rest",
                        "value": PowerService.full ? "voll" : PowerService.timeText
                    },
                    {
                        "label": PowerService.rate > 0 ? "Leistung" : "",
                        "value": PowerService.rate > 0 ? PowerService.rate.toFixed(1) + " W" : ""
                    },
                    {
                        "label": PowerService.health > 0 ? "Zustand" : "",
                        "value": PowerService.health > 0 ? PowerService.health + " %" : "",
                        "color": PowerService.health > 0 && PowerService.health < 70 ? Theme.yellow : Theme.fg
                    }
                ]
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "PROFIL  (tuned)"
            }

            // Untereinander stand hier vorher eine Liste, in der nur das
            // aktive Profil markiert war. Nebeneinander sieht man dasselbe --
            // und dazu, wie viele es ueberhaupt gibt.
            Segments {
                rowWidth: panel.rowWidth
                options: PowerService.profiles
                current: PowerService.activeProfile
                onChosen: value => PowerService.setProfile(value)
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
