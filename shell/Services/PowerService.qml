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
