pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Einstellungen aus ~/.config/nbshell/config.json.
//
// Bewusst eine einzige flache JSON-Datei, die man auch von Hand bearbeiten
// kann -- sie ist die Einstellungsoberflaeche, solange es keine gibt. Die
// FileView beobachtet sie, Aenderungen greifen also sofort.
//
// Geschrieben wird atomar (`atomicWrites`), sonst liest der eigene Beobachter
// die Datei mitten im Schreiben und sieht halbes JSON.
Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/nbshell"
    readonly property string themeDir: configDir + "/themes"

    property var data: ({})

    // ── Werte mit Vorgaben ────────────────────────────────────────────────
    // Alles, was die Oberflaeche kennt, steht hier einmal -- so ist die Liste
    // der Schluessel an einer Stelle nachlesbar.

    readonly property string theme: value("theme", "tokyo-night")

    readonly property string fontFamily: value("font", "Inconsolata Nerd Font Mono")
    readonly property int fontSize: value("fontSize", 13)

    // "island" = freistehende Pille, "bar" = durchgehender Balken.
    readonly property string mode: value("mode", "island")
    readonly property string edge: value("edge", "top")
    readonly property int gap: value("gap", 6)
    readonly property int lines: value("lines", 1)
    readonly property int padX: value("padX", 1)
    readonly property int padY: value("padY", 4)
    readonly property int radius: value("radius", 0)
    readonly property int borderWidth: value("borderWidth", 1)

    // Nur der Rahmen UM die Leiste -- Zellen, Popouts und Menues behalten
    // ihren eigenen. Gilt fuer Insel wie Balken.
    readonly property bool barBorder: value("barBorder", true)
    readonly property real opacity: value("opacity", 1.0)
    readonly property string widgetStyle: value("widgetStyle", "box")

    // Symbole vor dem Text der Bausteine. Aus wird die Leiste zur reinen
    // Textzeile -- naeher am Terminal, aber schmaler zu lesen.
    readonly property bool widgetIcons: value("widgetIcons", true)

    // Bausteine ohne Neuigkeit (keine Meldung, keine Aufnahme, leere Ablage)
    // verstecken sich und kommen erst hervor, wenn die Maus die Leiste
    // beruehrt. Aus heisst: alle stehen immer da.
    readonly property bool quietWidgets: value("quietWidgets", true)

    // Aus, solange DMS daneben laeuft: beide malen sonst auf dieselbe Ebene.
    readonly property bool wallpaperEnabled: value("wallpaper", false)

    // Weichgezeichnete Kopie fuer niris Uebersicht (Mod+Tab). Sie liegt auf
    // einer eigenen Flaeche, die niri per `place-within-backdrop` nur DORT
    // zeigt -- im Alltag sieht man sie nie.
    readonly property bool wallpaperBlur: value("wallpaperBlur", true)
    readonly property int wallpaperBlurAmount: value("wallpaperBlurAmount", 64)
    readonly property int collapseDelay: value("collapseDelay", 250)

    readonly property var collapsedWidgets: value("collapsedWidgets", ["clock"])
    readonly property var leftWidgets: value("leftWidgets", ["workspaces", "sep", "window"])
    readonly property var centerWidgets: value("centerWidgets", ["clock"])
    readonly property var rightWidgets: value("rightWidgets", ["sys", "sep", "layout", "battery"])

    function value(key, fallback) {
        const v = data[key];
        return v === undefined || v === null ? fallback : v;
    }

    function set(key, val) {
        const next = JSON.parse(JSON.stringify(data));
        next[key] = val;
        data = next;
        file.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function reload() {
        file.reload();
    }

    FileView {
        id: file

        path: root.configDir + "/config.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text() || "{}");
            } catch (e) {
                console.warn("nbshell: config.json ist kaputt --", e);
            }
        }
        // Fehlt die Datei, bleiben die Vorgaben oben stehen. Kein Grund zu
        // meckern: beim ersten Start ist das der Normalfall.
        onLoadFailed: root.data = ({})
    }
}
