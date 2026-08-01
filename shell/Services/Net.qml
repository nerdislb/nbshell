pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// Netzwerk. Quickshell spricht selbst mit dem NetworkManager; hier steht nur,
// was das Control Center davon zeigt.
Singleton {
    id: root

    readonly property var devices: Networking.devices?.values ?? []

    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: devices.find(d => d.type === DeviceType.Ethernet) ?? null

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wiredConnected: wiredDevice?.connected ?? false

    readonly property var activeWifi: (wifiDevice?.networks?.values ?? []).find(n => n.connected) ?? null

    // Staerkste zuerst, und jedes Netz nur einmal: ein Zugangspunkt kann mit
    // mehreren Frequenzen auftauchen.
    readonly property var wifiNetworks: {
        const seen = ({});
        const out = [];
        const all = wifiDevice?.networks?.values ?? [];
        for (var i = 0; i < all.length; i++) {
            const n = all[i];
            if (!n.name || seen[n.name])
                continue;
            seen[n.name] = true;
            out.push(n);
        }
        return out.sort((a, b) => b.signalStrength - a.signalStrength);
    }

    // Kurzfassung fuer die Zelle in der Leiste.
    readonly property string summary: {
        if (activeWifi)
            return activeWifi.name;
        if (wiredConnected)
            return "LAN";
        if (!wifiEnabled)
            return "WLAN aus";
        return "kein Netz";
    }

    readonly property bool online: activeWifi !== null || wiredConnected

    // Vier Stufen als Balken -- ein Symbol waere hier fehl am Platz.
    function bars(strength) {
        const s = Math.max(0, Math.min(100, strength));
        const filled = Math.max(1, Math.ceil(s / 25));
        return "▂▄▆█".substring(0, filled) + "····".substring(0, 4 - filled);
    }

    function needsPassword(network) {
        return !network.known && network.security !== WifiSecurityType.Open;
    }

    function connect(network, psk) {
        if (!network)
            return;
        if (psk && psk.length > 0)
            network.connectWithPsk(psk);
        else
            network.connect();
    }

    function disconnect(network) {
        network?.disconnect();
    }

    function setWifiEnabled(value) {
        Networking.wifiEnabled = value;
    }

    function rescan() {
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = true;
    }
}
