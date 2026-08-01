pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth. Wie beim Netz spricht Quickshell selbst mit BlueZ; hier steht nur
// die Auswahl, die das Control Center zeigt.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false

    readonly property var devices: adapter?.devices?.values ?? []

    // Verbundene zuerst, dann gekoppelte, dann der Rest -- und nur, was einen
    // Namen hat: unbenannte Adressen helfen niemandem.
    readonly property var sorted: devices.filter(d => d.name || d.deviceName).sort((a, b) => {
        const rank = d => (d.connected ? 0 : (d.paired ? 1 : 2));
        return rank(a) - rank(b);
    })

    readonly property var connected: devices.filter(d => d.connected)

    function label(device) {
        return device?.deviceName || device?.name || device?.address || "?";
    }

    function setEnabled(value) {
        if (adapter)
            adapter.enabled = value;
    }

    function toggleDevice(device) {
        if (!device)
            return;
        if (device.connected)
            device.disconnect();
        else if (device.paired)
            device.connect();
        else
            device.pair();
    }

    function scan(value) {
        if (adapter)
            adapter.discovering = value;
    }
}
