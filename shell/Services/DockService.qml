pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import "../Dock/DockModel.js" as DockModel

Singleton {
    id: root
    readonly property var pins: {
        const value = Config.value("dockPins", []);
        return Array.isArray(value) ? value.filter(id => typeof id === "string") : [];
    }
    readonly property var groups: DockModel.groups(Apps.entries, Compositor.windows, pins)
    // Keep delegate identities stable when only focus/title/window state changes.
    // Rebuilding every icon on an IPC event would destroy keyboard focus.
    property var groupKeys: []
    onGroupsChanged: {
        const next = groups.map(g => g.key);
        if (JSON.stringify(next) !== JSON.stringify(groupKeys)) groupKeys = next;
    }
    property var surfaces: ({})
    property var previewOwner: null
    readonly property bool previewActive: previewOwner !== null && Config.dockEnabled
    property int pendingScale: -1
    property int pendingIconScale: -1
    readonly property int dockScale: pendingScale >= 0 ? pendingScale : Config.dockScale
    readonly property int dockIconScale: pendingIconScale >= 0 ? pendingIconScale : Config.dockIconScale

    function previewSize(key, value) {
        if (!Config.configValid || !Number.isFinite(value)) return;
        if (key === "dockScale") pendingScale = Math.round(Math.max(75, Math.min(200, value)));
        else if (key === "dockIconScale") pendingIconScale = Math.round(Math.max(50, Math.min(200, value)));
    }
    function commitSize(key, value) {
        previewSize(key, value);
        if (key === "dockScale") { Config.set(key, dockScale); pendingScale = -1; }
        else if (key === "dockIconScale") { Config.set(key, dockIconScale); pendingIconScale = -1; }
    }
    function clearSizePreview() { pendingScale = -1; pendingIconScale = -1; }
    signal revealRequested(string output)
    signal hideRequested()

    function pin(group) {
        if (!group?.entry) return;
        const id = group.entry.id;
        Config.set("dockPins", pins.includes(id) ? pins.filter(p => p !== id) : pins.concat([id]));
    }
    function report(output, state) {
        const next = Object.assign({}, surfaces);
        if (state === null) delete next[output];
        else next[output] = state;
        surfaces = next;
    }
    function focusWindow(id) {
        if (!Compositor.windows.some(w => String(w.id) === String(id))) return;
        Compositor.focusWindow(id);
        hideRequested();
    }
    function launch(entry) {
        if (Apps.launch(entry)) hideRequested();
    }
    function closeGroup(key) {
        const ids = (groups.find(g => g.key === key)?.windows ?? []).map(w => w.id);
        if (!ids.length) return;
        // Release the menu's keyboard grab before an app opens a save dialog.
        hideRequested();
        for (const id of ids) Compositor.closeWindow(id);
    }
}
