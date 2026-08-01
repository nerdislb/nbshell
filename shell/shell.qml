//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Bar

// nbshell -- Einstiegspunkt.
//
// Eine eigene Quickshell-Konfiguration, kein Plugin und kein Fork. DMS bleibt
// daneben installiert und laeuft weiter; die beiden stossen sich nicht, solange
// nbshell keine D-Bus-Namen beansprucht (Benachrichtigungen, Tray) -- das kommt
// erst, wenn hier alles Noetige steht.
ShellRoot {
    id: shell

    Component.onCompleted: {
        // QML-Dateien werden im Betrieb neu geladen. Beim Entwickeln reicht
        // damit Speichern statt Neustarten.
        Quickshell.watchFiles = true;
        console.info("nbshell laeuft — Theme:", Config.theme, "| Modus:", Config.mode);
    }

    Bar {}

    // ── Steuerung von aussen ──────────────────────────────────────────────
    // Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell.

    IpcHandler {
        target: "bar"

        function mode(value: string): string {
            const next = value === "toggle" ? (Config.mode === "bar" ? "island" : "bar") : value;
            if (next !== "island" && next !== "bar")
                return "unbekannt: " + value + " (island|bar|toggle)";
            Config.set("mode", next);
            return next;
        }

        function edge(value: string): string {
            const next = value === "toggle" ? (Config.edge === "top" ? "bottom" : "top") : value;
            if (next !== "top" && next !== "bottom")
                return "unbekannt: " + value + " (top|bottom|toggle)";
            Config.set("edge", next);
            return next;
        }

        function open(): string {
            Runtime.islandOpen = true;
            return "offen";
        }

        function close(): string {
            Runtime.islandOpen = false;
            return "zu";
        }

        function toggle(): string {
            Runtime.islandOpen = !Runtime.islandOpen;
            return Runtime.islandOpen ? "offen" : "zu";
        }

        function status(): string {
            return JSON.stringify({
                "mode": Config.mode,
                "edge": Config.edge,
                "theme": Config.theme,
                "open": Runtime.islandOpen,
                "screens": Quickshell.screens.length
            });
        }
    }

    IpcHandler {
        target: "theme"

        function set(name: string): string {
            Config.set("theme", name);
            return name;
        }

        function current(): string {
            return Config.theme;
        }
    }

    IpcHandler {
        target: "config"

        function get(key: string): string {
            return JSON.stringify(Config.value(key, null));
        }

        // Werte kommen als Text herein und werden, wenn moeglich, als JSON
        // gelesen -- so lassen sich auch Zahlen, Wahrheitswerte und Listen
        // setzen: `nbshell config set rightWidgets '["clock"]'`
        function set(key: string, value: string): string {
            var parsed = value;
            try {
                parsed = JSON.parse(value);
            } catch (e) {}
            Config.set(key, parsed);
            return key + " = " + JSON.stringify(parsed);
        }

        function dump(): string {
            return JSON.stringify(Config.data, null, 2);
        }
    }
}
