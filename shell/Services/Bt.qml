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
