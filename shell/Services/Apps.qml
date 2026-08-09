pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Anwendungen: suchen und starten.
//
// Die Liste kommt von Quickshell (`DesktopEntries`), das die .desktop-Dateien
// aller XDG-Pfade schon eingelesen hat. Hier steht nur die Suche und das
// Starten.
Singleton {
    id: root

    readonly property var entries: (DesktopEntries.applications?.values ?? []).filter(e => !e.noDisplay)

    // Wie oft was gestartet wurde. Steht in ~/.local/state, nicht in der
    // Config: es ist Gebrauchsspur, keine Einstellung -- und niemand will das
    // in seinen Dotfiles wiederfinden.
    property var usage: ({})

    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/usage.json"

    function usageOf(entry) {
        return usage[entry?.id ?? ""] ?? 0;
    }

    function remember(entry) {
        if (!entry?.id)
            return;
        const next = JSON.parse(JSON.stringify(usage));
        next[entry.id] = (next[entry.id] ?? 0) + 1;
        usage = next;
        usageFile.setText(JSON.stringify(next));
    }

    FileView {
        id: usageFile

        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                root.usage = JSON.parse(text() || "{}");
            } catch (e) {
                root.usage = ({});
            }
        }
        onLoadFailed: root.usage = ({})
    }

    // Terminalanwendungen brauchen ein Terminal -- ohne faende ein Klick auf
    // "htop" still nicht statt. Dieselbe Falle wie bei DMS' Launcher.
    readonly property string terminal: Config.value("terminal", "") || Quickshell.env("TERMINAL") || "xterm"

    // Bewertet, wie gut `text` zu `query` passt. 0 heisst: passt nicht.
    //
    // Eine Teilfolgensuche mit Zuschlaegen: Treffer am Wortanfang zaehlen mehr,
    // aufeinanderfolgende Treffer noch mehr, und ein Name, der direkt mit der
    // Eingabe beginnt, gewinnt fast immer. Kein fzf, aber fuer ein paar hundert
    // Eintraege genau richtig.
    function score(text, query) {
        if (!query)
            return 1;
        const t = String(text).toLowerCase();
        const q = query.toLowerCase();
        if (t.startsWith(q))
            return 100 + Math.max(0, 20 - t.length);

        var pos = 0;
        var points = 0;
        var streak = 0;
        for (var i = 0; i < q.length; i++) {
            const found = t.indexOf(q[i], pos);
            if (found < 0)
                return 0;
            if (found === pos) {
                streak += 1;
                points += 3 + streak;
            } else {
                streak = 0;
                points += 1;
            }
            if (found === 0 || " -_.".indexOf(t[found - 1]) >= 0)
                points += 4;
            pos = found + 1;
        }
        return points + Math.max(0, 10 - t.length / 4);
    }

    // Wie `search`, aber mit den Punkten. Der Starter mischt Anwendungen und
    // Befehle in EINE Liste -- dafuer muss er vergleichen koennen, wie gut
    // beide Seiten passen, und nicht nur, in welcher Reihenfolge jede Seite
    // fuer sich sortiert waere.
    function rank(query) {
        if (!query) {
            const plain = entries.slice().sort((a, b) => (root.usageOf(b) - root.usageOf(a)) || a.name.localeCompare(b.name));
            return plain.map(e => ({
                        "entry": e,
                        "points": 0
                    }));
        }

        const list = [];
        for (var i = 0; i < entries.length; i++) {
            const e = entries[i];
            // Der Name zaehlt voll, Zweitname und Beschreibung nur halb: sonst
            // draengt sich ein Programm nach vorn, weil in seinem Fliesstext
            // zufaellig die Buchstaben vorkommen.
            const points = Math.max(root.score(e.name, query), root.score(e.genericName ?? "", query) * 0.5, root.score(e.comment ?? "", query) * 0.4);
            if (points > 0)
                list.push({
                    "entry": e,
                    // Haeufig Gestartetes bekommt einen Schubs, ueberholt aber
                    // keinen deutlich besseren Treffer.
                    "points": points + Math.min(8, root.usageOf(e))
                });
        }
        list.sort((a, b) => b.points - a.points || a.entry.name.localeCompare(b.entry.name));
        return list;
    }

    function search(query) {
        return rank(query).map(x => x.entry);
    }

    // Mit `check` liefert Quickshell einen leeren Pfad, wenn es das Symbol
    // nicht gibt -- sonst kaeme das magentafarbene Karomuster fuer ein
    // kaputtes Bild zurueck, und gerade Terminalprogramme bringen oft keines
    // mit. Der Starter zeichnet dann selbst einen Buchstaben.
    function iconFor(entry) {
        const name = entry?.icon ?? "";
        return name ? Quickshell.iconPath(name, true) : "";
    }

    // ── Jede Anwendung in ihren eigenen Scope ────────────────────────────
    //
    // Ohne das haengt alles Gestartete an nbshell und damit im selben Cgroup
    // wie die Shell. Laeuft ein Programm dann mit dem Speicher davon, sucht
    // systemd-oomd sich das groesste Cgroup -- und das ist die Sitzung, nicht
    // der Uebeltaeter. Ein eigener Scope je Anwendung macht sie einzeln
    // sichtbar und einzeln abraeumbar: `systemctl --user status app-nbshell-*`.
    //
    // `--scope` und nicht `--user <dienst>`: der Scope wird von systemd-run
    // selbst abgezweigt und erbt damit die Umgebung der Shell -- Anzeige,
    // Wayland-Socket, alles. Ein Dienst bekaeme stattdessen die des
    // User-Managers und faende keinen Bildschirm.
    //
    // `--collect` raeumt einen gescheiterten Scope gleich weg, sonst stuende er
    // bis zum Abmelden als "failed" in der Liste.
    readonly property bool useScopes: Config.value("appScopes", true)

    // Erst pruefen, dann verwenden: gibt es systemd-run nicht, wuerde sonst
    // nichts mehr starten -- ein hoher Preis fuer eine Aufraeumhilfe.
    property bool scopesReady: false

    function scoped(command, name) {
        if (!root.useScopes || !root.scopesReady)
            return command;
        const safe = String(name || "app").replace(/[^A-Za-z0-9_.-]/g, "_").substring(0, 40);
        const unit = "app-nbshell-" + safe + "-" + Math.floor(Math.random() * 1000000);
        return ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--unit=" + unit, "--"].concat(command);
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v systemd-run >/dev/null"]
        onExited: code => root.scopesReady = (code === 0)
    }

    function launch(entry) {
        if (!entry?.command)
            return false;

        root.remember(entry);

        const workDir = entry.workingDirectory || Quickshell.env("HOME");
        const name = entry.id || entry.name;

        if (entry.runInTerminal) {
            const quoted = entry.command.map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ");
            Quickshell.execDetached({
                "command": root.scoped([root.terminal, "-e", "sh", "-c", quoted], name),
                "workingDirectory": workDir
            });
            return true;
        }

        Quickshell.execDetached({
            "command": root.scoped(entry.command, name),
            "workingDirectory": workDir
        });
        return true;
    }

    // Was nicht als Anwendung gefunden wird, laeuft als Befehl -- wie in einem
    // Terminal, nur ohne eines zu oeffnen.
    function run(commandLine) {
        const text = String(commandLine).trim();
        if (!text)
            return false;
        Quickshell.execDetached({
            "command": root.scoped(["sh", "-c", text], "befehl"),
            "workingDirectory": Quickshell.env("HOME")
        });
        return true;
    }
}
