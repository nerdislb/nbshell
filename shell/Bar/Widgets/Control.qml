import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Networking
import qs.Common
import qs.Services
import qs.Widgets

// Control Center: Helligkeit, WLAN, Bluetooth in einem Popout.
//
// Die Zelle in der Leiste zeigt schon das Wichtigste -- an welchem Netz man
// haengt. Ein reiner Knopf waere verschenkter Platz.
Cell {
    id: root

    interactive: true
    popoutTakesKeyboard: true

    // Kabel schlaegt Funk: haengt beides, ist das Kabel die Verbindung, ueber
    // die es laeuft.
    icon: Net.wiredConnected ? (Net.internetRestricted ? Icons.lanRestricted : Icons.lan)
        : (Net.activeWifi ? (Net.internetRestricted ? Icons.wifiRestricted : Icons.wifiSignal(Net.activeWifi.signalStrength))
            : (Net.wifiEnabled ? Icons.wifiDisconnected : Icons.wifiOff))
    // Der Netzname stand frueher daneben. Das Symbol sagt schon, ob und
    // wie man haengt -- im Popout steht der Name ohnehin. Ohne Symbole
    // bleibt er, sonst waere die Zelle leer.
    label: "NET"
    text: Config.widgetIcons ? "" : (Net.summary.length > 12 ? (Net.summary.substring(0, 11) + "…") : Net.summary)
    color: Theme.text
    custom: root.wantIcon
    Row {
        visible: root.custom
        spacing: root.shownText !== "" ? Math.round(Theme.cellW * 0.6) : 0
        Item {
            width: Theme.barIconSlot
            height: Theme.cellH
            DuoGlyph {
                anchors.centerIn: parent
                // The compound mark needs more ink than a single font glyph,
                // but remains inside the existing cell and bar height.
                width: Math.min(Theme.barHeight - Theme.padY, Theme.barIconCanvas * 1.4)
                height: width
                batteryPresent: PowerService.available
                battery: PowerService.available ? PowerService.device.percentage : 0
                charging: PowerService.available && PowerService.charging
                lowBattery: PowerService.available && UPower.onBattery && battery <= 0.20
                wifiConnected: Net.activeWifi !== null
                wifiEnabled: Net.wifiEnabled
                signalStrength: Net.activeWifi?.signalStrength ?? 0
                wired: Net.wiredConnected
                bluetoothEnabled: Bt.enabled
                foreground: root.shownColor
                urgent: Theme.readable(Theme.red, Theme.barSurface, 3)
            }
        }
        Item {
            visible: root.shownText !== ""
            width: customLabel.implicitWidth
            height: Theme.cellH
            Line { id: customLabel; anchors.centerIn: parent; text: root.shownText; color: root.shownColor }
        }
    }
    accessibilityName: "Network, " + Net.summary + ", " + Net.connectivityLabel
        + "; battery " + (PowerService.available ? PowerService.percent + " percent, " + PowerService.stateText : "unavailable")
        + "; Bluetooth " + (Bt.enabled ? "on" : "off")

    preview: Component {
        BarPreview {
            icon: root.icon
            title: Net.summary
            subtitle: Net.connectivityLabel
            badge: Net.activeWifi ? Net.percentOf(Net.activeWifi.signalStrength) + " %" : (Net.wiredConnected ? "LAN" : "")
            badgeColor: Net.internetRestricted ? Theme.yellow : (Net.online ? Theme.fg : Theme.fgDim)
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Battery", "value": PowerService.available ? PowerService.percent + " %, " + PowerService.stateText : "unavailable" },
                        { "label": "Brightness", "value": Brightness.available ? Brightness.percent + " %" : "unavailable" },
                        { "label": "Bluetooth", "value": Bt.connected.length + " connected" },
                        { "label": "Wi-Fi", "value": Net.wifiEnabled ? "enabled" : "disabled", "color": Net.wifiEnabled ? Theme.fg : Theme.yellow },
                        { "label": "VPN", "value": Net.activeVpns.length ? Net.activeVpns[0].name : "disconnected", "color": Net.activeVpns.length ? Theme.green : Theme.fgDim }
                    ]
                }
            ]
        }
    }

    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.controlOpen = root.popoutVisible

    popoutCloseOnLeave: false
    popoutInsetBorder: true
    popoutPadding: Theme.networkPadding
    popoutBorderWidth: Theme.networkBorderWidth

    popout: Component {
        NetworkPanel {
            networkIcon: root.icon
            availableWidth: root.Screen.width - Config.gap * 2
                - (root.popoutPadding + root.popoutBorderWidth) * 2
        }
    }
}
