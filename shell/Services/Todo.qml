pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Die Aufgabenliste.
//
// Eine einzige JSON-Datei, die auch ein anderes Geraet schreiben darf --
// deshalb ist hier fast alles Zusammenfuehren und fast nichts Verwaltung.
//
// **Kein "wer zuletzt schreibt, gewinnt".** Die Datei wird nicht ersetzt,
// sondern EINTRAGSWEISE zusammengefuehrt: jeder Eintrag traegt `updated`, und
// bei gleicher `id` gewinnt der juengere. Ohne das verliert man jedes Mal alles,
// was auf dem Telefon dazukam, waehrend der Rechner aus war -- die Datei kaeme
// vollstaendig an, wuerde aber von der eigenen, aelteren Fassung ueberschrieben.
//
// Geloescht wird ebenfalls nicht durch Weglassen, sondern mit `deleted: true`.
// Ein fehlender Eintrag ist von einem "auf der anderen Seite noch nicht
// bekannten" nicht zu unterscheiden -- ein weggelassener Eintrag kaeme beim
// naechsten Abgleich also wieder zurueck. Grabsteine verfallen nach
// `todoKeepDays` Tagen.
//
// Das Format ist absichtlich das des nblauncher (Android): eine flache Liste
// aus {id, text, done}. Die drei Zusatzfelder ignoriert dessen Leser einfach.
Singleton {
    id: root

    readonly property bool enabled: Config.value("todo", true)

    // Wo die Liste liegt. Vorgabe: beim uebrigen Zustand, also NICHT im
    // Sync-Ordner -- wer nicht abgleicht, soll auch keinen anlegen muessen.
    // Fuers Telefon zeigt `todoFile` in den geteilten Ordner:
    //
    //   nbshell set todoFile '~/Sync/nbshell/todo.json'
    readonly property string file: {
        const home = Quickshell.env("HOME");
        const wish = String(Config.value("todoFile", ""));
        if (wish !== "")
            return wish.replace(/^~/, home);
        return (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/nbshell/todo.json";
    }

    readonly property int keepDays: Config.value("todoKeepDays", 30)
    readonly property bool showDone: Config.value("todoShowDone", true)

    // Alles, was in der Datei steht -- inklusive Grabsteine.
    property var items: []

    // Was man sieht: offene zuerst, in der Reihenfolge des Eintragens,
    // erledigte darunter, zuletzt Abgehaktes oben.
    readonly property var list: {
        const alive = root.items.filter(e => !e.deleted && (root.showDone || !e.done));
        const open = alive.filter(e => !e.done).sort((a, b) => a.created - b.created);
        const done = alive.filter(e => e.done).sort((a, b) => b.updated - a.updated);
        return open.concat(done);
    }

    readonly property int count: root.items.filter(e => !e.deleted && !e.done).length
    readonly property int doneCount: root.items.filter(e => !e.deleted && e.done).length

    readonly property string script: Qt.resolvedUrl("../scripts/todo.sh").toString().replace("file://", "")

    function now() {
        return Date.now();
    }

    // Die id ist der Zeitpunkt des Eintragens in Millisekunden -- dasselbe, was
    // der nblauncher vergibt (`System.currentTimeMillis()`). Zwei Eintraege in
    // derselben Millisekunde gibt es nur beim Einfuegen mehrerer Zeilen; dann
    // rueckt der zweite eine Millisekunde weiter.
    function newId() {
        var id = now();
        const taken = ({});
        for (var i = 0; i < root.items.length; i++)
            taken[String(root.items[i].id)] = true;
        while (taken[String(id)])
            id += 1;
        return id;
    }

    function find(id) {
        for (var i = 0; i < root.items.length; i++)
            if (String(root.items[i].id) === String(id))
                return root.items[i];
        return null;
    }

    // ── Aendern ───────────────────────────────────────────────────────────
    // Jede Aenderung setzt `updated`. Das ist der einzige Schiedsrichter beim
    // Zusammenfuehren -- wer das vergisst, dessen Aenderung verliert.

    function add(text) {
        const clean = String(text).trim();
        if (clean === "")
            return null;
        const t = now();
        const entry = {
            "id": newId(),
            "text": clean,
            "done": false,
            "created": t,
            "updated": t,
            "deleted": false
        };
        root.items = root.items.concat([entry]);
        save();
        return entry;
    }

    function setDone(id, done) {
        change(id, e => {
            e.done = !!done;
        });
    }

    function toggle(id) {
        const e = find(id);
        if (e)
            setDone(id, !e.done);
    }

    function edit(id, text) {
        const clean = String(text).trim();
        if (clean === "")
            return;
        change(id, e => {
            e.text = clean;
        });
    }

    function remove(id) {
        change(id, e => {
            e.deleted = true;
        });
    }

    function clearDone() {
        const t = now();
        var hit = 0;
        const next = root.items.map(e => {
            if (e.deleted || !e.done)
                return e;
            hit += 1;
            return Object.assign({}, e, {
                "deleted": true,
                "updated": t
            });
        });
        if (hit === 0)
            return 0;
        root.items = next;
        save();
        return hit;
    }

    function change(id, fn) {
        var hit = false;
        const next = root.items.map(e => {
            if (String(e.id) !== String(id))
                return e;
            hit = true;
            const copy = Object.assign({}, e);
            fn(copy);
            copy.updated = now();
            return copy;
        });
        if (!hit)
            return;
        root.items = next;
        save();
    }

    // ── Lesen und Zusammenfuehren ─────────────────────────────────────────

    // Aus einem beliebigen JSON eine Liste vollstaendiger Eintraege machen.
    // Bewusst nachsichtig: die Fassung des nblauncher kennt weder `updated`
    // noch `deleted`, und eine von Hand getippte Zeile kennt nur `text`.
    function normalize(raw) {
        var arr = raw;
        if (arr && !Array.isArray(arr) && Array.isArray(arr.items))
            arr = arr.items;
        if (!Array.isArray(arr))
            return [];
        const out = [];
        for (var i = 0; i < arr.length; i++) {
            const e = arr[i];
            if (!e || typeof e !== "object")
                continue;
            const text = String(e.text ?? "").trim();
            if (text === "")
                continue;
            const created = Number(e.created ?? e.id ?? 0) || 0;
            out.push({
                "id": e.id ?? created,
                "text": text,
                "done": !!e.done,
                "created": created,
                // Ohne Zeitstempel gilt der Eintrag als uralt: eine Fassung
                // MIT Stempel soll ihn schlagen, nicht umgekehrt.
                "updated": Number(e.updated ?? 0) || 0,
                "deleted": !!e.deleted
            });
        }
        return out;
    }

    // Zwei Listen zu einer. Bei gleicher id gewinnt der juengere Eintrag; bei
    // gleichem Stempel die eigene Seite (sonst flackerte es beim Vergleich mit
    // der gerade selbst geschriebenen Datei).
    function merge(mine, theirs) {
        const by = ({});
        const order = [];
        function put(e) {
            const key = String(e.id);
            const have = by[key];
            if (!have) {
                by[key] = e;
                order.push(key);
                return;
            }
            if (e.updated > have.updated)
                by[key] = e;
        }
        for (var i = 0; i < mine.length; i++)
            put(mine[i]);
        for (var j = 0; j < theirs.length; j++)
            put(theirs[j]);
        return order.map(k => by[k]);
    }

    // Grabsteine, die niemand mehr braucht. Sie muessen lange genug liegen
    // bleiben, dass jedes Geraet den Loeschvorgang einmal gesehen hat -- ein
    // Telefon, das drei Wochen im Flugmodus war, brauchte ihn noch.
    function purge(list) {
        if (root.keepDays <= 0)
            return list;
        const limit = now() - root.keepDays * 86400000;
        return list.filter(e => !e.deleted || e.updated >= limit);
    }

    // Vergleicht zwei Listen inhaltlich. Nur dafuer da, um NICHT zu schreiben,
    // wenn die Datei ohnehin schon stimmt: der eigene Beobachter meldet jede
    // Aenderung, und ein Schreiben bei jedem Lesen liefe im Kreis.
    function same(a, b) {
        if (a.length !== b.length)
            return false;
        for (var i = 0; i < a.length; i++) {
            const x = a[i];
            const y = b[i];
            if (String(x.id) !== String(y.id) || x.text !== y.text || x.done !== y.done || x.deleted !== y.deleted || x.updated !== y.updated)
                return false;
        }
        return true;
    }

    function apply(text) {
        // **Eine leere Datei heisst NICHT "drueben ist alles geloescht".** Sie
        // heisst fast immer: da schreibt gerade jemand. Wer eine Datei ersetzt,
        // ohne sie vorher unter einem anderen Namen fertigzuschreiben, kuerzt
        // sie zuerst auf 0 Bytes -- `adb pull` tut das, mancher Abgleich auch.
        // Wird dieser Moment als leere Liste gelesen, gewinnt die eigene Seite
        // jeden Vergleich und schreibt ihren Stand ueber die Datei, die gerade
        // erst zur Haelfte angekommen ist. Genau so ging beim Ausprobieren ein
        // Eintrag vom Telefon verloren.
        //
        // Wirklich leer geloescht wird mit "[]" -- das ist Text und faellt hier
        // nicht durch.
        const trimmed = String(text || "").trim();
        if (trimmed === "")
            return;

        var raw = [];
        try {
            raw = JSON.parse(trimmed);
        } catch (e) {
            // Halb geschriebenes JSON. Auch das ist kein Grund, die eigene
            // Fassung darueberzuschreiben -- der naechste Versuch kommt gleich.
            console.warn("nbshell/todo: Datei unlesbar --", e);
            return;
        }
        // Gueltiges JSON, aber keine Liste -- das ist keine Aufgabendatei. Sie
        // als leere zu lesen fuehrte geradewegs zurueck ins Ueberschreiben.
        if (!Array.isArray(raw) && !(raw && Array.isArray(raw.items))) {
            console.warn("nbshell/todo: das ist keine Aufgabenliste --", root.file);
            return;
        }

        const theirs = normalize(raw);
        const merged = purge(merge(root.items, theirs));
        const changed = !same(merged, root.items);
        if (changed)
            root.items = merged;
        // Stand die Datei hinter uns zurueck -- weil das Telefon eine aeltere
        // Fassung geschickt hat oder Grabsteine verfallen sind --, bekommt sie
        // das Ergebnis zurueck. Stimmt sie schon, wird nicht geschrieben.
        if (!same(merged, theirs))
            save();
    }

    function save() {
        store.setText(JSON.stringify(root.items, null, 2) + "\n");
    }

    // Syncthing legt bei gleichzeitigen Aenderungen eine Konfliktkopie daneben,
    // statt eine Seite zu verwerfen. Die faltet das Skript in die Datei zurueck
    // -- nach derselben Regel wie oben. Ohne das laege der Rest der Aufgaben in
    // einer Datei, die niemand mehr ansieht.
    function foldConflicts() {
        folder.command = ["bash", root.script, "merge", root.file];
        folder.running = true;
    }

    function reload() {
        store.reload();
    }

    Component.onCompleted: if (root.enabled)
        root.foldConflicts()

    Timer {
        id: settle

        interval: 300
        onTriggered: {
            store.reload();
            // Eine Aenderung von aussen kann eine Konfliktkopie im Schlepptau
            // haben -- Syncthing schreibt beide im selben Zug.
            root.foldConflicts();
        }
    }

    Process {
        id: folder

        stdout: StdioCollector {
            onStreamFinished: if (String(text).trim() !== "")
                console.info("nbshell/todo:", String(text).trim())
        }
    }

    FileView {
        id: store

        path: root.file
        watchChanges: true
        atomicWrites: true
        printErrors: false

        // NICHT sofort lesen: wer die Datei ersetzt, braucht dafuer mehrere
        // Schritte, und die erste Meldung kommt schon nach dem ersten. Ein
        // kurzer Moment Abstand liest den fertigen Stand statt eines
        // Zwischenzustands -- und die Meldungen mehrerer Schritte fallen
        // ausserdem zu einem Lesen zusammen.
        onFileChanged: settle.restart()
        // Beim ersten Start gibt es die Datei noch nicht -- `printErrors: false`
        // laesst das durchgehen, und beim ersten Eintrag entsteht sie.
        onLoaded: root.apply(text())
    }
}
