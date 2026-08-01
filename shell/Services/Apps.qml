pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// Anwendungen: suchen und starten.
//
// Die Liste kommt von Quickshell (`DesktopEntries`), das die .desktop-Dateien
// aller XDG-Pfade schon eingelesen hat. Hier steht nur die Suche und das
// Starten.
Singleton {
    id: root

    readonly property var entries: (DesktopEntries.applications?.values ?? []).filter(e => !e.noDisplay)

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

    function search(query) {
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
                    "points": points
                });
        }
        list.sort((a, b) => b.points - a.points || a.entry.name.localeCompare(b.entry.name));
        return list.map(x => x.entry);
    }

    function launch(entry) {
        if (!entry?.command)
            return false;

        const workDir = entry.workingDirectory || Quickshell.env("HOME");

        if (entry.runInTerminal) {
            const quoted = entry.command.map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ");
            Quickshell.execDetached({
                "command": [root.terminal, "-e", "sh", "-c", quoted],
                "workingDirectory": workDir
            });
            return true;
        }

        Quickshell.execDetached({
            "command": entry.command,
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
            "command": ["sh", "-c", text],
            "workingDirectory": Quickshell.env("HOME")
        });
        return true;
    }
}
