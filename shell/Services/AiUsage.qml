pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Verbrauch der KI-Zugaenge (Claude & Co.).
//
// Die normalisierten Provider-Helfer aus AiOverviewControl liegen
// MIT-lizenziert direkt unter scripts/ai-usage. Damit funktioniert die Anzeige
// auf einer frischen Installation ohne DMS-Verzeichnis. `aiHelper` darf den
// eingebauten Helfer weiterhin bewusst ersetzen, etwa fuer Entwicklung.
Singleton {
    id: root

    readonly property string bundledHelper: Qt.resolvedUrl("../scripts/ai-usage/providers/get-provider-usage").toString().replace("file://", "")
    readonly property string statsHelper: Qt.resolvedUrl("../scripts/ai-local-stats.py").toString().replace("file://", "")
    readonly property var candidates: [Config.value("aiHelper", ""), bundledHelper]

    property string helper: ""
    property bool available: helper !== ""

    // Welche Anbieter gefragt werden -- das Skript nimmt sie als Kommaliste.
    // Es kennt ueber dreissig; welche man hat, weiss nur der Benutzer.
    readonly property string providers: Config.value("aiProviders", "codex,claude")

    property var list: []
    property var localStats: ({})

    readonly property var primary: list[0] ?? null

    function refresh() {
        if (available && !fetch.running) {
            const provs = root.providers.replace(/\bagy\b/g, "antigravity");
            fetch.command = ["bash", root.helper, provs];
            fetch.running = true;
        }
        if (!statsFetch.running) {
            statsFetch.command = ["python3", root.statsHelper];
            statsFetch.running = true;
        }
    }

    function providerName(id) {
        if (id === "codex") return "OpenAI Codex";
        if (id === "claude") return "Claude Code";
        if (id === "agy") return "Antigravity";
        return id.charAt(0).toUpperCase() + id.slice(1);
    }

    function planName(raw) {
        const text = String(raw ?? "").replace(/^default_/, "").replace(/_/g, " ").trim();
        if (text === "" || text === "unknown") return "Subscription";
        return text.split(" ").map(part => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
    }

    function formatTokens(value) {
        const n = Math.max(0, Number(value ?? 0));
        if (n >= 1000000000) return (n / 1000000000).toFixed(n >= 10000000000 ? 0 : 1) + "B";
        if (n >= 1000000) return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1) + "M";
        if (n >= 1000) return (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "K";
        return String(Math.round(n));
    }

    // "in 2 h 15 min" ist beim normalen Verbrauch die nuetzlichere Angabe als eine
    // Uhrzeit -- man will wissen, wie lange man sich noch zurueckhalten muss.
    // Bei 100% (Limit voll ausgeschoepft) wird stattdessen der konkrete Zeitpunkt
    // angezeigt ("Reset um 14:20").
    function untilReset(entry) {
        if (!entry?.resetsAt)
            return "";
        const target = new Date(entry.resetsAt);
        if (isNaN(target.getTime()))
            return "";
        const now = new Date();

        if ((entry?.percent ?? 0) >= 100) {
            function pad2(n) { return n < 10 ? "0" + n : "" + n; }
            const timeStr = pad2(target.getHours()) + ":" + pad2(target.getMinutes());
            const isToday = target.getDate() === now.getDate() && target.getMonth() === now.getMonth() && target.getFullYear() === now.getFullYear();
            const tomorrow = new Date(now.getTime() + 86400000);
            const isTomorrow = target.getDate() === tomorrow.getDate() && target.getMonth() === tomorrow.getMonth() && target.getFullYear() === tomorrow.getFullYear();

            if (isToday)
                return "Resets at " + timeStr;
            if (isTomorrow)
                return "Resets tomorrow at " + timeStr;
            return "Resets on " + pad2(target.getDate()) + "." + pad2(target.getMonth() + 1) + ". at " + timeStr;
        }

        const mins = Math.max(0, Math.round((target.getTime() - now.getTime()) / 60000));
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
                        const stats = root.localStats[dispId] ?? ({ "recentDays": [], "models": [], "todayTokens": 0, "totalTokens": 0, "sessions": 0 });
                        return {
                            "id": dispId,
                            "name": root.providerName(dispId),
                            "plan": root.planName(u.identity?.loginMethod ?? item.credits?.remaining),
                            "percent": erst.percent,
                            "window": erst.label,
                            "resetsAt": erst.resetsAt,
                            "more": weitere,
                            "limits": [erst].concat(weitere),
                            "stats": stats,
                            "updatedAt": u.updatedAt ?? ""
                        };
                    });
                } catch (e) {
                    console.warn("nbshell/ai: unreadable response —", e);
                }
            }
        }
    }

    Process {
        id: statsFetch

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.localStats = JSON.parse(text);
                    // Rebuild the provider rows so their stats bindings receive
                    // a new immutable snapshot even when limits did not change.
                    root.list = root.list.map(entry => {
                        const copy = Object.assign({}, entry);
                        copy.stats = root.localStats[entry.id] ?? ({ "recentDays": [], "models": [], "todayTokens": 0, "totalTokens": 0, "sessions": 0 });
                        return copy;
                    });
                } catch (e) {
                    console.warn("nbshell/ai: unreadable local statistics —", e);
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
