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

    // Die Signalstaerke kommt als Anteil zwischen 0 und 1 herein, nicht als
    // Prozent -- wie `battery` bei Bluetooth-Geraeten. Das ist lange nicht
    // aufgefallen, weil `bars()` alles unter 25 auf einen Balken abrundet:
    // JEDES Netz sah gleich schwach aus, und das hielt man fuer die Lage im
    // Haus. Aufgeflogen ist es erst, als die Zahl selbst in der Kopfzeile
    // stand ("0.78 %").
    //
    // Umgerechnet wird nachsichtig: kommt eines Tages doch ein Wert ueber 1,
    // gilt er als Prozent. So geht nichts kaputt, falls Quickshell das aendert.
    function percentOf(strength) {
        const s = Number(strength);
        if (!isFinite(s) || s <= 0)
            return 0;
        return Math.round(Math.min(100, s <= 1 ? s * 100 : s));
    }

    // Vier Stufen als Balken -- ein Symbol waere hier fehl am Platz.
    function bars(strength) {
        const s = root.percentOf(strength);
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

    // ── Suchen ────────────────────────────────────────────────────────────
    //
    // Die API kennt kein "jetzt einmal suchen", sondern nur einen Schalter:
    // `scannerEnabled` laesst den NetworkManager regelmaessig abtasten. Ein
    // Aus-und-wieder-An stoesst also den naechsten Durchgang sofort an.
    //
    // Fertig meldet niemand -- weder ein Signal noch ein Zustand. Deshalb
    // laeuft die Anzeige auf einer Uhr: acht Sekunden sind mehr, als eine
    // Suche ueblicherweise braucht, und die Liste fuellt sich waehrenddessen
    // ohnehin nach und nach.

    readonly property bool scanning: scanTimer.running

    Timer {
        id: scanTimer
        interval: 8000
    }

    function rescan() {
        if (!root.wifiDevice || !root.wifiEnabled)
            return;
        root.wifiDevice.scannerEnabled = false;
        root.wifiDevice.scannerEnabled = true;
        scanTimer.restart();
    }

    // Solange die Liste jemand ansieht, darf sie sich auffrischen. Danach
    // wieder aus: ein dauerhaft laufender Scanner kostet Strom und weckt das
    // Funkmodul aus dem Ruhezustand.
    function setScanner(value) {
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = value;
        if (!value)
            scanTimer.stop();
    }
}
