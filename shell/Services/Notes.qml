pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Small, device-neutral notes store. Entries are merged independently so a
// laptop and phone can safely edit different notes while either is offline.
Singleton {
    id: root

    readonly property bool enabled: Config.value("notes", true)
    readonly property string file: {
        const home = Quickshell.env("HOME");
        const wish = String(Config.value("notesFile", ""));
        if (wish !== "")
            return wish.replace(/^~/, home);
        return (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/nbshell/notes.json";
    }
    readonly property int keepDays: Config.value("notesKeepDays", 30)
    readonly property string script: Qt.resolvedUrl("../scripts/todo.sh").toString().replace("file://", "")

    property var items: []
    readonly property var list: root.items
        .filter(e => !e.deleted)
        .sort((a, b) => b.updated - a.updated)
    readonly property int count: root.list.length

    function now() { return Date.now(); }

    function newId() {
        var id = now();
        while (find(id)) id += 1;
        return id;
    }

    function find(id) {
        for (var i = 0; i < root.items.length; i++)
            if (String(root.items[i].id) === String(id)) return root.items[i];
        return null;
    }

    function titleFor(text) {
        const lines = String(text).split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            const clean = lines[i].trim().replace(/^#+\s*/, "");
            if (clean !== "") return clean.length > 48 ? clean.substring(0, 47) + "…" : clean;
        }
        return "Untitled note";
    }

    function saveText(id, text) {
        const body = String(text).replace(/\s+$/, "");
        if (body.trim() === "") return null;
        const t = now();
        const old = id !== "" ? find(id) : null;
        if (old) {
            root.items = root.items.map(e => String(e.id) === String(id)
                ? Object.assign({}, e, {"title": titleFor(body), "text": body, "updated": t, "deleted": false}) : e);
        } else {
            id = newId();
            root.items = root.items.concat([{
                "id": id, "title": titleFor(body), "text": body,
                "created": t, "updated": t, "deleted": false
            }]);
        }
        save();
        return find(id);
    }

    function remove(id) {
        const t = now();
        root.items = root.items.map(e => String(e.id) === String(id)
            ? Object.assign({}, e, {"updated": t, "deleted": true}) : e);
        save();
    }

    function normalize(raw) {
        var arr = raw;
        if (arr && !Array.isArray(arr) && Array.isArray(arr.items)) arr = arr.items;
        if (!Array.isArray(arr)) return [];
        const out = [];
        for (var i = 0; i < arr.length; i++) {
            const e = arr[i];
            if (!e || typeof e !== "object" || e.id === undefined) continue;
            const text = String(e.text ?? "");
            const created = Number(e.created ?? e.id ?? 0) || 0;
            out.push({
                "id": e.id, "title": String(e.title ?? titleFor(text)), "text": text,
                "created": created, "updated": Number(e.updated ?? 0) || 0,
                "deleted": !!e.deleted
            });
        }
        return out;
    }

    function merge(mine, theirs) {
        const by = ({});
        mine.concat(theirs).forEach(e => {
            const key = String(e.id);
            if (!by[key] || e.updated > by[key].updated) by[key] = e;
        });
        return Object.keys(by).map(k => by[k]);
    }

    function purge(list) {
        if (root.keepDays <= 0) return list;
        const limit = now() - root.keepDays * 86400000;
        return list.filter(e => !e.deleted || e.updated >= limit);
    }

    function same(a, b) {
        if (a.length !== b.length) return false;
        const sa = a.slice().sort((x, y) => String(x.id).localeCompare(String(y.id)));
        const sb = b.slice().sort((x, y) => String(x.id).localeCompare(String(y.id)));
        for (var i = 0; i < sa.length; i++) {
            if (String(sa[i].id) !== String(sb[i].id) || sa[i].text !== sb[i].text
                    || sa[i].title !== sb[i].title || sa[i].updated !== sb[i].updated
                    || sa[i].deleted !== sb[i].deleted) return false;
        }
        return true;
    }

    function apply(text) {
        const clean = String(text || "").trim();
        if (clean === "") return;
        var raw;
        try { raw = JSON.parse(clean); }
        catch (e) { console.warn("nbshell/notes: file unreadable --", e); return; }
        if (!Array.isArray(raw) && !(raw && Array.isArray(raw.items))) return;
        const theirs = normalize(raw);
        const merged = purge(merge(root.items, theirs));
        if (!same(merged, root.items)) root.items = merged;
        if (!same(merged, theirs)) save();
    }

    function save() { store.setText(JSON.stringify(root.items, null, 2) + "\n"); }
    function reload() { store.reload(); }
    function foldConflicts() {
        merger.command = ["bash", root.script, "merge", root.file];
        merger.running = true;
    }

    Component.onCompleted: if (root.enabled) root.foldConflicts()

    Timer { id: settle; interval: 300; onTriggered: { store.reload(); root.foldConflicts(); } }
    Process { id: merger }
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
