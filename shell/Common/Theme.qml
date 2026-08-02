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

    // Zwei Farben mischen, t=0 gibt a, t=1 gibt b.
    function mix(a, b, t) {
        const ca = Qt.color(a);
        const cb = Qt.color(b);
        return Qt.rgba(ca.r * (1 - t) + cb.r * t, ca.g * (1 - t) + cb.g * t, ca.b * (1 - t) + cb.b * t, 1);
    }

    // Relative Luminanz nach WCAG -- entscheidet ueber hell/dunkel.
    function luminance(color) {
        const c = Qt.color(color);
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    // Omarchy-Themes gibt es in ZWEI Dialekten:
    //
    //   alt   benannte Schluessel -- red, green, muted, dark_foreground …
    //   neu   ANSI-Nummern -- color0 … color15, selection_background …
    //
    // Die 21 mitgelieferten sind der alte, frisch geholte meist der neue. Wer
    // nur einen liest, bekommt beim anderen ein halb gefuelltes Theme -- und
    // weil die Vorgabewerte ein vollstaendiges Theme sind, sieht das nicht
    // kaputt aus, sondern nur falsch. Genau das ist mit dos-moos passiert.
    function normalize(c) {
        const out = c;

        if (out.color0 !== undefined) {
            const ansi = {
                "red": "color1",
                "green": "color2",
                "yellow": "color3",
                "blue": "color4",
                "magenta": "color5",
                "cyan": "color6"
            };
            for (const name in ansi) {
                if (out[name] === undefined && out[ansi[name]] !== undefined)
                    out[name] = out[ansi[name]];
                const brightKey = "bright_" + name;
                const brightAnsi = "color" + (parseInt(ansi[name].substring(5), 10) + 8);
                if (out[brightKey] === undefined && out[brightAnsi] !== undefined)
                    out[brightKey] = out[brightAnsi];
            }
            if (out.muted === undefined)
                out.muted = out.color8;
            if (out.dark_foreground === undefined)
                out.dark_foreground = out.color8;
            if (out.light_foreground === undefined)
                out.light_foreground = out.color7;
            if (out.bright_foreground === undefined)
                out.bright_foreground = out.color15;
        }

        if (out.selection === undefined && out.selection_background !== undefined)
            out.selection = out.selection_background;

        // Abgeleitetes: dieselben Mischungen, die auch omarchy2dms nimmt.
        const bg = out.background;
        const fg = out.foreground;
        if (bg && fg) {
            if (out.lighter_background === undefined)
                out.lighter_background = String(mix(bg, fg, 0.12));
            if (out.selection === undefined)
                out.selection = String(mix(bg, fg, 0.18));
            if (out.muted === undefined)
                out.muted = String(mix(bg, fg, 0.35));
            if (out.dark_foreground === undefined)
                out.dark_foreground = String(mix(fg, bg, 0.45));
        }
        if (bg) {
            if (out.dark_background === undefined)
                out.dark_background = String(mix(bg, "#000000", 0.25));
            if (out.darker_background === undefined)
                out.darker_background = String(mix(bg, "#000000", 0.4));
            if (out.mode === undefined)
                out.mode = luminance(bg) > 0.5 ? "light" : "dark";
        }

        return out;
    }

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
            root.c = root.normalize(root.parseToml(text()));
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
