pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common

// Akku und Energieprofil.
//
// Der Akku kommt von UPower (steckt in Quickshell), das Profil von `tuned` --
// nicht von power-profiles-daemon. Auf diesem Rechner laeuft tuned, und die
// beiden schliessen sich aus; wer das falsche fragt, bekommt gar keine
// Antwort. Quickshells eigenes `PowerProfiles` spricht nur mit ppd.
//
// tuned kennt ueber 30 Profile, von SAP HANA bis Realtime. In der Leiste steht
// eine kurze Auswahl, die auf einem Notebook Sinn ergibt -- der Rest bleibt
// `tuned-adm` vorbehalten.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool available: device !== null && device.isLaptopBattery

    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false
    readonly property bool full: device ? device.state === UPowerDeviceState.FullyCharged : false

    // UPower zaehlt in Sekunden und meldet 0, solange es noch keine
    // Schaetzung gibt (kurz nach dem Anstecken etwa).
    readonly property int secondsLeft: {
        if (!device)
            return 0;
        return charging ? device.timeToFull : device.timeToEmpty;
    }

    readonly property real rate: device?.changeRate ?? 0
    readonly property int health: device ? Math.round(device.healthPercentage) : 0

    // "2 h 15 min", "45 min" -- und ehrlich, wenn nichts bekannt ist.
    readonly property string timeText: {
        if (full)
            return "voll";
        if (secondsLeft <= 0)
            return "rechnet …";
        const mins = Math.round(secondsLeft / 60);
        if (mins < 60)
            return mins + " min";
        return Math.floor(mins / 60) + " h " + String(mins % 60).padStart(2, "0") + " min";
    }

    readonly property string stateText: full ? "voll" : (charging ? "laedt" : "entlaedt")

    // ── Warnen, bevor es zu spaet ist ────────────────────────────────────
    //
    // Bis hierher wurde die Zelle bei 20 % rot -- und das war alles. Steht die
    // Insel zugeklappt auf der Uhr, sieht man davon nichts, und der Rechner
    // geht irgendwann einfach aus.
    //
    // Gewarnt wird an festen Schwellen, jede genau EINMAL je Entladung. Ohne
    // das Merken kaeme bei 19,6 % / 19,4 % / 19,2 % dreimal dieselbe Meldung;
    // zurueckgesetzt wird, sobald wieder geladen wird oder der Stand ueber der
    // Schwelle liegt.
    readonly property var warnAt: Config.value("batteryWarnAt", [20, 10, 5])

    property var warned: []

    function warn(level) {
        const kritisch = level <= 5;
        Quickshell.execDetached(["notify-send", "--app-name=nbshell", "--icon=battery-caution", kritisch ? "--urgency=critical" : "--urgency=normal", "Akku " + root.percent + " %", kritisch ? "Gleich ist Schluss — jetzt anstecken." : ("Noch " + root.timeText + ".")]);
    }

    onPercentChanged: {
        if (!root.available)
            return;

        // Am Kabel gibt es nichts zu warnen, und die Merkliste faengt von vorn
        // an: nach dem Abstecken soll wieder gewarnt werden duerfen.
        if (root.charging || root.full) {
            if (root.warned.length > 0)
                root.warned = [];
            return;
        }

        const offen = [];
        var neu = root.warned.slice();
        for (var i = 0; i < root.warnAt.length; i++) {
            const level = root.warnAt[i];
            if (root.percent > level) {
                // Wieder darueber -- die Schwelle darf erneut ausloesen.
                neu = neu.filter(l => l !== level);
                continue;
            }
            if (neu.indexOf(level) < 0) {
                neu.push(level);
                offen.push(level);
            }
        }
        if (neu.length !== root.warned.length || offen.length > 0)
            root.warned = neu;
        // Nur die niedrigste erreichte Schwelle meldet sich -- wer von 25 auf
        // 4 % springt (Standby), bekommt eine Meldung, nicht drei.
        if (offen.length > 0)
            root.warn(Math.min.apply(null, offen));
    }

    // ── tuned ─────────────────────────────────────────────────────────────

    readonly property var profiles: Config.value("powerProfiles", ["powersave", "laptop-battery-powersave", "balanced-battery", "balanced", "desktop", "throughput-performance"])

    property string activeProfile: ""

    function refreshProfile() {
        activeProc.running = true;
    }

    function setProfile(name) {
        setProc.command = ["tuned-adm", "profile", name];
        setProc.running = true;
    }

    Process {
        id: activeProc

        command: ["tuned-adm", "active"]
        running: true

        stdout: StdioCollector {
            // "Current active profile: balanced"
            onStreamFinished: {
                const m = text.match(/:\s*(\S+)/);
                root.activeProfile = m ? m[1] : "";
            }
        }
    }

    Process {
        id: setProc
        onExited: root.refreshProfile()
    }
}
