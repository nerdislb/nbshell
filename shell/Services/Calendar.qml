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

    // Kalenderwoche nach ISO 8601: die Woche mit dem ersten Donnerstag des
    // Jahres ist Woche 1. Qt hat dafuer kein Format, also von Hand. Steht hier
    // und nicht im Kalenderfenster, weil die Uhr sie ebenfalls anzeigen kann --
    // zweimal dieselbe Rechnung waere zweimal dieselbe Gelegenheit, sie
    // unterschiedlich falsch zu machen.
    function isoWeek(date) {
        const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
        const firstThursday = new Date(d.getFullYear(), 0, 4);
        firstThursday.setDate(firstThursday.getDate() + 3 - ((firstThursday.getDay() + 6) % 7));
        return 1 + Math.round((d.getTime() - firstThursday.getTime()) / (7 * 86400000));
    }

    // ── Mond ──────────────────────────────────────────────────────────────
    //
    // Reine Rechnerei, kein Abruf: aus dem julianischen Datum die Laenge von
    // Sonne und Mond, und der Abstand der beiden IST die Phase -- 0 ist
    // Neumond, 0,5 Vollmond. Die Reihe stammt aus omacal (MIT), dort in QML
    // derselben Art; sie steht hier im Dienst und nicht im Kalenderfenster, aus
    // demselben Grund wie die Kalenderwoche oben.
    //
    // Genauigkeit: gegen die mittlere Lunation nachgerechnet weicht sie um
    // hoechstens zwei Drittel eines Tages ab. Fuer ein Zeichen in der Kopfzeile
    // ist das reichlich -- schon die echten Mondlaeufe schwanken um mehr.
    function gradNorm(grad) {
        const g = grad % 360;
        return g < 0 ? g + 360 : g;
    }

    function sinGrad(grad) {
        return Math.sin(grad * Math.PI / 180);
    }

    function moonPhase(date) {
        // Mittags gemessen, nicht zur aktuellen Uhrzeit: sonst waere ein Tag je
        // nach Nachfragezeitpunkt zwei verschiedene Sicheln.
        const probe = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 12));
        const tage = probe.getTime() / 86400000 + 2440587.5 - 2451545.0;

        const sonneMittel = root.gradNorm(280.46646 + 0.98564736 * tage);
        const sonneAnomalie = root.gradNorm(357.52911 + 0.98560028 * tage);
        const sonne = root.gradNorm(sonneMittel + 1.914602 * root.sinGrad(sonneAnomalie) + 0.019993 * root.sinGrad(2 * sonneAnomalie));

        const mondMittel = root.gradNorm(218.3164477 + 13.17639648 * tage);
        const mondAnomalie = root.gradNorm(134.9633964 + 13.06499295 * tage);
        const mondElongation = root.gradNorm(297.8501921 + 12.19074912 * tage);
        const mond = root.gradNorm(mondMittel + 6.289 * root.sinGrad(mondAnomalie) + 1.274 * root.sinGrad(2 * mondElongation - mondAnomalie) + 0.658 * root.sinGrad(2 * mondElongation) + 0.214 * root.sinGrad(2 * mondAnomalie) - 0.186 * root.sinGrad(sonneAnomalie));

        return root.gradNorm(mond - sonne) / 360;
    }

    // In wie viele Stufen geteilt, sagt der Aufrufer: die Schrift hat 28
    // Sicheln, die Namen darunter nur acht.
    function moonIndex(date, stufen) {
        return Math.floor(root.moonPhase(date) * stufen + 0.5) % stufen;
    }

    readonly property var moonNames: ["new moon", "waxing crescent", "first quarter", "waxing gibbous", "full moon", "waning gibbous", "last quarter", "waning crescent"]

    function moonName(date) {
        return root.moonNames[root.moonIndex(date, 8)];
    }

    // Termine des geladenen Fensters, nach Beginn sortiert.
    property var events: []
    property var calendars: []
    property var writableCalendars: []

    property bool creating: false
    property string createError: ""
    signal eventCreated(bool ok, string error)

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

    function createEvent(calendarName, title, startIso, endIso) {
        if (root.creating)
            return;
        root.createError = "";
        root.creating = true;
        createProc.command = ["bash", root.script, "create", String(calendarName ?? ""), String(startIso ?? ""), String(endIso ?? ""), String(title ?? "")];
        createProc.running = true;
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
            return "all day";
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

    Process {
        id: writableListProc

        command: ["bash", root.script, "writable-calendars"]
        running: root.enabled

        stdout: StdioCollector {
            onStreamFinished: root.writableCalendars = String(text).split("\n").map(s => s.trim()).filter(s => s !== "")
        }
    }

    Process {
        id: createProc

        stderr: StdioCollector { id: createErr }
        onExited: code => Qt.callLater(() => {
            const ok = Number(code) === 0;
            const error = ok ? "" : (String(createErr.text || "").trim().split("\n")[0] || "The event could not be created.");
            root.creating = false;
            root.createError = error;
            root.eventCreated(ok, error);
            if (ok)
                root.sync();
        })
    }

    Timer {
        id: reloadTimer

        interval: 8000
        onTriggered: root.load(root.windowStart)
    }

    // Im Hintergrund frisch halten. Der Abgleich selbst gehoert vdirsyncers
    // Timer -- hier wird nur neu gelesen, was schon auf der Platte liegt.
    // Nicht, solange jemand hinsieht: ein neuer Satz Termine baut die Zeilen
    // im Popout neu auf, und was gerade unter der Maus lag, ist dann ein
    // anderes Element.
    Timer {
        interval: Config.value("calendarInterval", 900000)
        running: root.enabled && !Runtime.calendarOpen
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
