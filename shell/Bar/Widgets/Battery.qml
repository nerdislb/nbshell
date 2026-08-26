import QtQuick
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

    onClicked: PowerService.refreshProfile()

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
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 38 * Theme.cellW
            readonly property var batteries: {
                var out = [{
                    "label": "Notebook",
                    "percent": PowerService.percent,
                    "charging": PowerService.charging,
                    "source": "intern"
                }];
                for (var i = 0; i < Bt.withBattery.length; i++) {
                    const bt = Bt.withBattery[i];
                    out.push({
                        "label": bt.label,
                        "percent": bt.percent,
                        "charging": false,
                        "source": "Bluetooth"
                    });
                }
                const phones = Kdeconnect.devices.filter(d => d.paired && d.reachable && d.capabilities.battery && d.charge >= 0);
                for (var k = 0; k < phones.length; k++) {
                    const phone = phones[k];
                    out.push({
                        "label": phone.name,
                        "percent": phone.charge,
                        "charging": phone.charging,
                        "source": "KDE Connect"
                    });
                }
                return out;
            }
            readonly property int missingReports: Math.max(0, Bt.connected.length - Bt.withBattery.length)

            spacing: Theme.cellH * 0.2

            PanelHead {
                rowWidth: panel.rowWidth
                icon: PowerService.charging ? Icons.batteryCharge(PowerService.percent) : Icons.battery(PowerService.percent)
                title: "Battery levels"
                subtitle: panel.batteries.length + (panel.batteries.length === 1 ? " device" : " devices")
                badge: PowerService.percent + " % internal"
                badgeColor: PowerService.percent <= 20 && !PowerService.charging ? Theme.red : (PowerService.charging ? Theme.green : Theme.fgDim)
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "ALL DEVICES"
            }

            Repeater {
                model: panel.batteries

                Item {
                    required property var modelData
                    width: panel.rowWidth
                    height: Theme.cellH * 2.55

                    Line {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: parent.width * 0.72
                        text: parent.modelData.label + "  ·  " + parent.modelData.source
                        color: Theme.fg
                        elide: Text.ElideRight
                    }
                    Line {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: parent.modelData.percent + " %" + (parent.modelData.charging ? "  ↑" : "")
                        color: parent.modelData.percent <= 15 && !parent.modelData.charging ? Theme.red : (parent.modelData.charging ? Theme.green : Theme.fgBright)
                    }
                    LevelBar {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        cells: 30
                        value: parent.modelData.percent
                        interactive: false
                        fillColor: parent.modelData.percent <= 15 && !parent.modelData.charging ? Theme.red : (parent.modelData.charging ? Theme.green : Theme.accent)
                    }
                }
            }

            Line {
                width: panel.rowWidth
                visible: panel.missingReports > 0
                text: panel.missingReports + (panel.missingReports === 1 ? " Bluetooth device connected without a battery report" : " Bluetooth devices connected without battery reports")
                color: Theme.muted
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "NOTEBOOK"
            }

            Facts {
                rowWidth: panel.rowWidth
                pairs: [
                    {
                        "label": PowerService.charging ? "Full in" : "Remaining",
                        "value": PowerService.full ? "full" : PowerService.timeText
                    },
                    { "label": PowerService.powerLabel, "value": PowerService.powerText },
                    {
                        "label": PowerService.health > 0 ? "Health" : "",
                        "value": PowerService.health > 0 ? PowerService.health + " %" : "",
                        "color": PowerService.health > 0 && PowerService.health < 70 ? Theme.yellow : Theme.fg
                    }
                ]
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "POWER MODE"
            }

            // Untereinander stand hier vorher eine Liste, in der nur das
            // aktive Profil markiert war. Nebeneinander sieht man dasselbe --
            // und dazu, wie viele es ueberhaupt gibt.
            Segments {
                rowWidth: panel.rowWidth
                options: PowerService.profileOptions
                current: PowerService.activeProfile
                onChosen: value => PowerService.setProfile(value)
            }
        }
    }
}
