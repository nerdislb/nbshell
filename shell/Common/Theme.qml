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

    // Was das Theme selbst als Akzent vorschlaegt. Von hier aus wird der
    // wirklich benutzte Akzent bestimmt -- siehe `accent` weiter unten.
    readonly property color themeAccent: c.accent ?? "#7aa2f7"

    readonly property color muted: c.muted ?? "#414868"
    readonly property color selection: c.selection ?? bgLight

    // Beim transparenten Balken ist nicht `bg`, sondern das Wallpaper die
    // wirkliche Flaeche. Bar.qml aktualisiert diese Probe aus genau dem
    // Bildstreifen hinter der Leiste (Omarchy-4-Verfahren).
    property color transparentBarSurface: bg
    readonly property color barSurface: Config.barTransparent ? transparentBarSurface : bg

    // Flaeche unter der Maus. NICHT `selection` nehmen: das ist die Farbe fuer
    // markierten Text und in manchen Themes fast weiss (dos-moos: #A5B5AB).
    // Als Hoverflaeche in der Leiste blendet sie, und jede Schrift darauf muss
    // umgerechnet werden. Aus dem Hintergrund gemischt ist sie immer dezent --
    // und der normale Text bleibt ohne Rechnerei lesbar.
    readonly property color hover: mix(bg, fg, 0.14)

    readonly property color red: c.red ?? "#f7768e"
    readonly property color green: c.green ?? "#9ece6a"
    readonly property color yellow: c.yellow ?? "#e0af68"
    // Nicht auf `accent` zurueckfallen, sondern auf den des THEMES: `accent`
    // darf inzwischen selbst blau sein, und das waere ein Kreis.
    readonly property color blue: c.blue ?? themeAccent
    readonly property color magenta: c.magenta ?? "#ad8ee6"
    readonly property color cyan: c.cyan ?? "#449dab"
    readonly property color orange: c.orange ?? yellow

    readonly property color brightRed: c.bright_red ?? red
    readonly property color brightGreen: c.bright_green ?? green
    readonly property color brightYellow: c.bright_yellow ?? yellow

    // ── Der Akzent ist eine ROLLE, keine Farbe ───────────────────────────
    //
    // In der Config steht nicht `#e0af68`, sondern `yellow`. Aufgeloest wird
    // das gegen die Palette des GERADE aktiven Themes -- wer "das Gelbe" waehlt,
    // bekommt beim Wechsel von gruvbox auf nord nordens Gelb.
    //
    // Die Idee stammt aus Shibumi-Shell (HANCORE, MIT), wo der Akzent als
    // `color01`…`color08` gespeichert wird. Der Gewinn ist nicht die Auswahl,
    // sondern was NICHT passiert: ein fester Farbwert waere nach dem naechsten
    // Themewechsel ein Fremdkoerper -- im besten Fall unpassend, im
    // schlechtesten auf dem neuen Hintergrund nicht mehr zu lesen. Eine Rolle
    // kann das nicht, weil jede Wahl aus einer Palette kommt, die der
    // Themeautor abgestimmt hat.
    //
    //   nbshell accent          zeigt die Rolle und die Auswahl
    //   nbshell accent green
    //   nbshell accent theme    zurueck zum Vorschlag des Themes
    readonly property var accentRoles: ["theme", "red", "green", "yellow", "blue", "magenta", "cyan", "orange", "foreground"]

    readonly property string accentRole: {
        const wish = String(Config.value("accent", "theme")).toLowerCase();
        return root.accentRoles.indexOf(wish) >= 0 ? wish : "theme";
    }

    function roleColor(role) {
        switch (String(role).toLowerCase()) {
        case "red":
            return root.red;
        case "green":
            return root.green;
        case "yellow":
            return root.yellow;
        case "blue":
            return root.blue;
        case "magenta":
            return root.magenta;
        case "cyan":
            return root.cyan;
        case "orange":
            return root.orange;
        case "foreground":
            return root.fgBright;
        }
        return root.themeAccent;
    }

    readonly property color accent: roleColor(root.accentRole)
    readonly property color barFg: Config.barTransparent ? on(barSurface) : fg
    readonly property color barFgDim: Config.barTransparent ? readable(mix(barFg, barSurface, 0.45), barSurface, 3.0) : fgDim
    readonly property color barAccent: Config.barTransparent ? readable(accent, barSurface, 4.5) : accent
    readonly property color barHover: mix(barSurface, barFg, 0.14)

    // Farbe der Bausteine in der Leiste: entweder der normale Vordergrund
    // oder der Akzent des Themes. Warnfarben (leerer Akku, hohe Last) bleiben
    // davon unberuehrt -- die sollen auffallen, nicht schoen sein.
    //
    // Durch `readable` gedreht: ein Akzent, der auf dem Hintergrund des Themes
    // kaum zu lesen waere, wird so weit aufgehellt oder abgedunkelt, bis er es
    // ist. Die Farbe bleibt die des Themes, nur eben lesbar.
    readonly property color text: Config.value("widgetColor", "text") === "accent" ? readable(accent, barSurface, 4.5) : barFg

    // Die gedaempfte Fassung muss WIRKLICH gedaempft sein. `readable(accent)`
    // liefert auf dunklem Grund einfach wieder den Akzent -- damit sahen in der
    // Leiste Nebensaechliches und Wichtiges gleich aus, und die Abstufung war
    // weg. Also erst zum Hintergrund ziehen, dann auf Lesbarkeit pruefen.
    readonly property color textDim: Config.value("widgetColor", "text") === "accent" ? readable(mix(accent, barSurface, 0.45), barSurface, 3.0) : barFgDim

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
    readonly property real gap: Math.round(cellW * Config.widgetGap)

    // Bar content is optically denser than panel content. Config.padX and
    // widgetGap remain the user-facing scale, while these derived values keep
    // Nerd Font glyphs from looking like isolated buttons.
    readonly property real barItemPadding: Math.max(1, Math.round(padX * 0.62))
    readonly property real barItemGap: Math.max(1, Math.round(gap * 0.55))

    readonly property real barHeight: Math.round(cellH * Config.lines + padY * 2)
    readonly property real barIconSlot: Math.round(cellH * 1.08)
    readonly property real barIconCanvas: Math.round(cellH)
    readonly property real barIconHeight: Math.round(cellH * 0.76)

    readonly property int radius: Config.radius
    readonly property int borderWidth: Config.borderWidth

    // Shared visual vocabulary for panels and controls. The bar keeps its
    // character-cell geometry; these tokens make the larger surfaces speak
    // one consistent language without forcing every component to invent
    // pixel sizes and state colors of its own.
    // Panel typography deliberately starts one step above the bar. The bar
    // continues to use `fontSize` directly, so its density and pill geometry
    // do not change when larger surfaces become easier to scan.
    readonly property int fontCaption: Math.max(9, fontSize - 1)
    readonly property int fontBody: fontSize + 1
    readonly property int fontSubtitle: fontSize + 2
    readonly property int fontTitle: fontSize + 3
    readonly property int fontHeading: fontSize + 5
    readonly property int fontDisplay: fontSize + 12

    readonly property real spaceXs: Math.max(2, Math.round(cellW * 0.5))
    readonly property real spaceSm: Math.max(3, Math.round(cellW * 0.75))
    readonly property real spaceMd: Math.max(4, Math.round(cellW))
    readonly property real spaceLg: Math.max(6, Math.round(cellW * 1.5))
    readonly property real spaceXl: Math.max(8, Math.round(cellW * 2))
    // Typography may be one step larger than the bar, but geometry already
    // derives from the configured font metrics. Scaling it a second time made
    // every popup control roughly 7% larger at the default 14 px font.
    readonly property real panelScale: 1
    readonly property real controlHeight: Math.round(cellH * 1.55)
    readonly property real rowHeight: Math.round(cellH * 1.9)
    readonly property real denseRowHeight: Math.round(cellH * 1.25)
    readonly property real panelPadding: Math.round(cellW * 2)
    readonly property real overlayMarginX: Math.round(spaceXl * 2)
    readonly property real overlayMarginY: Math.round(cellH * 3)
    readonly property real overlayWidthMedium: Math.round(cellW * 84)
    readonly property real overlayWidthLarge: Math.round(cellW * 100)
    readonly property real overlayHeightMedium: Math.round(cellH * 34)
    readonly property real overlayHeightLarge: Math.round(cellH * 43)

    readonly property color panelSurface: bg
    readonly property color panelSurfaceRaised: alpha(bgLight, 0.72)
    readonly property color panelBorder: mix(bg, fg, 0.24)
    readonly property color focusBorder: readable(accent, bg, 3.0)
    // Match Omarchy's default menu scrim: summoned surfaces stand out while
    // the workspace remains legible rather than falling into near-black.
    readonly property color scrim: alpha(bgDarker, 0.50)

    // Surface geometry follows one rem-like scale. The bar keeps the separate
    // geometry tokens above and is therefore not enlarged by menu rows.
    readonly property real uiScale: Math.max(1, fontSize / 12)
    readonly property real menuRowHeight: Math.round(50 * uiScale)

    // Selected controls must be opaque before their foreground contrast is
    // calculated. A translucent accent is composited by QML later and made
    // the old calculation depend on whatever happened to sit behind it.
    function selectedSurface(tone) {
        return mix(bg, tone ?? accent, 0.18);
    }

    function selectedForeground(tone) {
        return readable(tone ?? accent, selectedSurface(tone), 4.5);
    }

    function controlFill(hot, selected, pressed) {
        if (pressed) return mix(bg, accent, 0.26);
        if (selected) return selectedSurface(accent);
        if (hot) return hover;
        return alpha(bgLight, 0.72);
    }

    function controlBorder(hot, selected, urgent) {
        if (urgent) return alpha(red, 0.8);
        if (selected) return "transparent";
        return hot ? alpha(fg, 0.25) : alpha(fg, 0.40);
    }

    function controlBorderWidth(hot, selected, urgent) {
        if (selected && !urgent) return 0;
        return borderWidth;
    }

    FontMetrics {
        id: metrics
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    // ── Themedatei ────────────────────────────────────────────────────────

    readonly property string themePath: Config.themeDir + "/" + Config.theme + "/colors.toml"

    // ── Lesbarkeit ────────────────────────────────────────────────────────
    //
    // Ein Theme darf beliebige Farben mitbringen; `selection` ist bei manchen
    // hell, bei anderen dunkel. Wer darauf einen festen Vordergrund malt, hat
    // bei der Haelfte der Themes weisse Schrift auf hellem Grund. Deshalb wird
    // hier gerechnet statt geraten -- Kontrastverhaeltnis nach WCAG.

    // 1 (gleich) bis 21 (schwarz auf weiss).
    function contrast(a, b) {
        const la = luminance(a);
        const lb = luminance(b);
        const hi = Math.max(la, lb);
        const lo = Math.min(la, lb);
        return (hi + 0.05) / (lo + 0.05);
    }

    // Lesbare Schrift auf einer Flaeche: der bessere von Vorder- und
    // Hintergrund des Themes. Ein fester Helligkeitsschwellwert liegt bei
    // mittelhellen Farben regelmaessig daneben, das Verhaeltnis nicht.
    function on(surface) {
        return contrast(fg, surface) >= contrast(bg, surface) ? fg : bg;
    }

    // Eine gewuenschte Farbe so weit zum Hellen oder Dunklen ziehen, bis sie
    // auf `surface` das Mindestverhaeltnis erreicht. Schafft sie es nicht,
    // gewinnt die Lesbarkeit.
    function readable(color, surface, minimum) {
        const target = minimum ?? 4.5;
        if (contrast(color, surface) >= target)
            return color;
        // Die Richtung entscheidet der Kontrast, NICHT ein Helligkeits-
        // schwellwert. `#A5B5AB` hat eine Luminanz von 0.44 und gilt damit als
        // "dunkel" -- gegen Weiss kommt es aber nur auf 2.1:1, gegen Schwarz
        // auf 9.8:1. Wer nach dem Schwellwert aufhellt, macht es schlimmer.
        // Genau dieser Fehler steckte hier, obwohl der Kommentar bei `on()`
        // davor warnt.
        const towards = contrast("#ffffff", surface) >= contrast("#000000", surface) ? "#ffffff" : "#000000";
        for (var i = 1; i <= 10; i++) {
            const candidate = mix(color, towards, i / 10);
            if (contrast(candidate, surface) >= target)
                return candidate;
        }
        return on(surface);
    }

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
            console.warn("nbshell: theme not found:", root.themePath);
            root.c = ({});
        }
    }
}
