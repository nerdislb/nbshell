pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// KDE Connect (Handy-Anbindung) fuer nbshell.
//
// Zustand (Geraete, Akku, Ladung, Mobilfunk) kommt ueber `kdeconnect.sh
// discover` (gdbus). Aktionen laufen direkt ueber `kdeconnect-cli`. Live wird
// es ueber `dbus-monitor`: jedes KDE-Connect-Signal stoesst ein erneutes
// discover an (kurz entprellt).
//
// Optik/Funktion nach Vorbild von OmaConnect (jitendradara12), aber in
// nbshells Bausteinen neu gebaut.
Singleton {
    id: root

    readonly property bool enabled: Config.value("kdeconnect", true)

    readonly property string script: Qt.resolvedUrl("../scripts/kdeconnect.sh").toString().replace("file://", "")

    // Alle Geraete (auch entkoppelte, damit man koppeln kann).
    property var devices: []

    // Welches Geraet im Popout im Fokus steht. Leer -> erstes erreichbares.
    property string selectedId: ""

    readonly property var selectedDevice: {
        if (root.devices.length === 0)
            return null;
        if (root.selectedId !== "") {
            const hit = root.devices.find(d => d.id === root.selectedId);
            if (hit)
                return hit;
        }
        return root.devices.find(d => d.reachable && d.paired) || root.devices[0];
    }

    // Kurze Rueckmeldung nach einer Aktion (im Popout eingeblendet).
    property string status: ""

    // Remote-Befehle des gerade gewaehlten Geraets.
    property var commands: []
    property string commandsForId: ""

    // ── Parsen ─────────────────────────────────────────────────────────────

    function _capsFromPlugins(pluginsCsv) {
        const p = String(pluginsCsv || "");
        return {
            "battery": p.indexOf("kdeconnect_battery") !== -1,
            "ring": p.indexOf("kdeconnect_findmyphone") !== -1,
            "clipboard": p.indexOf("kdeconnect_clipboard") !== -1,
            "file": p.indexOf("kdeconnect_share") !== -1,
            "text": p.indexOf("kdeconnect_share") !== -1,
            "sms": p.indexOf("kdeconnect_sms") !== -1,
            "ping": p.indexOf("kdeconnect_ping") !== -1,
            "commands": p.indexOf("kdeconnect_runcommand") !== -1,
            "connectivity": p.indexOf("kdeconnect_connectivity_report") !== -1
        };
    }

    function _apply(text) {
        const out = [];
        const lines = String(text || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            const f = lines[i].split("\t");
            if (f[0] !== "DEVICE" || f.length < 11)
                continue;
            out.push({
                "id": f[1],
                "name": f[2],
                "type": f[3],
                "paired": f[4] === "true",
                "reachable": f[5] === "true",
                "charge": parseInt(f[6]),
                "charging": f[7] === "true",
                "plugins": f[8],
                "netType": f[9],
                "netStrength": parseInt(f[10]),
                "capabilities": root._capsFromPlugins(f[8])
            });
        }
        root.devices = out;
    }

    // Menschlicher Mobilfunktyp: kdeconnect meldet oft Kuerzel wie "EDGE",
    // "LTE", "5G" -- die zeigen wir direkt, bar (n/4) fuer die Staerke.
    function cellLabel(dev) {
        if (!dev || !dev.capabilities.connectivity || dev.netType === "")
            return "";
        const s = dev.netStrength >= 0 ? " (" + dev.netStrength + "/4)" : "";
        return dev.netType + s;
    }

    // ── Discover + Live ────────────────────────────────────────────────────

    function refresh() {
        discoverProc.command = ["bash", root.script, "discover", "--refresh"];
        discoverProc.running = true;
    }

    function _discover() {
        discoverProc.command = ["bash", root.script, "discover"];
        discoverProc.running = true;
    }

    Component.onCompleted: if (root.enabled)
        root._discover()

    Process {
        id: discoverProc
        stdout: StdioCollector {
            onStreamFinished: root._apply(text)
        }
    }

    // Kurz entprellt: ein Signal kommt oft im Buendel (verbinden + Akku + ...).
    Timer {
        id: settle
        interval: 350
        onTriggered: root._discover()
    }

    Process {
        id: monitor
        command: ["dbus-monitor", "--session", "type='signal',sender='org.kde.kdeconnect'"]
        running: root.enabled
        stdout: SplitParser {
            onRead: settle.restart()
        }
    }

    // ── Aktionen ───────────────────────────────────────────────────────────

    Process { id: actionProc }

    function _run(cmd, msg) {
        actionProc.command = cmd;
        actionProc.running = true;
        if (msg !== undefined)
            root.flash(msg);
    }

    Timer {
        id: statusClear
        interval: 4000
        onTriggered: root.status = ""
    }
    function flash(msg) {
        root.status = msg;
        statusClear.restart();
    }

    function ring(id) {
        root._run(["kdeconnect-cli", "-d", String(id), "--ring"], "Klingeln gesendet");
    }
    function sendClipboard(id) {
        root._run(["kdeconnect-cli", "-d", String(id), "--send-clipboard"], "Clipboard sent");
    }
    function ping(id, text) {
        const t = String(text || "").trim();
        if (t === "")
            root._run(["kdeconnect-cli", "-d", String(id), "--ping"], "Ping gesendet");
        else
            root._run(["kdeconnect-cli", "-d", String(id), "--ping-msg", t], "Ping gesendet");
    }
    function shareText(id, text) {
        const t = String(text || "").trim();
        if (t === "")
            return;
        root._run(["kdeconnect-cli", "-d", String(id), "--share-text", t], "Text geteilt");
    }
    function openSms(id) {
        root._run(["sh", "-c", "nohup kdeconnect-sms --device " + String(id) + " >/dev/null 2>&1 &"], "SMS-App geoeffnet");
    }
    function pair(id) {
        root._run(["kdeconnect-cli", "-d", String(id), "--pair"], "Kopplung angefragt");
    }
    function unpair(id) {
        root._run(["kdeconnect-cli", "-d", String(id), "--unpair"], "Entkoppelt");
    }

    // Datei senden: erst Auswahl, dann --share des gewaehlten Pfads.
    property string _shareTargetId: ""
    function shareFile(id) {
        root._shareTargetId = String(id);
        picker.command = ["bash", root.script, "pick-file"];
        picker.running = true;
    }
    Process {
        id: picker
        stdout: StdioCollector {
            onStreamFinished: {
                const path = String(text || "").trim();
                if (path === "" || path.indexOf("ERR:") === 0 || root._shareTargetId === "")
                    return;
                root._run(["kdeconnect-cli", "-d", root._shareTargetId, "--share", path], "File sent");
            }
        }
    }

    // ── Remote-Befehle ─────────────────────────────────────────────────────

    function loadCommands(id) {
        root.commandsForId = String(id);
        commandsProc.command = ["kdeconnect-cli", "-d", String(id), "--list-commands"];
        commandsProc.running = true;
    }
    function runCommand(id, key) {
        root._run(["kdeconnect-cli", "-d", String(id), "--execute-command", String(key)], "Befehl ausgefuehrt");
    }
    Process {
        id: commandsProc
        stdout: StdioCollector {
            onStreamFinished: {
                // kdeconnect-cli --list-commands: eine Zeile je Befehl.
                // Format variiert; wir zeigen die Zeile und ziehen einen
                // Schluessel (erstes Wort ohne Doppelpunkt) heraus, falls da.
                const out = [];
                const lines = String(text || "").split("\n");
                for (var i = 0; i < lines.length; i++) {
                    const l = lines[i].trim();
                    if (l === "")
                        continue;
                    const m = l.match(/^([^:\s]+):\s*(.+)$/);
                    if (m)
                        out.push({ "key": m[1], "name": m[2] });
                    else
                        out.push({ "key": l, "name": l });
                }
                root.commands = out;
            }
        }
    }
}
