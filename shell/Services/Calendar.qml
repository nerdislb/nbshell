pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Termine.
//
// Die Shell spricht mit KEINEM Anbieter. Sie liest, was vdirsyncer nach
// ~/.local/share/calendars geholt hat -- und zwar durch khal, weil erst das
// Wiederholungen ausrechnet ("jeden zweiten Dienstag", "ausser am 24.12.").
// Ob dahinter Google, iCloud oder eine ICS-Datei im Netz steht, ist von hier
// aus nicht zu erkennen und muss es auch nicht sein.
//
// Geholt wird ein Fenster um den angezeigten Monat, kein ganzes Jahr: khal
// braucht fuer 400 Tage rund fuenf Sekunden, fuer 60 eine halbe. Wer blaettert,
// loest ein neues Fenster aus.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/calendar.sh").toString().replace("file://", "")

    readonly property bool enabled: Config.value("calendar", true)

    // Termine des geladenen Fensters, nach Beginn sortiert.
    property var events: []
    property var calendars: []

    property bool loading: false
    property bool available: true
    property string problem: ""

    // Anfang und Laenge des geladenen Fensters.
    property string windowStart: ""
    readonly property int windowDays: 70

    property date lastLoad: new Date(0)

    // ── Laden ─────────────────────────────────────────────────────────────

    function isoDay(date) {
        const m = date.getMonth() + 1;
        const d = date.getDate();
        return date.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (d < 10 ? "0" : "") + d;
    }

    // Das Fenster faengt eine Woche vor dem Monatsersten an: die Gitteransicht
    // zeigt die letzten Tage des Vormonats mit, und die sollen nicht leer sein.
    function windowFor(date) {
        const start = new Date(date.getFullYear(), date.getMonth(), 1);
        start.setDate(start.getDate() - 7);
        return isoDay(start);
    }

    function ensure(date) {
        if (!root.enabled)
            return;
        const start = windowFor(date);
        if (start === root.windowStart && !root.loading)
            return;
        load(start);
    }

    function refresh() {
        if (root.windowStart === "")
            root.windowStart = windowFor(new Date());
        load(root.windowStart);
    }

    function load(start) {
        if (!root.enabled || root.loading)
            return;
        root.loading = true;
        root.windowStart = start;
        proc.command = ["bash", root.script, "events", start, String(root.windowDays)];
        proc.running = true;
    }

    // Abgleich anstossen. Danach neu lesen -- aber mit Abstand: vdirsyncer
    // laeuft im Hintergrund weiter, wenn der Aufruf schon zurueck ist.
    function sync() {
        syncProc.command = ["bash", root.script, "sync"];
        syncProc.running = true;
    }

    // ── Auswerten ─────────────────────────────────────────────────────────

    // khal wiederholt einen mehrtaegigen Termin fuer JEDEN Tag, den er
    // beruehrt -- fuer die Markierung im Gitter praktisch, fuer eine Liste
    // nicht. Doppelte fallen hier raus; wo ein Termin liegt, sagt ohnehin
    // Anfang und Ende.
    function parse(list) {
        const seen = ({});
        const out = [];
        for (var i = 0; i < list.length; i++) {
            const e = list[i];
            const key = e["start-full"] + "|" + e.title + "|" + e.calendar;
            if (seen[key])
                continue;
            seen[key] = true;
            const start = new Date(e["start-full"]);
            const end = new Date(e["end-full"]);
            if (isNaN(start.getTime()))
                continue;
            out.push({
                "start": start,
                "end": isNaN(end.getTime()) ? start : end,
                "title": String(e.title ?? "").trim(),
                "calendar": String(e.calendar ?? ""),
                "allDay": String(e["all-day"] ?? "") === "True"
            });
        }
        return out.sort((a, b) => a.start.getTime() - b.start.getTime());
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // Ein Termin gehoert zu einem Tag, wenn er ihn beruehrt -- nicht nur, wenn
    // er an ihm beginnt. Ein Urlaub ueber zwei Wochen steht sonst nur am
    // ersten Tag.
    function touchesDay(event, day) {
        const from = new Date(day.getFullYear(), day.getMonth(), day.getDate());
        const to = new Date(from.getTime() + 86400000);
        // Ganztaegige Termine enden bei khal am Endtag um 00:00 -- ohne das
        // "kleiner gleich" faellt der letzte Tag weg.
        const endsAt = event.allDay ? new Date(event.end.getTime() + 1) : event.end;
        return event.start < to && endsAt > from;
    }

    function eventsOn(day) {
        return root.events.filter(e => touchesDay(e, day));
    }

    function hasEvents(day) {
        for (var i = 0; i < root.events.length; i++)
            if (touchesDay(root.events[i], day))
                return true;
        return false;
    }

    // Was als Naechstes ansteht, ueber Tagesgrenzen hinweg.
    function upcoming(limit) {
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        return root.events.filter(e => (e.allDay ? e.end.getTime() + 86400000 : e.end.getTime()) >= today.getTime()).slice(0, limit ?? 6);
    }

    function timeLabel(event) {
        if (event.allDay)
            return "ganztags";
        return Qt.formatDateTime(event.start, "HH:mm") + "–" + Qt.formatDateTime(event.end, "HH:mm");
    }

    // Farbe je Kalender: die Reihenfolge aus `khal printcalendars` bestimmt
    // sie. Damit bleibt sie stabil, solange die Konfiguration gleich bleibt --
    // und sie kommt aus dem Theme, nicht aus khals eigenen Farbnamen.
    function colorFor(name) {
        const palette = [Theme.accent, Theme.green, Theme.yellow, Theme.magenta, Theme.cyan, Theme.red];
        const index = root.calendars.indexOf(name);
        return index < 0 ? Theme.fgDim : palette[index % palette.length];
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.available = data.ok !== false;
                    root.problem = data.ok === false ? String(data.grund ?? "") : "";
                    root.events = root.available ? root.parse(data.events ?? []) : [];
                    root.lastLoad = new Date();
                } catch (e) {
                    console.warn("nbshell/calendar: Antwort unlesbar —", e);
                    root.problem = "Antwort unlesbar";
                }
                root.loading = false;
            }
        }
    }

    Process {
        id: syncProc

        onExited: reloadTimer.restart()
    }

    Process {
        id: listProc

        command: ["bash", root.script, "calendars"]
        running: root.enabled

        stdout: StdioCollector {
            onStreamFinished: root.calendars = String(text).split("\n").map(s => s.trim()).filter(s => s !== "")
        }
    }

    Timer {
        id: reloadTimer

        interval: 8000
        onTriggered: root.load(root.windowStart)
    }

    // Im Hintergrund frisch halten. Der Abgleich selbst gehoert vdirsyncers
    // Timer -- hier wird nur neu gelesen, was schon auf der Platte liegt.
    Timer {
        interval: Config.value("calendarInterval", 900000)
        running: root.enabled
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 4000
        running: root.enabled
        repeat: false
        onTriggered: root.refresh()
    }
}
