pragma Singleton
import QtQuick
import Quickshell

// Read-only, in-memory hover snapshot from the standalone Calendar's accounts.
Singleton {
    id: root
    readonly property string pluginId: "io.github.nbshell.calendar"
    readonly property var plugin: Plugins.entry(pluginId)
    readonly property bool available: !!plugin && Plugins.enabledIds.indexOf(pluginId) >= 0
    property bool requested: false
    property date today: new Date()
    property double requestedAt: 0
    property string requestedDay: ""
    readonly property var backend: loader.item
    readonly property bool busy: requested && loader.status !== Loader.Error && (loader.status === Loader.Loading || !backend || backend.busy)
    readonly property bool stale: !!backend && backend.stale
    readonly property string error: loader.status === Loader.Error ? "Calendar preview unavailable" : backend ? backend.error : ""
    readonly property var events: backend ? backend.events.filter(e => backend.calendars.some(c => c.key === e.calendarKey && c.visible)) : []
    readonly property var days: [day(0), day(1), day(2)]

    function day(offset) { return new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset); }
    function parse(value) {
        if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
            const p = value.split("-"); return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
        }
        return new Date(value);
    }
    function eventsOn(date) {
        const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1);
        return events.filter(e => parse(e.start) < end && parse(e.end) > date)
            .sort((a,b) => Number(b.allDay) - Number(a.allDay) || parse(a.start) - parse(b.start));
    }
    function refresh() {
        if (!available) return;
        const now = new Date();
        const changedDay = requestedDay !== now.toDateString();
        today = now;
        requested = true;
        if (!backend || backend.busy) return;
        // Reopening a hover card must not repeatedly contact calendar providers.
        if (!changedDay && Date.now() - requestedAt < 300000) return;
        requestedAt = Date.now();
        requestedDay = now.toDateString();
        backend.refresh(day(0).toISOString(), day(3).toISOString());
    }
    onAvailableChanged: if (!available) { requested = false; requestedAt = 0; }
    Loader {
        id: loader
        active: root.requested && root.available
        asynchronous: true
        source: root.plugin && root.plugin.entryPoints && root.plugin.entryPoints.panel
            ? "file://" + root.plugin.entryPoints.panel.replace(/[^/]+$/, "Service.qml") : ""
        onLoaded: root.refresh()
    }
}
