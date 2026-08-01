import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Widgets

// Akku. Beim Laden steht ein Pfeil davor, unter 20 % faerbt sich die Zelle rot
// -- mehr Zustaende braucht eine Statuszeile nicht.
Cell {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false

    shown: device !== null && device.isLaptopBattery
    text: (charging ? "↑" : "") + "BAT " + percent + "%"
    color: percent <= 20 && !charging ? Theme.red : (charging ? Theme.green : Theme.fg)
}
