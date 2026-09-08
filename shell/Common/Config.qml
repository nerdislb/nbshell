pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Settings from ~/.config/nbshell/config.json. This singleton owns the live
// shell settings only; plugin manifests and Umbriel configuration have separate
// formats and lifecycle contracts.
//
// Bewusst eine einzige flache JSON-Datei, die man auch von Hand bearbeiten
// kann -- sie ist die Einstellungsoberflaeche, solange es keine gibt. Die
// FileView beobachtet sie, Aenderungen greifen also sofort.
//
// Writes use per-setting compare-and-swap patches under the migration lock.
// FileView only reads; unrelated external changes are never copied over.
Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/nbshell"
    readonly property string themeDir: configDir + "/themes"
    readonly property int supportedSchemaVersion: 1

    property var data: ({ "schemaVersion": supportedSchemaVersion })
    property bool configValid: false
    property string writeError: ""
    property var diskData: ({ "schemaVersion": supportedSchemaVersion })
    property var pendingPatch: ({})
    property var activePatch: ({})
    property int retryAttempt: 0
    readonly property bool saving: writer.running || Object.keys(activePatch).length > 0 || Object.keys(pendingPatch).length > 0
    readonly property string writeScript: Qt.resolvedUrl("../scripts/config-write.py").toString().replace("file://", "")
    signal writeFailed(string message)

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

    // Exact WhatsApp group used by the guarded shopping-list sender. Keep the
    // useful German default while allowing public installations to choose
    // their own group without changing source code.
    readonly property string shoppingListTarget: String(value("shoppingListTarget", "Einkauf")).trim() || "Einkauf"

    readonly property bool wallpaperEnabled: value("wallpaper", true)

    // Umbriel overview tint and workspace-card backdrop.
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

    function copy(value) { return JSON.parse(JSON.stringify(value)); }

    function set(key, val) {
        const values = {};
        values[key] = val;
        return setValues(values);
    }

    function setValues(values) {
        if (!configValid) {
            writeError = "Changes were not saved. Reload or repair the configuration before changing settings.";
            writeFailed(writeError);
            return false;
        }
        if (!values || typeof values !== "object" || Array.isArray(values))
            return false;
        if (Object.prototype.hasOwnProperty.call(values, "schemaVersion"))
            return false;
        const next = copy(data);
        const patch = copy(pendingPatch);
        for (const key of Object.keys(values)) {
            if (values[key] === undefined)
                return false;
            if (!Object.prototype.hasOwnProperty.call(patch, key)) {
                patch[key] = { "present": Object.prototype.hasOwnProperty.call(next, key) };
                if (patch[key].present)
                    patch[key].before = copy(next[key]);
            }
            patch[key].value = copy(values[key]);
            next[key] = copy(values[key]);
        }
        pendingPatch = patch;
        writeError = "";
        data = next;
        theme = String(next.theme || "tokyo-night");
        startSave.restart();
        return true; // Accepted into the queue; saving/writeError report persistence.
    }

    function displaySnapshot(candidate) {
        diskData = copy(candidate);
        const next = copy(candidate);
        for (const patch of [activePatch, pendingPatch]) {
            for (const key of Object.keys(patch))
                next[key] = copy(patch[key].value);
        }
        data = next;
        theme = String(next.theme || "tokyo-night");
    }

    Timer {
        id: startSave
        interval: 0
        onTriggered: {
            if (writer.running)
                return;
            if (Object.keys(root.activePatch).length === 0) {
                if (Object.keys(root.pendingPatch).length === 0)
                    return;
                root.activePatch = root.pendingPatch;
                root.pendingPatch = ({});
                root.retryAttempt = 0;
            }
            writer.stdinEnabled = true;
            writer.running = true;
        }
    }

    Process {
        id: writer
        command: ["timeout", "--kill-after=2", "15", "python3", root.writeScript]
        property string resultText: ""
        stdout: StdioCollector { onStreamFinished: writer.resultText = text }
        onStarted: {
            resultText = "";
            write(JSON.stringify(root.activePatch));
            stdinEnabled = false;
        }
        onExited: code => {
            let result = ({});
            try { result = JSON.parse(resultText); } catch (e) {}
            if (result.ok !== true && (result.ok !== false || result.uncertain === true) && root.retryAttempt === 0) {
                // The helper may have committed before losing its reply.
                // Replaying the same CAS patch once is idempotent.
                root.retryAttempt = 1;
                startSave.restart();
                return;
            }
            const completedPatch = root.activePatch;
            root.activePatch = ({});
            if (result.ok !== true) {
                const pending = root.copy(root.pendingPatch);
                for (const key of Object.keys(completedPatch))
                    delete pending[key]; // These edits depended on the rejected value.
                root.pendingPatch = pending;
                root.writeError = result.ok === false && result.uncertain !== true
                    ? "Changes were not saved. " + result.error
                    : "Could not confirm whether changes were saved. Check the current settings before retrying.";
                root.displaySnapshot(root.diskData);
                root.writeFailed(root.writeError);
                console.warn("nbshell:", root.writeError);
            }
            file.reload();
            startSave.restart();
        }
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
                const candidate = JSON.parse(text());
                if (candidate === null || Array.isArray(candidate) || typeof candidate !== "object")
                    throw new Error("the top level must be an object");
                if (!Number.isInteger(candidate.schemaVersion))
                    throw new Error("schemaVersion must be an integer");
                if (candidate.schemaVersion !== root.supportedSchemaVersion)
                    throw new Error("unsupported schemaVersion " + candidate.schemaVersion);
                root.displaySnapshot(candidate);
                root.configValid = true;
            } catch (e) {
                // Keep the last valid in-memory snapshot. Invalid state is never
                // replaced with defaults or written back silently.
                root.configValid = false;
                console.warn("nbshell: config.json was rejected --", e);
            }
        }
        // Fehlt die Datei, bleiben die Vorgaben oben stehen. Kein Grund zu
        // meckern: beim ersten Start ist das der Normalfall.
        // A later read failure also keeps the last valid in-memory snapshot.
        onLoadFailed: root.configValid = false
    }
}
