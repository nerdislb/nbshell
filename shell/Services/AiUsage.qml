pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Verbrauch der KI-Zugaenge (Claude & Co.).
//
// Die Zahlen holt ein fremdes Helferskript: `get-provider-usage` aus dem
// DMS-Plugin `aiOverviewControl`. Es ist ein reines Bash-Skript -- es
// funktioniert also weiter, auch wenn DMS gar nicht mehr laeuft; die Dateien
// liegen ja noch da. Nachgebaut wird es hier nicht: es kennt die Anmeldung an
// mehrere Anbieter, und das ist fremde Arbeit, die man nicht abschreibt.
//
// Fehlt das Skript, bleibt der Baustein still -- kein Fehler, nur kein Wert.
Singleton {
    id: root

    readonly property var candidates: [Config.value("aiHelper", ""), (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/DankMaterialShell/plugins/aiOverviewControl/providers/get-provider-usage", (Quickshell.env("HOME") + "/.local/share/nbshell/get-provider-usage")]

    property string helper: ""
    property bool available: helper !== ""

    // Welche Anbieter gefragt werden -- das Skript nimmt sie als Kommaliste.
    // Es kennt ueber dreissig; welche man hat, weiss nur der Benutzer.
    readonly property string providers: Config.value("aiProviders", "claude")

    property var list: []

    readonly property var primary: list[0] ?? null

    function refresh() {
        if (!available || fetch.running)
            return;
        const provs = root.providers.replace(/\bagy\b/g, "antigravity");
        fetch.command = ["bash", root.helper, provs];
        fetch.running = true;
    }

    // "in 2 h 15 min" ist beim Verbrauch die nuetzlichere Angabe als eine
    // Uhrzeit -- man will wissen, wie lange man sich noch zurueckhalten muss.
    function untilReset(entry) {
        if (!entry?.resetsAt)
            return "";
        const target = new Date(entry.resetsAt);
        if (isNaN(target.getTime()))
            return "";
        const mins = Math.max(0, Math.round((target.getTime() - Date.now()) / 60000));
        if (mins < 60)
            return "in " + mins + " min";
        const h = Math.floor(mins / 60);
        if (h < 24)
            return "in " + h + " h " + (mins % 60) + " min";
        return "in " + Math.floor(h / 24) + " d " + (h % 24) + " h";
    }

    // Sucht beim Start einmal, welcher der Kandidaten wirklich da ist.
    Process {
        id: find

        running: true
        command: ["sh", "-c", "for f in " + root.candidates.filter(c => c !== "").map(c => JSON.stringify(c)).join(" ") + "; do [ -r \"$f\" ] && { printf '%s' \"$f\"; exit 0; }; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.helper = text.trim();
                if (root.helper !== "")
                    root.refresh();
            }
        }
    }

    Process {
        id: fetch

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const raw = JSON.parse(text);
                    function topf(t, isAgy) {
                        if (!t || t.usedPercent === undefined || t.usedPercent === null)
                            return null;
                        var label = t.name || t.resetDescription || "";
                        if (isAgy) {
                            // "Gemini Models" muss nicht da stehen, damit die Reset-Zeit
                            // sofort und ohne Zeilenumbruch lesbar ist.
                            if (label.toLowerCase().indexOf("gemini") !== -1) {
                                label = "";
                            } else if (label.toLowerCase().indexOf("claude & openai") !== -1) {
                                label = "Claude/OpenAI";
                            } else if (label.toLowerCase().indexOf("other") !== -1) {
                                label = "Other";
                            }
                        }
                        return {
                            "percent": Math.round(t.usedPercent),
                            "label": label,
                            "resetsAt": t.resetsAt ?? ""
                        };
                    }

                    root.list = raw.map(item => {
                        const isAgy = item.provider === "antigravity" || item.provider === "agy";
                        const dispId = isAgy ? "agy" : item.provider;
                        const u = item.usage ?? ({});
                        const weitere = [topf(u.secondary, isAgy), topf(u.tertiary, isAgy)].filter(t => t !== null);
                        const erst = topf(u.primary, isAgy) ?? ({
                                "percent": 0,
                                "label": "",
                                "resetsAt": ""
                            });
                        return {
                            "id": dispId,
                            "percent": erst.percent,
                            "window": erst.label,
                            "resetsAt": erst.resetsAt,
                            "more": weitere
                        };
                    });
                } catch (e) {
                    console.warn("nbshell/ai: Antwort unlesbar —", e);
                }
            }
        }
    }

    // Fuenf Minuten reichen: die Fenster sind Stunden lang, und jeder Abruf
    // kostet einen Netzzugriff.
    Timer {
        interval: Config.value("aiInterval", 300000)
        running: root.available
        repeat: true
        onTriggered: root.refresh()
    }
}
