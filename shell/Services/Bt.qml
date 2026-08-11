pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Common

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
    //
    // Waehrend der Suche gilt das nicht: dort taucht ein Geraet erst als
    // blosse Adresse auf und bekommt seinen Namen ein, zwei Sekunden spaeter.
    // Wer es dann ausblendet, zeigt eine leere Liste, obwohl gerade etwas
    // gefunden wurde.
    readonly property var sorted: devices.filter(d => d.name || d.deviceName || root.discovering).sort((a, b) => {
        const rank = d => (d.connected ? 0 : (d.paired ? 1 : 2));
        return rank(a) - rank(b);
    })

    readonly property var connected: devices.filter(d => d.connected)

    // ── Akkus der Geraete ────────────────────────────────────────────────
    //
    // BlueZ meldet den Stand als Anteil zwischen 0 und 1 -- wie die
    // Signalstaerke beim WLAN, und wie dort wird hier EINMAL umgerechnet,
    // statt an jeder Anzeigestelle neu.
    //
    // Bisher stand das nur im Control-Popout, ganz unten in der Geraeteliste.
    // Eine Maus, die morgen leer ist, sieht man dort nie.
    function batteryOf(device) {
        return device?.batteryAvailable ? Math.round(device.battery * 100) : -1;
    }

    readonly property var withBattery: connected.filter(d => d.batteryAvailable).map(d => ({
                "label": root.label(d),
                "percent": root.batteryOf(d)
            })).sort((a, b) => a.percent - b.percent)

    readonly property var lowest: withBattery.length > 0 ? withBattery[0] : null

    // Ab wann es der Rede wert ist. Darueber bleibt die Zelle still.
    readonly property int lowAt: Config.value("deviceLowAt", 30)
    readonly property int warnAt: Config.value("deviceWarnAt", 15)

    // Gemeldet wird je Geraet einmal. Erst wenn es wieder ueber `warnAt + 10`
    // steigt (also geladen wurde), darf es sich erneut melden -- sonst haengt
    // eine Maus, die um 15 % pendelt, den ganzen Tag in den Meldungen.
    property var warnedDevices: []

    onWithBatteryChanged: {
        var merk = root.warnedDevices.slice();
        const neu = [];
        for (var i = 0; i < root.withBattery.length; i++) {
            const d = root.withBattery[i];
            const drin = merk.indexOf(d.label) >= 0;
            if (d.percent > root.warnAt + 10) {
                if (drin)
                    merk = merk.filter(n => n !== d.label);
                continue;
            }
            if (d.percent <= root.warnAt && !drin) {
                merk.push(d.label);
                neu.push(d);
            }
        }
        if (merk.length !== root.warnedDevices.length)
            root.warnedDevices = merk;
        for (var k = 0; k < neu.length; k++)
            Quickshell.execDetached(["notify-send", "--app-name=nbshell", "--icon=battery-caution", neu[k].label, "Akku bei " + neu[k].percent + " %"]);
    }

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

    // ── Suchen ────────────────────────────────────────────────────────────
    //
    // Anders als beim WLAN gibt es hier einen echten Zustand: `discovering`
    // sagt, ob BlueZ gerade sucht. Angezeigt wird also nichts geraten.
    //
    // ABER: das ist der Zustand des GERAETS, nicht unserer. BlueZ zaehlt die
    // Suchen pro Programm; laeuft nebenher eine Einstellungs-App, steht dort
    // "sucht", obwohl wir nichts angefordert haben -- und ein Stopp quittiert
    // BlueZ dann mit "No discovery started". Deshalb merken wir uns getrennt,
    // ob die Suche von uns kommt: das Symbol zeigt den echten Zustand, der
    // Knopf schaltet nur die eigene Sitzung.
    property bool requested: false

    // Wird Bluetooth abgeschaltet, ist auch unsere Suche weg -- ohne das
    // haelte sich der Knopf fuer "laeuft noch".
    onEnabledChanged: if (!root.enabled)
        root.requested = false

    // Von selbst hoert BlueZ nie auf. Eine laufende Suche haelt das Funkmodul
    // wach und stoert obendrein bestehende Verbindungen (Kopfhoerer stottern),
    // also endet sie nach einer halben Minute -- so lange, wie ein Geraet zum
    // Auffinden ueblicherweise braucht.
    Timer {
        id: stopTimer

        interval: 30000
        onTriggered: root.scan(false)
    }

    function scan(value) {
        if (!adapter || !adapter.enabled)
            return;
        if (!value && !root.requested) {
            stopTimer.stop();
            return;
        }
        adapter.discovering = value;
        root.requested = value;
        if (value)
            stopTimer.restart();
        else
            stopTimer.stop();
    }

    function toggleScan() {
        root.scan(!root.requested);
    }
}
