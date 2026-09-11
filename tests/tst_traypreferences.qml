import QtQuick
import QtTest
import "../shell/Bar/Widgets/TrayPreferences.js" as Preferences

TestCase {
    name: "TrayPreferences"
    readonly property var apps: [
        {id: "chat", title: "Chat", status: 1},
        {id: "sync", title: "Sync", status: 1},
        {id: "idle", title: "Idle", status: 0},
        {id: "alert", title: "Alert", status: 2}
    ]
    function ids(items) { return items.map(item => item.id).join(","); }
    function test_drawer_and_passive() {
        compare(ids(Preferences.visibleItems(apps, {}, false, 0)), "");
        compare(ids(Preferences.visibleItems(apps, {}, true, 0)), "chat,sync,alert");
    }
    function test_pin_hide_restore_and_reconnect() {
        let p = Preferences.updated({}, apps[1], "pinned");
        p = Preferences.updated(p, apps[0], "hidden");
        compare(ids(Preferences.visibleItems(apps, p, false, 0)), "sync");
        compare(ids(Preferences.visibleItems(apps, p, true, 0)), "sync,alert");
        const reconnected = {id: "sync", title: "Changed title", status: 1};
        compare(Preferences.mode(JSON.parse(JSON.stringify(p)), reconnected), "pinned");
        const old = JSON.stringify(p);
        const restored = Preferences.updated(p, apps[0], "drawer");
        compare(JSON.stringify(p), old);
        compare(ids(Preferences.visibleItems(apps, restored, true, 0)), "sync,chat,alert");
        compare(Preferences.mode(Preferences.updated(p, apps[1], "hidden"), apps[1]), "hidden");
    }
    function test_missing_id_and_invalid_preferences() {
        compare(Preferences.key({id: ""}), "");
        compare(JSON.stringify(Preferences.updated({}, {title: "temporary"}, "hidden")), "{}");
        compare(Preferences.mode({"app:chat": "invalid"}, apps[0]), "drawer");
        compare(Preferences.mode(Preferences.updated(null, apps[0], "pinned"), apps[0]), "pinned");
        compare(Preferences.mode(Preferences.updated({}, {id: "__proto__"}, "hidden"), {id: "__proto__"}), "hidden");
    }
    function test_status_change() {
        const p = Preferences.updated({}, apps[0], "pinned");
        compare(ids(Preferences.visibleItems([{id: "chat", status: 0}], p, false, 0)), "");
        compare(ids(Preferences.visibleItems([{id: "chat", status: 2}], p, false, 0)), "chat");
    }
}
