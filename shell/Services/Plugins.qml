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

    // Was fest eingebaut ist. Die Beschreibung steht hier und nicht im
    // Anordnen-Menue, damit beides -- eingebaut wie Plugin -- dieselbe Form
    // hat und die Liste dort nur noch anzeigen muss.
    readonly property var builtins: [
        {
            "id": "workspaces",
            "name": "Arbeitsflaechen",
            "description": "die Flaechen von niri",
            "category": "niri"
        },
        {
            "id": "window",
            "name": "Fenstertitel",
            "description": "was gerade den Fokus hat",
            "category": "niri"
        },
        {
            "id": "clock",
            "name": "Uhr",
            "description": "Datum und Zeit, Klick oeffnet den Kalender",
            "category": "Zeit"
        },
        {
            "id": "media",
            "name": "Medien",
            "description": "was gerade laeuft",
            "category": "Ton"
        },
        {
            "id": "musik",
            "name": "Wiedergabe",
            "description": "zurueck, Pause, weiter, Zufall",
            "category": "Ton"
        },
        {
            "id": "vis",
            "name": "Ausschlag",
            "description": "Balken, solange etwas spielt (cava)",
            "category": "Ton"
        },
        {
            "id": "sys",
            "name": "Systemlast",
            "description": "CPU und Speicher",
            "category": "System"
        },
        {
            "id": "battery",
            "name": "Akku",
            "description": "Ladestand, Restzeit, Energieprofil",
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
            "description": "Symbole der Programme",
            "category": "System"
        },
        {
            "id": "notifications",
            "name": "Benachrichtigungen",
            "description": "Anzahl und Archiv",
            "category": "System"
        },
        {
            "id": "clipboard",
            "name": "Zwischenablage",
            "description": "Verlauf",
            "category": "System"
        },
        {
            "id": "capture",
            "name": "Aufnahme",
            "description": "Screenshot und Bildschirmaufnahme",
            "category": "System"
        },
        {
            "id": "control",
            "name": "Control Center",
            "description": "Helligkeit, WLAN, Bluetooth",
            "category": "System"
        },
        {
            "id": "volume",
            "name": "Lautstaerke",
            "description": "Regler und Geraetewahl",
            "category": "Ton"
        },
        {
            "id": "themes",
            "name": "Themewahl",
            "description": "Farbpalette wechseln",
            "category": "Aussehen"
        },
        {
            "id": "ai",
            "name": "KI-Verbrauch",
            "description": "Fuellstand je Anbieter",
            "category": "System"
        },
        {
            "id": "updates",
            "name": "Updates",
            "description": "offene Systemupdates",
            "category": "System"
        },
        {
            "id": "todo",
            "name": "Aufgaben",
            "description": "offene Punkte, Liste per Mod+T",
            "category": "System"
        },
        {
            "id": "devices",
            "name": "Geraeteakkus",
            "description": "Maus, Kopfhoerer -- meldet sich nur, wenn es knapp wird",
            "category": "System"
        },
        {
            "id": "nearby",
            "name": "In der Naehe",
            "description": "Zwischenablage und Bilder ans Telefon (LocalSend)",
            "category": "System"
        },
        {
            "id": "caffeine",
            "name": "Wachhalten",
            "description": "haelt Dimmen, Bildschirm-aus und Sperren an",
            "category": "System"
        },
        {
            "id": "sep",
            "name": "Trenner",
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
        return e ? e.description : "unbekannter Baustein";
    }

    // Der Pfad zur QML-Datei -- leer, wenn der Baustein eingebaut ist. Genau
    // daran unterscheidet WidgetHost die beiden Faelle.
    function source(id) {
        const e = entry(id);
        return e && e.entry ? "file://" + e.entry : "";
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
