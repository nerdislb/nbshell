import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Akku. In Ruhe der Ladestand, unter der Maus die Restzeit -- die will man
// selten, aber dann sofort. Ein Klick oeffnet die Energieeinstellungen.
Cell {
    id: root

    shown: PowerService.available
    // Percentage and battery-side power stay visible at a glance. Hover still
    // swaps to the remaining time without moving the rest of the bar.
    slotChars: 13
    interactive: true

    // Das Symbol fuellt sich mit dem Ladestand, beim Laden steht der Blitz
    // da -- den Pfeil davor braucht es dann nicht mehr.
    label: PowerService.charging ? "BAT ↑" : "BAT"
    icon: PowerService.charging ? Icons.batteryCharge(PowerService.percent) : Icons.battery(PowerService.percent)
    text: hovered ? PowerService.timeText
        : (PowerService.percent + "% · " + PowerService.powerCompactText)

    color: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.text)

    popoutTakesKeyboard: true
    popoutCloseOnLeave: false
    popoutInsetBorder: true
    popoutPadding: Theme.powerPadding
    popoutBorderWidth: Theme.powerBorderWidth

    preview: Component {
        BarPreview {
            icon: PowerService.charging ? Icons.batteryCharge(PowerService.percent) : Icons.battery(PowerService.percent)
            title: "Battery"
            subtitle: PowerService.charging ? "Charging" : "On battery"
            badge: PowerService.percent + " %"
            badgeColor: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.accent)
            content: [
                LevelBar {
                    cells: 32
                    value: PowerService.percent
                    interactive: false
                    fillColor: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.accent)
                },
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": PowerService.charging ? "Full in" : "Remaining", "value": PowerService.timeText },
                        { "label": PowerService.powerLabel, "value": PowerService.powerText },
                        { "label": "Power mode", "value": PowerService.activeProfileLabel }
                    ]
                }
            ]
        }
    }

    popout: Component {
        PowerPanel {
            availableWidth: root.Screen.width - Config.gap * 2
                - (root.popoutPadding + root.popoutBorderWidth) * 2
        }
    }
}
