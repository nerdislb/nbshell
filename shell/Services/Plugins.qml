pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Die Liste aller Bausteine -- der eingebauten und der nachinstallierten.
//
// Ein Plugin ist ein Verzeichnis unter ~/.config/nbshell/plugins mit einer
// manifest.json und einer QML-Datei. Die Shell laedt daraus nichts von selbst:
// erst wenn ein Baustein in einer der vier Listen der Config steht, entsteht
// er auch. Ein Plugin, das niemand eingeplant hat, kostet nichts.
//
// Warum ueberhaupt: bisher stand jeder Baustein in einer `switch`-Anweisung in
// WidgetHost.qml und noch einmal als Name im Anordnen-Menue. Wer etwas Eigenes
// bauen wollte, musste beide Stellen in der Shell aendern -- und beim naechsten
// `install.sh` war es wieder weg. Jetzt liegt es im eigenen Verzeichnis und
// ueberlebt jede Aktualisierung.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/plugins.sh").toString().replace("file://", "")

    // Wo die Plugins liegen. Dieselbe Stelle wie in scripts/plugins.sh --
    // dort wird gelesen, hier nur angezeigt.
    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/nbshell/plugins"

    // Was von aussen kommt.
    property var plugins: []
    property bool scanned: false

    // Panels, Overlays und Dienste werden explizit eingeschaltet. Bar-Widgets
    // bleiben wie bisher durch ihre Position in einer Leistenliste aktiviert.
    readonly property var enabledIds: Config.value("enabledPlugins", [])
    property var instances: ({})
    // Laufzeitdiagnose fuer die Entwickleransicht. Loader melden hier sowohl
    // den erfolgreichen Aufbau als auch Fehler; dadurch muss die Vorschau ein
    // Plugin nicht ein zweites Mal ausfuehren.
    property var loadStates: ({})

    // Was fest eingebaut ist. Die Beschreibung steht hier und nicht im
    // Anordnen-Menue, damit beides -- eingebaut wie Plugin -- dieselbe Form
    // hat und die Liste dort nur noch anzeigen muss.
    readonly property var builtins: [
        {
            "id": "workspaces",
            "name": "Workspaces",
            "description": "die Flaechen von niri",
            "category": "niri"
        },
        {
            "id": "window",
            "name": "Window title",
            "description": "what currently has focus",
            "category": "niri"
        },
        {
            "id": "clock",
            "name": "Clock",
            "description": "date and time; click opens the calendar",
            "category": "Zeit"
        },
        {
            "id": "media",
            "name": "Media",
            "description": "currently playing media",
            "category": "Audio"
        },
        {
            "id": "musik",
            "name": "Playback",
            "description": "previous, pause, next, shuffle",
            "category": "Audio"
        },
        {
            "id": "vis",
            "name": "Visualizer",
            "description": "meter while media is playing (cava)",
            "category": "Audio"
        },
        {
            "id": "bongo",
            "name": "Bongo Cat",
            "description": "typing cat using session input",
            "category": "Spass"
        },
        {
            "id": "sys",
            "name": "System load",
            "description": "CPU and memory",
            "category": "System"
        },
        {
            "id": "battery",
            "name": "Battery",
            "description": "battery level, remaining time, power profile",
            "category": "System"
        },
        {
            "id": "layout",
            "name": "Tastaturbelegung",
            "description": "zwei Buchstaben",
            "category": "niri"
        },
        {
            "id": "tray",
            "name": "System-Tray",
            "description": "application icons",
            "category": "System"
        },
        {
            "id": "notifications",
            "name": "Notifications",
            "description": "count and archive",
            "category": "System"
        },
        {
            "id": "clipboard",
            "name": "Clipboard",
            "description": "Verlauf",
            "category": "System"
        },
        {
            "id": "capture",
            "name": "Capture",
            "description": "screenshots and screen recording",
            "category": "System"
        },
        {
            "id": "control",
            "name": "Control Center",
            "description": "brightness, Wi-Fi, Bluetooth",
            "category": "System"
        },
        {
            "id": "volume",
            "name": "Volume",
            "description": "controls and device selection",
            "category": "Audio"
        },
        {
            "id": "themes",
            "name": "Theme picker",
            "description": "switch the color palette",
            "category": "Appearance"
        },
        {
            "id": "ai",
            "name": "AI usage",
            "description": "usage level for each provider",
            "category": "System"
        },
        {
            "id": "updates",
            "name": "Updates",
            "description": "available system updates",
            "category": "System"
        },
        {
            "id": "units",
            "name": "Failed services",
            "description": "failed systemd units; hidden while everything works",
            "category": "System"
        },
        {
            "id": "todo",
            "name": "Tasks",
            "description": "open tasks; list with Mod+T",
            "category": "System"
        },
        {
            "id": "habits",
            "name": "Habits",
            "description": "nbHabits / init.Habits tracker with a 20-week heatmap and streaks",
            "category": "System"
        },
        {
            "id": "devices",
            "name": "Device batteries",
            "description": "mouse and headphones; only appears when battery is low",
            "category": "System"
        },
        {
            "id": "nearby",
            "name": "In der Naehe",
            "description": "Clipboard und Bilder ans Telefon (LocalSend)",
            "category": "System"
        },
        {
            "id": "caffeine",
            "name": "Wachhalten",
            "description": "prevents dimming, screen-off, and locking",
            "category": "System"
        },
        {
            "id": "tailscale",
            "name": "Tailscale",
            "description": "Tailnet status, online devices, and addresses",
            "category": "Netz"
        },
        {
            "id": "whatsapp",
            "name": "WhatsApp",
            "description": "unread messages, chat history, and direct replies",
            "category": "Netz"
        },
        {
            "id": "sep",
            "name": "Separator",
            "description": "senkrechter Strich",
            "category": "Aussehen"
        }
    ]

    // Eingebaute zuerst, Plugins dahinter. Ein Plugin mit der Kennung eines
    // eingebauten Bausteins ersetzt diesen NICHT -- es kaeme sonst darauf an,
    // wer zuerst gelesen wurde. Es faellt raus, mit einer Meldung.
    readonly property var catalog: {
        const out = root.builtins.slice();
        const known = ({});
        for (var i = 0; i < out.length; i++)
            known[out[i].id] = true;
        for (var j = 0; j < root.plugins.length; j++) {
            const p = root.plugins[j];
            if (known[p.id]) {
                console.warn("nbshell/plugins: '" + p.id + "' heisst wie ein eingebauter Baustein — uebersprungen");
                continue;
            }
            known[p.id] = true;
            out.push(p);
        }
        return out;
    }

    readonly property var ids: catalog.map(e => e.id)

    readonly property var runtimeEntries: {
        const out = [];
        for (var i = 0; i < root.plugins.length; i++) {
            const plugin = root.plugins[i];
            if (root.enabledIds.indexOf(plugin.id) < 0)
                continue;
            const kinds = plugin.kinds ?? [];
            for (var j = 0; j < kinds.length; j++) {
                const kind = kinds[j];
                if (kind === "bar-widget")
                    continue;
                const key = kind === "panel" ? "panel" : (kind === "overlay" ? "overlay" : (kind === "service" ? "service" : ""));
                const source = key !== "" && plugin.entryPoints ? (plugin.entryPoints[key] ?? "") : "";
                if (source !== "")
                    out.push({"id": plugin.id, "kind": kind, "source": "file://" + source});
            }
        }
        return out;
    }

    function entry(id) {
        for (var i = 0; i < root.catalog.length; i++)
            if (root.catalog[i].id === id)
                return root.catalog[i];
        return null;
    }

    function label(id) {
        const e = entry(id);
        return e ? e.name : id;
    }

    function describe(id) {
        const e = entry(id);
        return e ? e.description : "unknown module";
    }

    // Der Pfad zur QML-Datei -- leer, wenn der Baustein eingebaut ist. Genau
    // daran unterscheidet WidgetHost die beiden Faelle.
    function source(id) {
        const e = entry(id);
        return e && e.entry ? "file://" + e.entry : "";
    }

    function registerInstance(id, kind, item) {
        if (!item)
            return;
        const next = Object.assign({}, root.instances);
        next[id + ":" + kind] = item;
        root.instances = next;
    }

    function unregisterInstance(id, kind, item) {
        const key = id + ":" + kind;
        if (root.instances[key] !== item)
            return;
        const next = Object.assign({}, root.instances);
        delete next[key];
        root.instances = next;
    }

    function reportLoadState(id, kind, state, detail) {
        const next = Object.assign({}, root.loadStates);
        next[id + ":" + kind] = {"state": state, "detail": detail || ""};
        root.loadStates = next;
    }

    function loadState(id, kind) {
        return root.loadStates[id + ":" + kind] ?? {"state": "inactive", "detail": ""};
    }

    function setEnabled(id, enabled) {
        const next = root.enabledIds.filter(value => value !== id);
        if (enabled)
            next.push(id);
        Config.set("enabledPlugins", next);
    }

    function runtimeInstance(id) {
        return root.instances[id + ":overlay"] ?? root.instances[id + ":panel"] ?? root.instances[id + ":service"] ?? null;
    }

    function invoke(id, verb, payload) {
        const item = runtimeInstance(id);
        if (!item)
            return "Plugin is disabled or has no runtime entry point: " + id;
        if (typeof item[verb] !== "function")
            return "Plugin " + id + " kennt " + verb + " nicht";
        try {
            const result = item[verb](payload ?? "{}");
            return result === undefined ? id + ": " + verb : String(result);
        } catch (e) {
            console.warn("nbshell/plugins:", id, verb, "failed —", e);
            return id + ": error while " + verb;
        }
    }

    function refresh() {
        proc.command = ["bash", root.script, "list"];
        proc.running = true;
    }

    Process {
        id: proc

        command: ["bash", root.script, "list"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.plugins = JSON.parse(text);
                } catch (e) {
                    console.warn("nbshell/plugins: Liste unlesbar —", e);
                    root.plugins = [];
                }
                root.scanned = true;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: if (String(text).trim() !== "")
                console.warn(String(text).trim())
        }
    }
}
