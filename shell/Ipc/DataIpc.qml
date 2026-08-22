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
    // Mediensteuerung fuer den jeweils aktiven MPRIS-Player. nbshell spielt
    // selbst nichts ab; Browser und Medien-Apps bleiben die Quelle.
    IpcHandler {
        target: "music"

        function open(): string {
            Runtime.dashboardPage = 1;
            Runtime.dashboardOpen = true;
            return "open";
        }

        function toggle(): string {
            if (Runtime.dashboardOpen && Runtime.dashboardPage === 1)
                Runtime.dashboardOpen = false;
            else {
                Runtime.dashboardPage = 1;
                Runtime.dashboardOpen = true;
            }
            return Runtime.dashboardOpen ? "open" : "closed";
        }

        function status(): string {
            return JSON.stringify({
                "spieler": String(MediaService.player?.identity ?? "keiner"),
                "spielt": MediaService.playing,
                "titel": MediaService.title,
                "interpret": MediaService.artist,
                "stelle": MediaService.zeit(MediaService.position),
                "alle": MediaService.players.map(p => String(p?.identity ?? "?"))
            });
        }

        function pause(): string {
            const lief = MediaService.playing;
            MediaService.playPause();
            return lief ? "paused" : "playing";
        }

        function next(): string { MediaService.next(); return "next"; }
        function previous(): string { MediaService.previous(); return "previous"; }
    }

    IpcHandler {
        target: "calendar"

        function open(): string {
            Runtime.dashboardPage = 3;
            Runtime.dashboardOpen = true;
            return "open";
        }

        function toggle(): string {
            if (Runtime.dashboardOpen && Runtime.dashboardPage === 3)
                Runtime.dashboardOpen = false;
            else {
                Runtime.dashboardPage = 3;
                Runtime.dashboardOpen = true;
            }
            return Runtime.dashboardOpen ? "open" : "closed";
        }

        // Was als Naechstes ansteht -- fuers Terminal, ohne Popout.
        function next(): string {
            const list = Calendar.upcoming(8);
            if (list.length === 0)
                return Calendar.available ? "nothing entered" : ("Calendar unavailable: " + Calendar.problem);
            return list.map(e => Qt.formatDateTime(e.start, "dd.MM") + "  " + (e.allDay ? "ganztags    " : Qt.formatDateTime(e.start, "HH:mm") + "       ") + e.title).join("\n");
        }

        function sync(): string {
            Calendar.sync();
            return "vdirsyncer started";
        }

        function status(): string {
            return JSON.stringify({
                "available": Calendar.available,
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
            return Runtime.todoOpen ? "open" : "closed";
        }

        // Der Text kommt prozentkodiert herein -- Quickshells IPC-Aufrufer
        // zerlegt Kommas, Semikola und eckige Klammern zu eigenen Argumenten.
        // "Milch, Brot und Kaese" waeren sonst drei Argumente und der Aufruf
        // scheitert. `bin/nbshell` kodiert, hier steht es wieder her.
        function add(text: string): string {
            const clean = String(text).replace(/%5B/g, "[").replace(/%5D/g, "]").replace(/%2C/g, ",").replace(/%3B/g, ";").replace(/%25/g, "%");
            const entry = Todo.add(clean);
            return entry ? "added: " + entry.text : "empty -- nothing entered";
        }

        function list(): string {
            if (Todo.list.length === 0)
                return "no tasks";
            return Todo.list.map((e, i) => String(i + 1).padStart(3, " ") + "  " + (e.done ? "✓" : "○") + "  " + e.text).join("\n");
        }

        // Nummern beziehen sich auf genau die Liste, die `list` ausgibt.
        function done(which: string): string {
            const e = Todo.list[parseInt(which, 10) - 1];
            if (!e)
                return "no item " + which;
            Todo.toggle(e.id);
            return (e.done ? "open again: " : "done: ") + e.text;
        }

        function drop(which: string): string {
            const e = Todo.list[parseInt(which, 10) - 1];
            if (!e)
                return "no item " + which;
            Todo.remove(e.id);
            return "deleted: " + e.text;
        }

        function clear(): string {
            const n = Todo.clearDone();
            return n > 0 ? "cleaned up: " + n : "nothing to clean up";
        }

        // Konfliktkopien einsammeln und die Datei neu lesen -- fuer den Fall,
        // dass der Abgleich lief, waehrend die Shell nicht hinsah.
        function sync(): string {
            Todo.foldConflicts();
            Todo.reload();
            return "reloaded: " + Todo.file;
        }

        function status(): string {
            return JSON.stringify({
                "enabled": Todo.enabled,
                "open": Todo.count,
                "done": Todo.doneCount,
                "total": Todo.items.length,
                "file": Todo.file,
                "retentionDays": Todo.keepDays
            });
        }
    }

    IpcHandler {
        target: "notes"

        function toggle(): string {
            Runtime.notesOpen = !Runtime.notesOpen;
            return Runtime.notesOpen ? "open" : "closed";
        }
        function newNote(): string {
            Runtime.notesRequestedId = "";
            Runtime.notesOpen = true;
            return "open";
        }
        function open(which: string): string {
            const note = Notes.list[parseInt(which, 10) - 1];
            if (!note) return "no note " + which;
            Runtime.notesRequestedId = String(note.id);
            Runtime.notesOpen = true;
            return "open: " + note.title;
        }
        function list(): string {
            if (Notes.list.length === 0) return "no notes";
            return Notes.list.map((e, i) => String(i + 1).padStart(3, " ") + "  " + e.title).join("\n");
        }
        function sync(): string {
            Notes.foldConflicts(); Notes.reload();
            return "reloaded: " + Notes.file;
        }
        function status(): string {
            return JSON.stringify({"enabled": Notes.enabled, "count": Notes.count, "file": Notes.file, "retentionDays": Notes.keepDays});
        }
    }

    IpcHandler {
        target: "habits"

        function toggle(): string {
            Runtime.habitsOpen = !Runtime.habitsOpen;
            return Runtime.habitsOpen ? "open" : "closed";
        }

        function open(): string {
            Runtime.habitsOpen = true;
            return "open";
        }

        function list(): string {
            if (Habits.habits.length === 0)
                return "no habits configured";
            return Habits.habits.map((h, i) => {
                const e = Habits.todayMap[String(h.id)];
                const done = e ? e.isCompleted : false;
                const curVal = e ? e.currentValue : 0.0;
                const streak = Habits.calculateStreak(h.id);
                var line = String(i + 1).padStart(2, " ") + "  " + (done ? "✓" : "○") + "  " + (h.icon || "✨") + "  " + h.name;
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
                return "no item " + which;
            Habits.toggle(h.id);
            const e = Habits.todayMap[String(h.id)];
            return (e && e.isCompleted ? "done: " : "open again: ") + h.name;
        }

        function inc(which: string, delta: string): string {
            const h = Habits.habits[parseInt(which, 10) - 1];
            if (!h)
                return "no item " + which;
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
            return h ? "added: " + h.name + " // " + h.routine : "nothing entered";
        }

        function drop(which: string): string {
            const h = Habits.habits[parseInt(which, 10) - 1];
            if (!h)
                return "no item " + which;
            Habits.remove(h.id);
            return "deleted: " + h.name;
        }

        function sync(): string {
            Habits.foldConflicts();
            Habits.reload();
            return "gelesen: " + Habits.file;
        }

        function status(): string {
            return JSON.stringify({
                "an": Habits.enabled,
                "open": Habits.count - Habits.doneCount,
                "done": Habits.doneCount,
                "gesamt": Habits.count,
                "prozent": Habits.progressPercent,
                "file": Habits.file
            });
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): string {
            Runtime.revealIslandTemporarily();
            Runtime.clipOpen = !Runtime.clipOpen;
            return Runtime.clipOpen ? "open" : "closed";
        }

        function list(): string {
            if (Clipboard.entries.length === 0)
                return "nothing copied yet";
            return Clipboard.entries.map((e, i) => (i + 1) + "  " + Clipboard.preview(e, 60)).join("\n");
        }

        function clear(): string {
            const n = Clipboard.entries.length;
            Clipboard.clear();
            return "deleted: " + n;
        }
    }
}
