pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Geraete in der Naehe -- LocalSend, ohne die App.
//
// Die Idee stammt aus dem Omarchy-Plugin-Katalog (`Nearby`, jfg96). Dort
// erledigt ein vorkompilierter Rust-Helfer die Arbeit; hier reicht python3,
// das ohnehin Pflicht ist. Das Protokoll steckt in scripts/nearby.py, hier
// steht nur, wann gesucht und was geschickt wird.
//
// GESUCHT WIRD NUR, SOLANGE DAS POPOUT OFFEN IST. Eine Suche im Hintergrund
// hiesse: alle paar Sekunden ein Multicast-Paket ins WLAN, den ganzen Tag, für
// eine Liste, die niemand ansieht. Das ist dieselbe Regel wie beim
// Bluetooth-Scanner und bei der Prozessliste.
//
// Empfangen kann nbshell nicht -- dafuer braeuchte es einen dauerhaften Server,
// eine Zustimmungsabfrage und einen offenen Port in der Firewall. Zum Empfangen
// bleibt die LocalSend-App; zum schnellen Hinschicken braucht es sie nicht.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/nearby.py").toString().replace("file://", "")

    readonly property bool enabled: Config.value("nearby", true)

    property var devices: []
    property bool scanning: false

    // Was gerade laeuft und wie es ausging -- fuer die Zeile im Popout.
    property string status: ""
    property bool sending: false

    // Solange das an ist, wird gesucht. Das Popout setzt es.
    property bool wanted: false

    function scan() {
        if (!root.enabled || root.scanning)
            return;
        root.scanning = true;
        finder.command = ["python3", root.script, "discover", "3"];
        finder.running = true;
    }

    // Scan-Runde: bei jedem Ergebnis +1. Ein gefundenes Geraet merkt sich seine
    // Runde und bleibt sichtbar, bis es zwei Runden am Stueck fehlt. Ohne das
    // flackert die Liste -- LocalSends Multicast-Suche antwortet nicht in jedem
    // 3-Sekunden-Fenster, ein schon dagewesenes Handy fiele sonst je Runde kurz
    // raus und wieder rein.
    property int _round: 0

    function _merge(found) {
        root._round += 1;
        const r = root._round;

        var byIp = {};
        for (var i = 0; i < root.devices.length; i++)
            byIp[root.devices[i].ip] = root.devices[i];

        for (var j = 0; j < found.length; j++) {
            var dev = found[j];
            dev._seen = r;
            byIp[dev.ip] = dev;
        }

        var out = [];
        for (var ip in byIp) {
            var e = byIp[ip];
            if (e._seen === undefined)
                e._seen = 0;
            if (r - e._seen <= 2)
                out.push(e);
        }
        root.devices = out;
    }

    function sendFiles(device, files) {
        if (!device || files.length === 0)
            return;
        root.sending = true;
        root.status = "sendet an " + device.alias + " …";
        sender.command = ["python3", root.script, "send", device.ip, String(device.port), device.protocol].concat(files);
        sender.running = true;
    }

    function sendText(device, text) {
        if (!device || !text)
            return;
        root.sending = true;
        root.status = "sendet Text an " + device.alias + " …";
        sender.command = ["python3", root.script, "text", device.ip, String(device.port), device.protocol, text];
        sender.running = true;
    }

    // Das zuletzt aufgenommene Bild -- der zweithaeufigste Wunsch nach der
    // Zwischenablage. Welche Datei das ist, weiss nur das Dateisystem, also
    // fragt es ein Einzeiler; erst danach steht fest, was gesendet wird.
    readonly property string shotDir: {
        const home = Quickshell.env("HOME");
        return String(Config.value("captureDir", home + "/Pictures/Screenshots")).replace(/^~/, home);
    }

    property var pendingDevice: null

    function sendLastShot(device) {
        root.pendingDevice = device;
        root.status = "looking for the latest image …";
        lastShot.command = ["python3", root.script, "latest-image", root.shotDir];
        lastShot.running = true;
    }

    Process {
        id: lastShot

        stdout: StdioCollector {
            onStreamFinished: {
                const pfad = String(text).trim();
                if (pfad === "") {
                    root.status = "no image in " + root.shotDir;
                    quittung.restart();
                    return;
                }
                root.sendFiles(root.pendingDevice, [pfad]);
            }
        }
    }

    // Solange das Popout offen ist, alle paar Sekunden neu rufen: ein Telefon,
    // das gerade erst aufgeweckt wurde, ist beim ersten Ruf noch nicht da.
    Timer {
        interval: 6000
        repeat: true
        running: root.wanted && root.enabled
        triggeredOnStart: true
        onTriggered: root.scan()
    }

    // Die Meldung nach einer Uebertragung verschwindet von selbst -- sie ist
    // eine Quittung, kein Zustand.
    Timer {
        id: quittung

        interval: 6000
        onTriggered: root.status = ""
    }

    onWantedChanged: {
        if (!root.wanted) {
            root.devices = [];
            root._round = 0;
        }
    }

    Process {
        id: finder

        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                try {
                    const d = JSON.parse(text);
                    if (d.ok)
                        root._merge(d.devices ?? []);
                    else
                        root.status = String(d.grund);
                } catch (e) {
                    console.warn("nbshell/nearby: Antwort unlesbar —", e);
                }
            }
        }
    }

    Process {
        id: sender

        stdout: StdioCollector {
            onStreamFinished: {
                root.sending = false;
                try {
                    const d = JSON.parse(text);
                    root.status = d.ok ? ("sent: " + (d.gesendet ?? []).join(", ")) : ("failed: " + d.grund);
                } catch (e) {
                    root.status = "Antwort unlesbar";
                }
                quittung.restart();
            }
        }
    }
}
