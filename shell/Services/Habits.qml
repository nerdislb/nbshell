pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Gewohnheiten-Tracker (nbHabits / init.Habits fuer nbshell).
//
// Liest und schreibt `habits.json`, das mit der Android-App nbHabits ueber
// Syncthing abgeglichen wird.
//
// Struktur von `habits.json`:
// {
//   "version": "1.0.0",
//   "syncedAt": 1786657288512,
//   "habits": [ { id, name, icon, mode, routine, targetValue, unit, shields, createdAt, isArchived, updated, deleted } ],
//   "entries": [ { habitId, date, isCompleted, currentValue, isShieldUsed, timestamp, updated } ]
// }
Singleton {
    id: root

    readonly property bool enabled: Config.value("habits", true)

    readonly property string file: {
        const home = Quickshell.env("HOME");
        const wish = String(Config.value("habitsFile", ""));
        if (wish !== "")
            return wish.replace(/^~/, home);
        // Bevorzugt den Sync-Ordner, falls er existiert:
        return home + "/Sync/nbshell/habits.json";
    }

    readonly property string script: Qt.resolvedUrl("../scripts/habits.sh").toString().replace("file://", "")

    // Alle Daten aus der Datei
    property var habitsRaw: []
    property var entriesRaw: []

    // Gefilterte Gewohnheiten (aktiv, nicht geloescht)
    readonly property var habits: habitsRaw.filter(h => !h.deleted && !h.isArchived)

    // Heutiges Datum als YYYY-MM-DD
    readonly property string todayString: {
        const d = new Date();
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return y + "-" + m + "-" + day;
    }

    // Heutige Eintraege als Map: habitId -> entry
    readonly property var todayMap: {
        const map = ({});
        const today = root.todayString;
        for (var i = 0; i < root.entriesRaw.length; i++) {
            const e = root.entriesRaw[i];
            if (e.date === today) {
                map[String(e.habitId)] = e;
            }
        }
        return map;
    }

    // Statistiken fuer heute
    readonly property int count: root.habits.length
    readonly property int doneCount: {
        var n = 0;
        for (var i = 0; i < root.habits.length; i++) {
            const h = root.habits[i];
            const e = root.todayMap[String(h.id)];
            if (e && e.isCompleted)
                n += 1;
        }
        return n;
    }

    readonly property int progressPercent: count > 0 ? Math.round((doneCount / count) * 100) : 0

    // Heatmap Matrix (140 Tage / 20 Wochen)
    readonly property var matrixCells: {
        const cells = [];
        const today = new Date();
        // 140 Tage rueckwaerts
        for (var i = 139; i >= 0; i--) {
            const d = new Date(today);
            d.setDate(today.getDate() - i);
            const y = d.getFullYear();
            const m = String(d.getMonth() + 1).padStart(2, "0");
            const day = String(d.getDate()).padStart(2, "0");
            const dateStr = y + "-" + m + "-" + day;

            // Zaehle Erledigungen an diesem Tag
            var done = 0;
            for (var j = 0; j < root.entriesRaw.length; j++) {
                const e = root.entriesRaw[j];
                if (e.date === dateStr && e.isCompleted) {
                    done += 1;
                }
            }

            const total = root.habits.length;
            const ratio = total > 0 ? (done / total) : 0;
            var level = 0;
            if (ratio > 0.75) level = 4;
            else if (ratio > 0.5) level = 3;
            else if (ratio > 0.25) level = 2;
            else if (ratio > 0) level = 1;

            cells.push({
                "date": dateStr,
                "dayOfWeek": d.getDay(), // 0 = Sun, 1 = Mon ... 6 = Sat
                "done": done,
                "total": total,
                "level": level,
                "isToday": i === 0
            });
        }
        return cells;
    }

    function now() {
        return Date.now();
    }

    function generateId() {
        return "h_" + now() + "_" + Math.floor(Math.random() * 1000);
    }

    function findHabit(id) {
        for (var i = 0; i < root.habitsRaw.length; i++) {
            if (String(root.habitsRaw[i].id) === String(id))
                return root.habitsRaw[i];
        }
        return null;
    }

    function findTodayEntry(habitId) {
        return root.todayMap[String(habitId)] ?? null;
    }

    // ── Streak-Berechnung ──────────────────────────────────────────────────
    function calculateStreak(habitId) {
        var current = 0;
        var longest = 0;
        const habitEntries = root.entriesRaw.filter(e => String(e.habitId) === String(habitId) && e.isCompleted);
        const datesSet = ({});
        for (var i = 0; i < habitEntries.length; i++)
            datesSet[habitEntries[i].date] = true;

        const d = new Date();
        const todayStr = root.todayString;

        // Wenn heute erledigt, zaehle ab heute, sonst ab gestern
        if (!datesSet[todayStr]) {
            d.setDate(d.getDate() - 1);
        }

        while (true) {
            const y = d.getFullYear();
            const m = String(d.getMonth() + 1).padStart(2, "0");
            const day = String(d.getDate()).padStart(2, "0");
            const s = y + "-" + m + "-" + day;
            if (datesSet[s]) {
                current += 1;
                d.setDate(d.getDate() - 1);
            } else {
                break;
            }
        }

        longest = Math.max(current, habitEntries.length > 0 ? 1 : 0);
        return { "current": current, "longest": longest };
    }

    // ── Aktionen ──────────────────────────────────────────────────────────

    function add(name, icon, routine, mode, targetValue, unit, shields) {
        const cleanName = String(name).trim();
        if (cleanName === "") return null;

        const t = now();
        const newHabit = {
            "id": generateId(),
            "name": cleanName,
            "icon": icon || "✨",
            "mode": mode || "CHECKBOX",
            "routine": routine || "all",
            "targetValue": Number(targetValue) || 1.0,
            "unit": unit || "times",
            "shields": Number(shields) || 2,
            "createdAt": t,
            "updated": t,
            "isArchived": false,
            "deleted": false
        };

        root.habitsRaw = root.habitsRaw.concat([newHabit]);
        save();
        return newHabit;
    }

    function remove(habitId) {
        const t = now();
        var hit = false;
        const next = root.habitsRaw.map(h => {
            if (String(h.id) === String(habitId)) {
                hit = true;
                return Object.assign({}, h, { "deleted": true, "updated": t });
            }
            return h;
        });
        if (hit) {
            root.habitsRaw = next;
            save();
        }
    }

    function setEntry(habitId, completed, currentValue) {
        const today = root.todayString;
        const t = now();
        var found = false;
        const nextEntries = root.entriesRaw.map(e => {
            if (String(e.habitId) === String(habitId) && e.date === today) {
                found = true;
                return Object.assign({}, e, {
                    "isCompleted": !!completed,
                    "currentValue": Number(currentValue) || 0.0,
                    "timestamp": t,
                    "updated": t
                });
            }
            return e;
        });

        if (!found) {
            const newEntry = {
                "habitId": String(habitId),
                "date": today,
                "isCompleted": !!completed,
                "currentValue": Number(currentValue) || 0.0,
                "isShieldUsed": false,
                "timestamp": t,
                "updated": t
            };
            root.entriesRaw = root.entriesRaw.concat([newEntry]);
        } else {
            root.entriesRaw = nextEntries;
        }

        save();
    }

    function toggle(habitId) {
        const habit = findHabit(habitId);
        if (!habit) return;
        const entry = findTodayEntry(habitId);
        const wasDone = entry ? entry.isCompleted : false;
        const newDone = !wasDone;
        const newVal = newDone ? habit.targetValue : 0.0;
        setEntry(habitId, newDone, newVal);
    }

    function increment(habitId, delta) {
        const habit = findHabit(habitId);
        if (!habit) return;
        const entry = findTodayEntry(habitId);
        const curVal = entry ? Number(entry.currentValue) : 0.0;
        const step = (delta !== undefined && delta !== null) ? Number(delta) : 1.0;
        const nextVal = Math.max(0.0, curVal + step);
        const isDone = nextVal >= habit.targetValue;
        setEntry(habitId, isDone, nextVal);
    }

    function setValue(habitId, value) {
        const habit = findHabit(habitId);
        if (!habit) return;
        const v = Math.max(0.0, Number(value));
        const isDone = v >= habit.targetValue;
        setEntry(habitId, isDone, v);
    }

    // ── Speichern und Laden ───────────────────────────────────────────────

    function normalizeHabits(raw) {
        if (!Array.isArray(raw)) return [];
        return raw.filter(h => h && typeof h === "object" && h.id).map(h => ({
            "id": String(h.id),
            "name": String(h.name || "Habit"),
            "icon": String(h.icon || "✨"),
            "mode": String(h.mode || "CHECKBOX"),
            "routine": String(h.routine || "all"),
            "targetValue": Number(h.targetValue) || 1.0,
            "unit": String(h.unit || "times"),
            "shields": Number(h.shields) || 2,
            "createdAt": Number(h.createdAt || 0) || now(),
            "updated": Number(h.updated || h.createdAt || 0) || 0,
            "isArchived": !!h.isArchived,
            "deleted": !!h.deleted
        }));
    }

    function normalizeEntries(raw) {
        if (!Array.isArray(raw)) return [];
        return raw.filter(e => e && typeof e === "object" && e.habitId && e.date).map(e => ({
            "habitId": String(e.habitId),
            "date": String(e.date),
            "isCompleted": !!e.isCompleted,
            "currentValue": Number(e.currentValue) || 0.0,
            "isShieldUsed": !!e.isShieldUsed,
            "timestamp": Number(e.timestamp || 0) || now(),
            "updated": Number(e.updated || e.timestamp || 0) || 0
        }));
    }

    function mergeHabits(mine, theirs) {
        const by = ({});
        const order = [];
        function put(h) {
            const k = String(h.id);
            const have = by[k];
            if (!have) {
                by[k] = h;
                order.push(k);
                return;
            }
            if (h.updated > have.updated)
                by[k] = h;
        }
        for (var i = 0; i < mine.length; i++) put(mine[i]);
        for (var j = 0; j < theirs.length; j++) put(theirs[j]);
        return order.map(k => by[k]);
    }

    function mergeEntries(mine, theirs) {
        const by = ({});
        const order = [];
        function put(e) {
            const k = String(e.habitId) + "_" + String(e.date);
            const have = by[k];
            if (!have) {
                by[k] = e;
                order.push(k);
                return;
            }
            if (e.updated > have.updated)
                by[k] = e;
        }
        for (var i = 0; i < mine.length; i++) put(mine[i]);
        for (var j = 0; j < theirs.length; j++) put(theirs[j]);
        return order.map(k => by[k]);
    }

    function apply(text) {
        const trimmed = String(text || "").trim();
        if (trimmed === "") return;

        var raw = null;
        try {
            raw = JSON.parse(trimmed);
        } catch (e) {
            console.warn("nbshell/habits: Datei unlesbar --", e);
            return;
        }

        if (!raw || typeof raw !== "object") return;

        const theirsHabits = normalizeHabits(raw.habits);
        const theirsEntries = normalizeEntries(raw.entries);

        const mergedH = mergeHabits(root.habitsRaw, theirsHabits);
        const mergedE = mergeEntries(root.entriesRaw, theirsEntries);

        root.habitsRaw = mergedH;
        root.entriesRaw = mergedE;
    }

    function save() {
        const data = {
            "version": "1.0.0",
            "syncedAt": now(),
            "habits": root.habitsRaw,
            "entries": root.entriesRaw
        };
        store.setText(JSON.stringify(data, null, 2) + "\n");
    }

    function foldConflicts() {
        folder.command = ["bash", root.script, "merge", root.file];
        folder.running = true;
    }

    function reload() {
        store.reload();
    }

    Component.onCompleted: if (root.enabled) {
        root.foldConflicts();
    }

    Timer {
        id: settle
        interval: 300
        onTriggered: {
            store.reload();
            root.foldConflicts();
        }
    }

    Process {
        id: folder
        stdout: StdioCollector {
            onStreamFinished: if (String(text).trim() !== "")
                console.info("nbshell/habits:", String(text).trim())
        }
    }

    FileView {
        id: store
        path: root.file
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: settle.restart()
        onLoaded: root.apply(text())
    }
}
