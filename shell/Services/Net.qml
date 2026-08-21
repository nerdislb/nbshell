pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Netzwerk. Quickshell spricht selbst mit dem NetworkManager; hier steht nur,
// was das Control Center davon zeigt.
Singleton {
    id: root

    readonly property string vpnScript: Qt.resolvedUrl("../scripts/network-vpn.py").toString().replace("file://", "")

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
            return "Wi-Fi off";
        return "no network";
    }

    readonly property bool online: activeWifi !== null || wiredConnected

    // NetworkManager VPN profiles are handled through nmcli because
    // Quickshell's networking API currently exposes Wi-Fi and devices, but
    // not saved VPN connections. Only profile metadata crosses this boundary;
    // credentials remain in NetworkManager and the desktop keyring.
    property bool vpnAvailable: false
    property var vpnProfiles: []
    property string vpnBusyUuid: ""
    property string vpnError: ""
    readonly property var activeVpns: vpnProfiles.filter(profile => profile.active)

    function refreshVpns() {
        if (!vpnList.running)
            vpnList.running = true;
    }

    function toggleVpn(profile) {
        if (!profile || vpnAction.running)
            return;
        vpnBusyUuid = profile.uuid;
        vpnError = "";
        vpnAction.command = ["python3", root.vpnScript, profile.active ? "down" : "up", profile.uuid];
        vpnAction.running = true;
    }

    Process {
        id: vpnList
        command: ["python3", root.vpnScript, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    root.vpnAvailable = data.available === true;
                    root.vpnProfiles = data.profiles || [];
                    if (data.error)
                        root.vpnError = data.error;
                } catch (error) {
                    root.vpnError = "Could not read VPN profiles";
                }
            }
        }
    }

    Process {
        id: vpnAction
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    root.vpnError = data.ok === true ? "" : (data.error || "VPN action failed");
                } catch (error) {
                    root.vpnError = "VPN action failed";
                }
                root.vpnBusyUuid = "";
                root.refreshVpns();
            }
        }
    }

    // ── Aktuelle Datenrate ───────────────────────────────────────────────
    //
    // NetworkManager kennt Verbindung und Signal, liefert aber keine Live-
    // Bytezaehler. Der Kernel tut das unter /sys/class/net. Abgetastet wird
    // nur, solange das Control-Popout sichtbar ist.
    property bool trafficMonitoring: false
    property string trafficInterface: ""
    property real downloadBps: 0
    property real uploadBps: 0
    property real previousRx: -1
    property real previousTx: -1
    property double previousSampleMs: 0

    function setTrafficMonitoring(value) {
        trafficMonitoring = value;
        previousRx = -1;
        previousTx = -1;
        previousSampleMs = 0;
        if (!value) {
            downloadBps = 0;
            uploadBps = 0;
            trafficInterface = "";
        }
    }

    function formatRate(bytesPerSecond) {
        const rate = Math.max(0, Number(bytesPerSecond) || 0);
        if (rate < 1024)
            return Math.round(rate) + " B/s";
        if (rate < 1024 * 1024)
            return (rate / 1024).toFixed(rate < 10 * 1024 ? 1 : 0) + " KiB/s";
        return (rate / 1024 / 1024).toFixed(rate < 10 * 1024 * 1024 ? 1 : 0) + " MiB/s";
    }

    // Logarithmisch von 0 bis 100 MiB/s: Aktivitaet bleibt bei kleinen
    // Transfers sichtbar, grosse Downloads schlagen trotzdem klar aus.
    function rateLevel(bytesPerSecond) {
        const capped = Math.min(100 * 1024 * 1024, Math.max(0, Number(bytesPerSecond) || 0));
        return Math.round(100 * Math.log(1 + capped) / Math.log(1 + 100 * 1024 * 1024));
    }

    Process {
        id: trafficSample
        command: ["sh", "-c", "d=$(ip -o route show default | awk 'NR==1 {print $5}'); test -n \"$d\" && printf '%s %s %s\\n' \"$d\" \"$(cat /sys/class/net/$d/statistics/rx_bytes)\" \"$(cat /sys/class/net/$d/statistics/tx_bytes)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length !== 3)
                    return;
                const iface = parts[0];
                const rx = Number(parts[1]);
                const tx = Number(parts[2]);
                const now = Date.now();
                if (iface === root.trafficInterface && root.previousRx >= 0 && root.previousTx >= 0) {
                    const seconds = Math.max(0.001, (now - root.previousSampleMs) / 1000);
                    root.downloadBps = Math.max(0, (rx - root.previousRx) / seconds);
                    root.uploadBps = Math.max(0, (tx - root.previousTx) / seconds);
                } else {
                    root.downloadBps = 0;
                    root.uploadBps = 0;
                }
                root.trafficInterface = iface;
                root.previousRx = rx;
                root.previousTx = tx;
                root.previousSampleMs = now;
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.trafficMonitoring
        triggeredOnStart: true
        onTriggered: if (!trafficSample.running) trafficSample.running = true
    }

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
