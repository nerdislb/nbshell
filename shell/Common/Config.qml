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

    // Nicht ueber value("theme", ...) binden: QML loest den gleichnamigen
    // Schluessel dabei als Rueckbezug auf diese Property auf und meldet eine
    // Binding-Schleife. Theme wird beim Laden und Schreiben explizit gespiegelt.
    property string theme: "tokyo-night"

    readonly property string fontFamily: value("font", "JetBrainsMono Nerd Font")
    readonly property int fontSize: value("fontSize", 14)

    // Drei Formen, zwei Geometrien:
    //
    //   island  freistehende Pille, die zur Uhr zusammenschrumpft und erst
    //           beim Ueberfahren alles zeigt.
    //   pill    dieselbe Pille, die aber offen BLEIBT -- sie bleibt optisch
    //           freistehend, reserviert aber wie die Insel ihren Platz.
    //   bar     durchgehender Balken ueber die volle Breite, der den Fenstern
    //           ihren Platz wegnimmt.
    readonly property string mode: value("mode", "bar")
    readonly property string edge: value("edge", "top")
    readonly property int gap: value("gap", 6)
    readonly property int lines: value("lines", 1)
    // Innenabstand einer Zelle in Zeichen (links wie rechts).
    readonly property real padX: value("padX", 1)

    // Abstand ZWISCHEN den Bausteinen, ebenfalls in Zeichen. Zusammen mit
    // `padX` bestimmt er, wie luftig die Leiste wirkt: zwischen zwei Texten
    // liegen padX + widgetGap + padX Zeichen.
    readonly property real widgetGap: value("widgetGap", 1)
    readonly property int padY: value("padY", 4)
    readonly property int radius: value("radius", 2)
    readonly property int borderWidth: value("borderWidth", 1)
    readonly property string motionProfile: {
        const profile = String(value("motionProfile", "standard")).toLowerCase();
        return ["reduced", "standard", "expressive"].indexOf(profile) >= 0 ? profile : "standard";
    }

    // Nur der Rahmen UM die Leiste -- Zellen, Popouts und Menues behalten
    // ihren eigenen. Gilt fuer Insel wie Balken.
    readonly property bool barBorder: value("barBorder", true)
    readonly property real opacity: value("opacity", 1.0)
    // Separater Schnellschalter: die konfigurierte Deckkraft bleibt erhalten,
    // waehrend ein Doppelklick den Bar-Hintergrund komplett ausblendet.
    readonly property bool barTransparent: value("barTransparent", false)
    readonly property real barOpacity: barTransparent ? 0.0 : opacity
    readonly property string widgetStyle: value("widgetStyle", "plain")

    // Stil der Meter-Balken in den Popouts (AI-Usage/CPU/RAM/Lautstaerke ...):
    // nur "blocks" = TUI-Bloecke (Vorgabe) oder "line" = duenne Linie.
    readonly property string meterStyle: value("meterStyle", "blocks")

    // Stil des Musik-Visualizers (Cava) -- getrennt von den Metern:
    // "blocks" (Textzeile) | "line" (Balken) | "dots" | "wave".
    readonly property string visualizerStyle: value("visualizerStyle", "blocks")

    // Symbole vor dem Text der Bausteine. Aus wird die Leiste zur reinen
    // Textzeile -- naeher am Terminal, aber schmaler zu lesen.
    readonly property bool widgetIcons: value("widgetIcons", true)

    // Bausteine ohne Neuigkeit (keine Meldung, keine Aufnahme, leere Ablage)
    // verstecken sich und kommen erst hervor, wenn die Maus die Leiste
    // beruehrt. Aus heisst: alle stehen immer da.
    readonly property bool quietWidgets: value("quietWidgets", true)

    // Die Mittelgruppe der ausgeklappten Insel sitzt wirklich in der Mitte des
    // Bildschirms -- die Insel waechst dafuer um den Unterschied der beiden
    // Aussengruppen. Aus heisst: gleich grosse Luecken, die Uhr wandert.
    readonly property bool islandCenter: value("islandCenter", true)

    // Let the compact island grow into a full-width bar while it is open.
    // The setting only changes its expanded geometry; the collapsed state
    // remains a small pill.
    readonly property bool islandExpandFullWidth: value("islandExpandFullWidth", false)

    // Wie die Arbeitsflaechen aussehen: `numbers` die Nummern, `dots` ein
    // dicker Punkt fuer die aktive und kleine fuer die uebrigen, `pacman` und
    // `invader` dieselben Punkte mit einer Figur auf der aktiven. Rechtsklick
    // auf den Baustein geht reihum durch.
    readonly property string workspaceStyle: value("workspaceStyle", "numbers")

    // Pac-Man gelb, der Invader gruen -- sonst sind es keine. Aus heisst:
    // beide kommen aus der Palette des Themes.
    readonly property bool workspaceClassic: value("workspaceClassic", true)

    // Die Einblendung erscheint IN der Pille statt in einem eigenen Fenster:
    // sie wird fuer den Moment selbst zur Anzeige und geht danach zurueck.
    //
    // Nur in der Pille. Die Insel ist meistens zugeklappt -- sie muesste dafuer
    // erst aufgehen --, und der Balken ist bildschirmbreit, da waere die
    // Verwandlung keine. (Die Idee stammt aus ChillPill-Shell, nachgebaut,
    // nicht uebernommen: die steht unter GPL, nbshell unter MIT.)
    readonly property bool osdInPill: value("osdInPill", true)

    // Die Aufgabenliste. `todoFile` ist der einzige Schluessel, der wirklich
    // wichtig ist: zeigt er in einen Ordner, den ein Abgleich mitnimmt
    // (Syncthing & Co.), liegt dieselbe Liste auf dem Telefon.
    //
    //   nbshell set todoFile '~/Sync/nbshell/todo.json'
    //
    // Geloeschtes bleibt `todoKeepDays` Tage als Grabstein liegen, sonst kaeme
    // es beim naechsten Abgleich vom anderen Geraet zurueck.
    readonly property bool todo: value("todo", true)
    readonly property string todoFile: value("todoFile", "")
    readonly property int todoKeepDays: value("todoKeepDays", 30)
    readonly property bool todoShowDone: value("todoShowDone", true)

    // Aus, solange DMS daneben laeuft: beide malen sonst auf dieselbe Ebene.
    readonly property bool wallpaperEnabled: value("wallpaper", false)

    // Weichgezeichnete Kopie fuer niris Uebersicht (Mod+Tab). Sie liegt auf
    // einer eigenen Flaeche, die niri per `place-within-backdrop` nur DORT
    // zeigt -- im Alltag sieht man sie nie.
    readonly property bool wallpaperBlur: value("wallpaperBlur", true)
    readonly property int wallpaperBlurAmount: value("wallpaperBlurAmount", 64)
    // Wie lange die Insel nach dem Verlassen noch offen bleibt. 250 ms waren
    // zu knapp: wer die Maus aus der Leiste zieht, um etwas anderes zu tun,
    // und es sich unterwegs anders ueberlegt, findet sie schon zu.
    readonly property int collapseDelay: value("collapseDelay", 1400)

    readonly property var collapsedWidgets: value("collapsedWidgets", ["clock"])
    readonly property var leftWidgets: value("leftWidgets", ["workspaces", "sep", "window"])
    readonly property var centerWidgets: value("centerWidgets", ["clock"])
    readonly property var rightWidgets: value("rightWidgets", ["sys", "sep", "tray", "notifications", "volume", "control", "themes", "battery"])
    // The first separator in the right group is also its compact-mode boundary.
    // Collapsing that tail never mutates rightWidgets or the tray's own state.
    readonly property bool rightSectionExpanded: value("rightSectionExpanded", true)

    function value(key, fallback) {
        const v = data[key];
        return v === undefined || v === null ? fallback : v;
    }

    function set(key, val) {
        const next = JSON.parse(JSON.stringify(data));
        next[key] = val;
        data = next;
        if (key === "theme")
            theme = String(val || "tokyo-night");
        file.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function toggleBarTransparency() {
        set("barTransparent", !barTransparent);
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
                root.theme = String(root.data.theme || "tokyo-night");
            } catch (e) {
                console.warn("nbshell: config.json ist kaputt --", e);
            }
        }
        // Fehlt die Datei, bleiben die Vorgaben oben stehen. Kein Grund zu
        // meckern: beim ersten Start ist das der Normalfall.
        onLoadFailed: {
            root.data = ({});
            root.theme = "tokyo-night";
        }
    }
}
