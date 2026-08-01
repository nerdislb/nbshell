pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bildschirmhelligkeit.
//
// Gelesen wird aus /sys/class/backlight, gesetzt ueber logind:
//
//   busctl call org.freedesktop.login1 … SetBrightness ssu backlight <geraet> <wert>
//
// Das ist der Weg ohne Zusatzprogramm und ohne Rechte-Gebastel -- logind
// erlaubt es jeder Sitzung, die gerade aktiv ist. `brightnessctl` waere ein
// weiteres Paket, ein udev-Regelwerk waere Handarbeit auf jedem neuen Rechner.
Singleton {
    id: root

    property string device: ""
    property int raw: 0
    property int maxRaw: 0

    readonly property bool available: device !== "" && maxRaw > 0
    readonly property int percent: available ? Math.round(100 * raw / maxRaw) : 0

    // Ganz dunkel waere ein schwarzer Bildschirm, aus dem man nicht mehr
    // heraus findet.
    readonly property int minPercent: 1

    function set(percentValue) {
        if (!available)
            return 0;
        const clamped = Math.max(minPercent, Math.min(100, Math.round(percentValue)));
        const value = Math.round(maxRaw * clamped / 100);
        setProc.command = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", root.device, String(value)];
        setProc.running = true;
        raw = value;
        return clamped;
    }

    function step(delta) {
        return set(percent + delta);
    }

    Process {
        id: setProc
    }

    // Welches Backlight es gibt, sagt das Verzeichnis. Der erste Eintrag
    // gewinnt -- Notebooks haben genau eines.
    Process {
        id: findProc

        command: ["sh", "-c", "ls -1 /sys/class/backlight/ 2>/dev/null | head -1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    FileView {
        id: maxFile
        path: root.device ? "/sys/class/backlight/" + root.device + "/max_brightness" : ""
        printErrors: false
        onLoaded: root.maxRaw = parseInt(text().trim(), 10) || 0
    }

    // Der aktuelle Wert aendert sich auch von aussen (Helligkeitstasten des
    // Notebooks), deshalb nachsehen statt einmal lesen.
    FileView {
        id: curFile
        path: root.device ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        printErrors: false
        onLoaded: root.raw = parseInt(text().trim(), 10) || 0
    }

    Timer {
        interval: 3000
        running: root.device !== ""
        repeat: true
        onTriggered: curFile.reload()
    }
}
