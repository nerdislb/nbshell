import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services

// Steuerung von aussen: Inhalte.
//
// Termine, Aufgaben, Zwischenablage.
//
// Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell. Diese Handler
// standen frueher alle in shell.qml -- 945 von 1088 Zeilen, sodass die
// eigentliche Frage "woraus besteht diese Shell?" unter der Fernsteuerung
// begraben lag. Sie sprechen ausschliesslich mit Singletons, also war der
// Schnitt schmerzlos.
Scope {
    // Musik. Die Mediathek (Playlists, Suche) laeuft NICHT hierueber, sondern
    // direkt ueber scripts/ytm.py -- `nbshell music` muss auch dann noch
    // antworten, wenn die Shell gerade nicht laeuft. Hier steht nur, was einen
    // laufenden Abspieler braucht.
    IpcHandler {
        target: "music"

        function play(id: string, titel: string): string {
            if (id === "")
                return "welcher Titel?";
            Music.spiele({
                "id": id,
                "titel": titel === "" ? id : titel,
                "interpret": ""
            });
            return "spielt: " + (titel === "" ? id : titel);
        }

        function open(): string {
            Runtime.musicOpen = true;
            return "offen";
        }

        function toggle(): string {
            Runtime.musicOpen = !Runtime.musicOpen;
            return Runtime.musicOpen ? "offen" : "zu";
        }

        // Angeheftet bleibt das Fenster stehen und gibt die Tastatur ab.
        function pin(): string {
            const jetzt = !Config.value("musicPinned", false);
            Config.set("musicPinned", jetzt);
            // Wie im Fenster: Loesen laesst es stehen, statt es wegzunehmen.
            if (!jetzt)
                Runtime.musicOpen = true;
            return jetzt ? "angeheftet" : "geloest, bleibt offen";
        }

        // Auf WEN zielen die Musikknoepfe gerade? Genau das war die Frage, als
        // eine Sprachnachricht im Browser den mpv verdraengt hatte.
        function status(): string {
            return JSON.stringify({
                "spieler": String(Music.spieler?.identity ?? "keiner"),
                "eigener": MediaService.mpv !== null,
                "spielt": Music.spielt,
                "titel": Music.titel,
                "stelle": MediaService.zeit(Music.stelle),
                "warteschlange": Music.queue.length,
                "alle": MediaService.players.map(p => String(p?.identity ?? "?"))
            });
        }

        function pause(): string {
            // Vorher lesen: nach dem Umschalten steht der neue Zustand noch
            // nicht da, MPRIS meldet ihn erst zurueck. Die Antwort waere sonst
            // jedesmal die falsche.
            const lief = Music.spielt;
            Music.playPause();
            return lief ? "pausiert" : "spielt";
        }

        function stop(): string {
            Music.leeren();
            return "gestoppt";
        }

        function queue(): string {
            if (Music.queue.length === 0)
                return "die Warteschlange ist leer";
            return Music.queue.map((t, i) => (i === Music.position ? "▸ " : "  ") + t.titel + (t.interpret ? "  —  " + t.interpret : "")).join("\n");
        }
    }

    IpcHandler {
        target: "calendar"

        function toggle(): string {
            Runtime.islandOpen = true;
            Runtime.calendarOpen = !Runtime.calendarOpen;
            return Runtime.calendarOpen ? "offen" : "zu";
        }

        // Was als Naechstes ansteht -- fuers Terminal, ohne Popout.
        function next(): string {
            const list = Calendar.upcoming(8);
            if (list.length === 0)
                return Calendar.available ? "nichts eingetragen" : ("Kalender nicht verfuegbar: " + Calendar.problem);
            return list.map(e => Qt.formatDateTime(e.start, "dd.MM") + "  " + (e.allDay ? "ganztags    " : Qt.formatDateTime(e.start, "HH:mm") + "       ") + e.title).join("\n");
        }

        function sync(): string {
            Calendar.sync();
            return "vdirsyncer angestossen";
        }

        function status(): string {
            return JSON.stringify({
                "verfuegbar": Calendar.available,
                "problem": Calendar.problem,
                "kalender": Calendar.calendars,
                "termine": Calendar.events.length,
                "fenster": Calendar.windowStart
            });
        }
    }

    IpcHandler {
        target: "todo"

        function toggle(): string {
            Runtime.todoOpen = !Runtime.todoOpen;
            return Runtime.todoOpen ? "offen" : "zu";
        }

        // Der Text kommt prozentkodiert herein -- Quickshells IPC-Aufrufer
        // zerlegt Kommas, Semikola und eckige Klammern zu eigenen Argumenten.
        // "Milch, Brot und Kaese" waeren sonst drei Argumente und der Aufruf
        // scheitert. `bin/nbshell` kodiert, hier steht es wieder her.
        function add(text: string): string {
            const clean = String(text).replace(/%5B/g, "[").replace(/%5D/g, "]").replace(/%2C/g, ",").replace(/%3B/g, ";").replace(/%25/g, "%");
            const entry = Todo.add(clean);
            return entry ? "eingetragen: " + entry.text : "leer -- nichts eingetragen";
        }

        function list(): string {
            if (Todo.list.length === 0)
                return "nichts vorgemerkt";
            return Todo.list.map((e, i) => String(i + 1).padStart(3, " ") + "  " + (e.done ? "[x]" : "[ ]") + "  " + e.text).join("\n");
        }

        // Nummern beziehen sich auf genau die Liste, die `list` ausgibt.
        function done(which: string): string {
            const e = Todo.list[parseInt(which, 10) - 1];
            if (!e)
                return "keine Nummer " + which;
            Todo.toggle(e.id);
            return (e.done ? "wieder offen: " : "erledigt: ") + e.text;
        }

        function drop(which: string): string {
            const e = Todo.list[parseInt(which, 10) - 1];
            if (!e)
                return "keine Nummer " + which;
            Todo.remove(e.id);
            return "geloescht: " + e.text;
        }

        function clear(): string {
            const n = Todo.clearDone();
            return n > 0 ? "aufgeraeumt: " + n : "nichts zu erledigen";
        }

        // Konfliktkopien einsammeln und die Datei neu lesen -- fuer den Fall,
        // dass der Abgleich lief, waehrend die Shell nicht hinsah.
        function sync(): string {
            Todo.foldConflicts();
            Todo.reload();
            return "gelesen: " + Todo.file;
        }

        function status(): string {
            return JSON.stringify({
                "an": Todo.enabled,
                "offen": Todo.count,
                "erledigt": Todo.doneCount,
                "gesamt": Todo.items.length,
                "datei": Todo.file,
                "grabsteine": Todo.keepDays
            });
        }
    }

    IpcHandler {
        target: "habits"

        function toggle(): string {
            Runtime.habitsOpen = !Runtime.habitsOpen;
            return Runtime.habitsOpen ? "offen" : "zu";
        }

        function open(): string {
            Runtime.habitsOpen = true;
            return "offen";
        }

        function list(): string {
            if (Habits.habits.length === 0)
                return "keine Gewohnheiten eingerichtet";
            return Habits.habits.map((h, i) => {
                const e = Habits.todayMap[String(h.id)];
                const done = e ? e.isCompleted : false;
                const curVal = e ? e.currentValue : 0.0;
                const streak = Habits.calculateStreak(h.id);
                var line = String(i + 1).padStart(2, " ") + "  " + (done ? "[✔]" : "[ ]") + "  " + (h.icon || "✨") + "  " + h.name;
                if (h.mode === "COUNTER" || h.mode === "NUMBER" || h.mode === "DURATION") {
                    line += " (" + curVal + "/" + h.targetValue + " " + (h.unit || "") + ")";
                }
                if (streak.current > 0) {
                    line += "  🔥" + streak.current + "d";
                }
                return line;
            }).join("\n");
        }

        function done(which: string): string {
            const h = Habits.habits[parseInt(which, 10) - 1];
            if (!h)
                return "keine Nummer " + which;
            Habits.toggle(h.id);
            const e = Habits.todayMap[String(h.id)];
            return (e && e.isCompleted ? "erledigt: " : "wieder offen: ") + h.name;
        }

        function inc(which: string, delta: string): string {
            const h = Habits.habits[parseInt(which, 10) - 1];
            if (!h)
                return "keine Nummer " + which;
            const step = delta !== "" ? parseFloat(delta) : 1.0;
            Habits.increment(h.id, isNaN(step) ? 1.0 : step);
            const e = Habits.todayMap[String(h.id)];
            const curVal = e ? e.currentValue : 0.0;
            return h.name + " -> " + curVal + " / " + h.targetValue + " " + (h.unit || "");
        }

        function add(text: string): string {
            const clean = String(text).replace(/%5B/g, "[").replace(/%5D/g, "]").replace(/%2C/g, ",").replace(/%3B/g, ";").replace(/%25/g, "%");
            var name = clean;
            var routine = "general";
            var icon = "✨";
            var mode = "CHECKBOX";
            var target = 1.0;
            var unit = "times";

            if (clean.indexOf("//") !== -1) {
                const parts = clean.split("//");
                name = parts[0].trim();
                const tag = parts[1].trim().toLowerCase();
                if (["morning", "workout", "work", "evening", "general"].indexOf(tag) !== -1) {
                    routine = tag;
                }
            }

            if (routine === "morning") icon = "🌅";
            else if (routine === "workout") icon = "💪";
            else if (routine === "work") icon = "💻";
            else if (routine === "evening") icon = "🌙";

            const h = Habits.add(name, icon, routine, mode, target, unit, 2);
            return h ? "eingetragen: " + h.name + " // " + h.routine : "nichts eingetragen";
        }

        function drop(which: string): string {
            const h = Habits.habits[parseInt(which, 10) - 1];
            if (!h)
                return "keine Nummer " + which;
            Habits.remove(h.id);
            return "geloescht: " + h.name;
        }

        function sync(): string {
            Habits.foldConflicts();
            Habits.reload();
            return "gelesen: " + Habits.file;
        }

        function status(): string {
            return JSON.stringify({
                "an": Habits.enabled,
                "offen": Habits.count - Habits.doneCount,
                "erledigt": Habits.doneCount,
                "gesamt": Habits.count,
                "prozent": Habits.progressPercent,
                "datei": Habits.file
            });
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): string {
            Runtime.islandOpen = true;
            Runtime.clipOpen = !Runtime.clipOpen;
            return Runtime.clipOpen ? "offen" : "zu";
        }

        function list(): string {
            if (Clipboard.entries.length === 0)
                return "noch nichts kopiert";
            return Clipboard.entries.map((e, i) => (i + 1) + "  " + Clipboard.preview(e, 60)).join("\n");
        }

        function clear(): string {
            const n = Clipboard.entries.length;
            Clipboard.clear();
            return "geloescht: " + n;
        }
    }
}
