pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Farben und Masse.
//
// Kein Material Design: es gibt keine Rollen wie "surfaceContainerHighest",
// keine Erhebungen, keine Schatten. Stattdessen dieselbe Palette, die auch das
// Terminal benutzt -- Omarchys `colors.toml`, 1:1 aus omarchy2dms uebernommen.
// Damit sieht die Shell aus wie die Programme darunter, und ein Themewechsel
// faerbt beides gleichzeitig.
//
// Die Masse sind Zellen, keine px. `cellW`/`cellH` kommen aus der Schrift;
// Hoehen und Abstaende sind Vielfache davon. Das ist der eigentliche Trick am
// TUI-Aussehen: alles liegt auf einem Zeichenraster.
Singleton {
    id: root

    property var c: ({})

    // ── Palette ───────────────────────────────────────────────────────────

    readonly property bool isLight: (c.mode ?? "dark") === "light"

    readonly property color bg: c.background ?? "#1a1b26"
    readonly property color bgDark: c.dark_background ?? bg
    readonly property color bgDarker: c.darker_background ?? bgDark
    readonly property color bgLight: c.lighter_background ?? bg

    readonly property color fg: c.foreground ?? "#a9b1d6"
    readonly property color fgDim: c.dark_foreground ?? muted
    readonly property color fgBright: c.bright_foreground ?? fg

    readonly property color accent: c.accent ?? "#7aa2f7"
    readonly property color muted: c.muted ?? "#414868"
    readonly property color selection: c.selection ?? bgLight

    readonly property color red: c.red ?? "#f7768e"
    readonly property color green: c.green ?? "#9ece6a"
    readonly property color yellow: c.yellow ?? "#e0af68"
    readonly property color blue: c.blue ?? accent
    readonly property color magenta: c.magenta ?? "#ad8ee6"
    readonly property color cyan: c.cyan ?? "#449dab"
    readonly property color orange: c.orange ?? yellow

    readonly property color brightRed: c.bright_red ?? red
    readonly property color brightGreen: c.bright_green ?? green
    readonly property color brightYellow: c.bright_yellow ?? yellow

    function alpha(color, a) {
        return Qt.rgba(color.r, color.g, color.b, a);
    }

    // ── Zeichenraster ─────────────────────────────────────────────────────

    readonly property string fontFamily: Config.fontFamily
    readonly property int fontSize: Config.fontSize

    // Eine Monospace-Zelle. `advanceWidth` statt `averageCharacterWidth`:
    // gemessen wird die tatsaechliche Vorschubbreite eines Zeichens, und bei
    // einer Monospace-Schrift ist die fuer alle gleich.
    readonly property real cellW: metrics.advanceWidth("0")
    readonly property real cellH: Math.ceil(metrics.height)

    readonly property real padX: Math.round(cellW * Config.padX)
    readonly property real padY: Config.padY
    readonly property real gap: cellW

    readonly property real barHeight: Math.round(cellH * Config.lines + padY * 2)

    readonly property int radius: Config.radius
    readonly property int borderWidth: Config.borderWidth

    FontMetrics {
        id: metrics
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    // ── Themedatei ────────────────────────────────────────────────────────

    readonly property string themePath: Config.themeDir + "/" + Config.theme + "/colors.toml"

    // Ein winziger TOML-Leser. Omarchys Farbdateien sind flach und haben nur
    // `schluessel = "wert"`-Zeilen -- ein vollstaendiger Parser waere hier
    // Ballast.
    function parseToml(text) {
        const out = ({});
        const lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            // Zwei Faelle: in Anfuehrungszeichen (dann gilt alles darin) oder
            // blank bis zum Kommentar. Wichtig ist, dass die Raute NUR den
            // Kommentar einleitet -- jede Farbe faengt selbst mit einer an.
            const m = lines[i].match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:"([^"]*)"|([^\s#]+))/);
            if (m)
                out[m[1]] = m[2] !== undefined ? m[2] : m[3];
        }
        return out;
    }

    FileView {
        id: themeFile

        path: root.themePath
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            root.c = root.parseToml(text());
            // Ohne diese Warnung faellt ein kaputter Parser nicht auf: die
            // Vorgabewerte oben sind ein vollstaendiges Theme und sehen
            // richtig aus.
            if (Object.keys(root.c).length < 5)
                console.warn("nbshell: Theme", Config.theme, "nur teilweise gelesen —", Object.keys(root.c).length, "Werte");
        }
        onLoadFailed: {
            console.warn("nbshell: Theme nicht gefunden:", root.themePath);
            root.c = ({});
        }
    }
}
