pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common

// Battery und Energieprofil.
//
// Der Battery kommt von UPower (steckt in Quickshell), das Profil von `tuned` --
// nicht von power-profiles-daemon. Auf diesem Rechner laeuft tuned, und die
// beiden schliessen sich aus; wer das falsche fragt, bekommt gar keine
// Antwort. Quickshells eigenes `PowerProfiles` spricht nur mit ppd.
//
// tuned kennt ueber 30 Profile, von SAP HANA bis Realtime. nbshell bietet
// bewusst nur drei alltagstaugliche Modi an und versteckt die technischen
// Profilnamen hinter stabilen, compositor-unabhaengigen Bezeichnungen.
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

    // UPower reports the battery-side energy flow in watts. It is discharge
    // power on battery and charge power while plugged in; it is not a whole-
    // system wall-meter reading. Keep zero visible as a valid idle/full value.
    readonly property real rate: Math.max(0, Number(device?.changeRate ?? 0))
    readonly property string powerText: rate.toFixed(1) + " W"
    readonly property string powerCompactText: rate.toFixed(1) + "W"
    readonly property string powerLabel: full ? "Battery flow"
        : (charging ? "Charge power" : "Power draw")
    readonly property int nativeHealth: device ? Math.round(device.healthPercentage) : 0

    // Some UPower/Quickshell combinations expose the current percentage but
    // leave healthPercentage at zero. Linux still publishes the design and
    // current full charge below power_supply, so use that as a portable
    // fallback instead of hiding battery health on supported laptops. Both
    // charge_* and energy_* variants occur in the wild.
    property string sysfsBattery: ""
    property real sysfsFull: 0
    property real sysfsDesign: 0
    readonly property int sysfsHealth: sysfsFull > 0 && sysfsDesign > 0
        ? Math.round(100 * sysfsFull / sysfsDesign) : 0
    readonly property int health: nativeHealth > 0 ? nativeHealth : sysfsHealth

    // "2 h 15 min", "45 min" -- und ehrlich, wenn nichts bekannt ist.
    readonly property string timeText: {
        if (full)
            return "full";
        if (secondsLeft <= 0)
            return "calculating …";
        const mins = Math.round(secondsLeft / 60);
        if (mins < 60)
            return mins + " min";
        return Math.floor(mins / 60) + " h " + String(mins % 60).padStart(2, "0") + " min";
    }

    readonly property string stateText: full ? "full" : (charging ? "charging" : "discharging")

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
        Quickshell.execDetached(["notify-send", "--app-name=nbshell", "--icon=battery-caution", kritisch ? "--urgency=critical" : "--urgency=normal", "Battery " + root.percent + " %", kritisch ? "Battery critical — connect the charger now." : ("Remaining: " + root.timeText + ".")]);
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

    readonly property var profileOptions: [
        { "label": "Power saver", "value": "powersave" },
        { "label": "Balanced", "value": "balanced" },
        { "label": "Performance", "value": "throughput-performance" }
    ]

    property string activeProfile: ""
    readonly property string activeProfileLabel: profileLabel(activeProfile)

    function canonicalProfile(name) {
        const normalised = String(name || "").trim().toLowerCase();
        if (normalised === "powersaver" || normalised === "power-saver" || normalised === "power saver" || normalised === "powersave")
            return "powersave";
        if (normalised === "balanced")
            return "balanced";
        if (normalised === "performance" || normalised === "throughput-performance")
            return "throughput-performance";
        return "";
    }

    function profileLabel(name) {
        const canonical = canonicalProfile(name);
        if (canonical === "powersave")
            return "Power saver";
        if (canonical === "balanced")
            return "Balanced";
        if (canonical === "throughput-performance")
            return "Performance";
        return name || "Unknown";
    }

    function refreshProfile() {
        activeProc.running = true;
    }

    function setProfile(name) {
        const canonical = canonicalProfile(name);
        if (!canonical)
            return false;
        setProc.command = ["tuned-adm", "profile", canonical];
        setProc.running = true;
        return true;
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

    Process {
        command: ["sh", "-c", "for d in /sys/class/power_supply/*; do [ \"$(cat \"$d/type\" 2>/dev/null)\" = Battery ] && { printf %s \"$d\"; break; }; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.sysfsBattery = text.trim()
        }
    }

    FileView {
        path: root.sysfsBattery ? root.sysfsBattery + "/charge_full" : ""
        printErrors: false
        onLoaded: root.sysfsFull = parseFloat(text().trim()) || 0
        onLoadFailed: energyFull.reload()
    }

    FileView {
        path: root.sysfsBattery ? root.sysfsBattery + "/charge_full_design" : ""
        printErrors: false
        onLoaded: root.sysfsDesign = parseFloat(text().trim()) || 0
        onLoadFailed: energyDesign.reload()
    }

    FileView {
        id: energyFull
        path: root.sysfsBattery ? root.sysfsBattery + "/energy_full" : ""
        printErrors: false
        onLoaded: root.sysfsFull = parseFloat(text().trim()) || 0
    }

    FileView {
        id: energyDesign
        path: root.sysfsBattery ? root.sysfsBattery + "/energy_full_design" : ""
        printErrors: false
        onLoaded: root.sysfsDesign = parseFloat(text().trim()) || 0
    }
}
