pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Common

// Benachrichtigungen.
//
// nbshell owns org.freedesktop.Notifications in its supported Umbriel session.
// The server is enabled by default and can be disabled explicitly with
// `nbshell notify server off`.
//
// `keepOnReload: false`: nach dem Neuladen der QML-Dateien faengt die Liste
// leer an, statt Karteileichen aus der vorigen Runde zu behalten.
//
// Das Archiv liegt trotzdem auf der Platte, und zwar aus einem handfesten
// Grund: jedes `install.sh` und jedes `nbshell restart` startet die Shell neu.
// Lag die Liste nur im Speicher, war eine Meldung, die man noch nicht gelesen
// hatte, danach weg -- ausgerechnet beim Aktualisieren, wo am ehesten etwas
// schiefgeht. Deshalb steht jeder Eintrag als flaches Objekt in
// ~/.local/state/nbshell/notifications.json.
//
// Der Eintrag ist die Kopie, nicht die Benachrichtigung selbst: `notification`
// zeigt auf das lebende Objekt (fuer Aktionen und `dismiss`) und ist bei allem,
// was aus der Datei kommt, schlicht nicht da. Alles, was angezeigt wird, steht
// im Eintrag.
//
// Gesucht wird ueber `key`, nicht ueber `id`: der Server faengt seine Zaehlung
// nach einem Neustart wieder bei 1 an -- eine frische Meldung haette sonst
// dieselbe id wie eine aus der Datei, und ein Klick raeumte beide weg.
Singleton {
    id: root

    readonly property bool enabled: Config.value("notifications", true)

    readonly property bool dnd: Config.value("dnd", false)
    readonly property int normalPopupDuration: Config.value("notifyTimeout", 8000)
    readonly property int lowPopupDuration: 5000
    readonly property int maxPopupDuration: 30000
    readonly property int maxPopupCount: Config.value("notifyMaxPopups", 5)
    readonly property int keep: Config.value("notifyKeep", 200)
    readonly property int keepDays: Config.value("notifyKeepDays", 7)

    // Wie alt eine Karte hoechstens sein darf, um einen Neustart der Shell zu
    // ueberleben. Ohne Grenze staende nach einer Nacht im Standby der ganze
    // Stapel von gestern wieder da.
    readonly property int popupRevive: Config.value("notifyReviveMs", 300000)

    // Alles, was hereinkam -- neueste zuerst.
    property var history: []

    // Was gerade als Karte am Rand steht.
    property var popups: []
    property var popupRemaining: ({})
    property var popupHoverCounts: ({})
    property int keySerial: 0
    property double lastSeen: 0
    property double readMark: 0

    // Wiederholte identische Meldungen (Sync- und Build-Werkzeuge sind hier
    // besonders laut) werden zu einer Karte zusammengefasst.
    readonly property int dedupeWindow: Config.value("notifyDedupeMs", 120000)

    readonly property int count: history.length
    readonly property int unreadCount: history.filter(e => e.time.getTime() > lastSeen).length

    function requestedDuration(expireTimeout) {
        const value = Number(expireTimeout || 0);
        return isFinite(value) && value > 0 ? Math.round(value) : 0;
    }

    function popupDuration(entry) {
        if (entry?.urgency === NotificationUrgency.Critical || entry?.urgency === 2)
            return 0;
        const configured = Object.prototype.hasOwnProperty.call(Config.data, "notifyTimeout")
            ? Math.max(1, Number(Config.data.notifyTimeout) || normalPopupDuration)
            : (entry?.urgency === NotificationUrgency.Low || entry?.urgency === 0
                ? lowPopupDuration : normalPopupDuration);
        return Math.min(maxPopupDuration, Math.max(configured, requestedDuration(entry?.expireTimeout)));
    }

    function popupRemainingFor(key, lifetime) {
        const value = Number(popupRemaining[key]);
        if (Number.isFinite(value))
            return value;
        const initial = Math.max(0, Number(lifetime) || 0);
        popupRemaining[key] = initial;
        return initial;
    }

    function consumePopupLifetime(key, elapsed) {
        const next = Math.max(0, popupRemainingFor(key, 0) - Math.max(0, elapsed));
        popupRemaining[key] = next;
        return next;
    }

    function setPopupHovered(key, hovered) {
        if (key === undefined || key === null)
            return;
        const counts = Object.assign({}, popupHoverCounts);
        const next = Math.max(0, Number(counts[key] || 0) + (hovered ? 1 : -1));
        if (next > 0)
            counts[key] = next;
        else
            delete counts[key];
        popupHoverCounts = counts;
    }

    function forgetPopupLifetime(key) {
        if (key !== undefined && key !== null) {
            delete popupRemaining[key];
            const counts = Object.assign({}, popupHoverCounts);
            delete counts[key];
            popupHoverCounts = counts;
        }
    }

    // One service-owned clock advances each popup exactly once per interval.
    // Rendering the same toast on several outputs must not shorten its life.
    Timer {
        interval: 50
        repeat: true
        running: root.popups.some(entry => root.popupDuration(entry) > 0)
        onTriggered: {
            const expired = [];
            const snapshot = root.popups.slice();
            for (const entry of snapshot) {
                if (root.popupDuration(entry) <= 0
                        || Number(root.popupHoverCounts[entry.key] || 0) > 0)
                    continue;
                if (root.consumePopupLifetime(entry.key, interval) <= 0)
                    expired.push(entry.key);
            }
            for (const key of expired)
                root.dismissPopup(key);
        }
    }

    function shouldBypassDnd(notification) {
        const app = String(notification?.appName || "").toLowerCase();
        const critical = notification?.urgency === NotificationUrgency.Critical
            || notification?.urgency === 2;
        return app === "nbshell-action"
            || (critical && (app === "notify-send" || app === "nbshell"));
    }

    function isEphemeral(notification) {
        const app = String(notification?.appName || "").toLowerCase();
        var transient = false;
        try {
            transient = !!notification?.hints?.["transient"];
        } catch (e) {
            transient = false;
        }
        return transient || app === "nbshell-action";
    }

    function release(entry, reason) {
        const notification = entry?.notification;
        if (!notification) {
            forgetPopupLifetime(entry?.key);
            return;
        }
        try {
            if (notification.tracked) {
                if (reason === "expire" && typeof notification.expire === "function")
                    notification.expire();
                else if (reason === "dismiss")
                    notification.dismiss();
                else
                    notification.tracked = false;
            }
        } catch (e) {
            // The sender or server may already have destroyed the live object.
        }
        entry.notification = null;
        forgetPopupLifetime(entry.key);
    }

    function retained(items, nowMs) {
        const cutoff = Number(nowMs || Date.now()) - Math.max(1, keepDays) * 86400000;
        return items.filter(e => e.time.getTime() >= cutoff).slice(0, keep);
    }

    function markSeen() {
        readMark = lastSeen;
        lastSeen = Date.now();
        seenStore.setText(String(lastSeen));
        secureState.restart();
    }

    function dayLabel(date) {
        const value = new Date(date);
        const today = new Date();
        const startToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        const startValue = new Date(value.getFullYear(), value.getMonth(), value.getDate()).getTime();
        const days = Math.round((startToday - startValue) / 86400000);
        if (days === 0) return "TODAY";
        if (days === 1) return "YESTERDAY";
        return Qt.formatDateTime(value, "dddd · dd MMMM").toUpperCase();
    }

    readonly property var webSources: ({
        "reddit.com": { "name": "Reddit", "icon": "reddit" },
        "github.com": { "name": "GitHub", "icon": "github" },
        "youtube.com": { "name": "YouTube", "icon": "youtube" },
        "web.whatsapp.com": { "name": "WhatsApp", "icon": "whatsapp" },
        "whatsapp.com": { "name": "WhatsApp", "icon": "whatsapp" },
        "mail.google.com": { "name": "Gmail", "icon": "gmail" },
        "gmail.com": { "name": "Gmail", "icon": "gmail" },
        "web.telegram.org": { "name": "Telegram", "icon": "telegram" },
        "telegram.org": { "name": "Telegram", "icon": "telegram" },
        "discord.com": { "name": "Discord", "icon": "discord" },
        "instagram.com": { "name": "Instagram", "icon": "instagram" },
        "facebook.com": { "name": "Facebook", "icon": "facebook" },
        "x.com": { "name": "X", "icon": "twitter" },
        "twitter.com": { "name": "X", "icon": "twitter" },
        "linkedin.com": { "name": "LinkedIn", "icon": "linkedin" }
    })

    function plain(text) {
        return String(text ?? "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
    }

    function domain(entry) {
        const text = String(entry?.body ?? "");
        const match = text.match(/https?:\/\/([^\s\/'\"<>]+)/i);
        return match ? match[1].toLowerCase().replace(/^www\./, "") : "";
    }

    function webSource(entry) {
        const host = domain(entry);
        if (webSources[host]) return webSources[host];
        const keys = Object.keys(webSources);
        for (var i = 0; i < keys.length; i++)
            if (host.endsWith("." + keys[i])) return webSources[keys[i]];
        return null;
    }

    function sourceName(entry) {
        const site = webSource(entry);
        const app = String(entry?.appName || "System");
        return site ? site.name + " · " + app : app;
    }

    function sourceIcon(entry) {
        return webSource(entry)?.icon || entry?.appIcon || "";
    }

    function sourceGlyph(entry) {
        const app = String(entry?.appName || "").toLowerCase();
        const desktop = String(entry?.desktopEntry || "").toLowerCase();
        if (app.indexOf("nbshell agent") >= 0)
            return Icons.agent;
        if (app.indexOf("kde connect") >= 0 || desktop.indexOf("kdeconnect") >= 0)
            return Icons.phone;
        return "";
    }

    function focus(entry) {
        const app = String(entry?.desktopEntry || entry?.appName || "").toLowerCase();
        if (!app) return false;
        const candidates = Compositor.windows.filter(w => {
            const id = String(w.app_id || "").toLowerCase();
            const title = String(w.title || "").toLowerCase();
            const words = app.split(/[^a-z0-9]+/).filter(x => x.length > 2);
            if (id.indexOf(app) >= 0 || app.indexOf(id) >= 0 || title.indexOf(app) >= 0) return true;
            return words.some(word => id.indexOf(word) >= 0 || title.indexOf(word) >= 0);
        });
        if (candidates.length === 0) return false;
        Compositor.focusWindow(candidates[0].id);
        return true;
    }

    function open(entry) {
        const action = entry?.notification?.actions?.find(a => a.identifier === "default")
            ?? entry?.notification?.actions?.[0];
        if (action) {
            action.invoke();
            dismissPopup(entry.key);
            return true;
        }
        return focus(entry);
    }

    // Gesucht wird ueber den Schluessel, NICHT ueber das Objekt: was ein
    // Repeater als `modelData` herausgibt, ist eine eigene Verpackung desselben
    // Werts -- `!==` trifft damit immer zu, und die Karte bliebe ewig stehen.
    // Genau so ist es passiert.
    function dismissPopup(key) {
        const entry = popups.find(p => p.key === key);
        popups = popups.filter(p => p.key !== key);
        release(entry, "expire");
        save();
    }

    function drop(key) {
        const entry = history.find(p => p.key === key) ?? popups.find(p => p.key === key);
        popups = popups.filter(p => p.key !== key);
        history = history.filter(p => p.key !== key);
        release(entry, "dismiss");
        save();
    }

    function clear() {
        const items = history.slice();
        history = [];
        popups = [];
        for (var i = 0; i < items.length; i++)
            release(items[i], "dismiss");
        save();
    }

    function setDnd(value) {
        Config.set("dnd", value);
        if (value) {
            const items = popups.slice();
            popups = [];
            for (var i = 0; i < items.length; i++)
                release(items[i], "expire");
            save();
        }
    }

    function invoke(key, action) {
        action.invoke();
        dismissPopup(key);
    }

    // Relative time for recent entries, clock time for older ones.
    // interessiert der Abstand, nicht der Zeitpunkt.
    function ago(date) {
        const secs = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
        if (secs < 60)
            return "now";
        if (secs < 3600)
            return Math.floor(secs / 60) + "m ago";
        if (secs < 86400)
            return Math.floor(secs / 3600) + "h ago";
        return Qt.formatDateTime(date, "HH:mm");
    }

    // ── Archiv auf der Platte ────────────────────────────────────────────
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell"
    readonly property string statePath: stateDir + "/notifications.json"
    readonly property string seenPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/notifications-seen"

    // Temporary file icons are useful while a notification is alive, but
    // restoring them days later only produces broken-image warnings.
    function persistentIcon(value) {
        const icon = String(value || "");
        return icon.startsWith("/") || icon.startsWith("file://") ? "" : icon;
    }

    // Geschrieben wird die Kopie ohne `notification`: das lebende Objekt
    // gehoert Quickshell und liesse sich ohnehin nicht in JSON fassen.
    function save() {
        const pending = root.popups;
        const out = root.history.map(e => ({
                    "key": e.key,
                    "id": e.id,
                    "appName": e.appName,
                    "summary": e.summary,
                    "body": e.body,
                    "appIcon": root.persistentIcon(e.appIcon),
                    "desktopEntry": e.desktopEntry ?? "",
                    "urgency": e.urgency,
                    "expireTimeout": e.expireTimeout ?? 0,
                    "repeat": e.repeat ?? 1,
                    "time": e.time.getTime(),
                    "pending": pending.some(p => p.key === e.key)
                }));
        store.setText(JSON.stringify(out));
        secureState.restart();
    }

    Timer {
        id: secureState
        interval: 150
        onTriggered: {
            Quickshell.execDetached(["/usr/bin/chmod", "700", root.stateDir]);
            Quickshell.execDetached(["/usr/bin/chmod", "600", root.statePath, root.seenPath]);
        }
    }

    FileView {
        id: store

        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            var raw = [];
            try {
                raw = JSON.parse(text() || "[]");
            } catch (e) {
                raw = [];
            }
            if (!Array.isArray(raw))
                return;

            const now = Date.now();
            const restored = raw.map(e => ({
                        "key": String(e.key ?? e.id),
                        "id": e.id,
                        "appName": e.appName,
                        "summary": e.summary,
                        "body": e.body,
                        "appIcon": root.persistentIcon(e.appIcon),
                        "desktopEntry": e.desktopEntry ?? "",
                        "urgency": e.urgency,
                        "expireTimeout": e.expireTimeout ?? 0,
                        "repeat": e.repeat ?? 1,
                        "time": new Date(e.time),
                        "pending": e.pending === true,
                        "notification": null
                    }));

            root.history = root.retained(restored, now);
            secureState.restart();
            // Nur was beim Beenden noch am Rand stand und nicht laengst
            // veraltet ist, kommt zurueck auf den Bildschirm.
            root.popups = restored.filter(e => e.pending && (now - e.time.getTime()) < root.popupRevive)
                .slice(0, Math.max(1, root.maxPopupCount));
            for (var i = 0; i < root.popups.length; i++)
                root.popupRemainingFor(root.popups[i].key, root.popupDuration(root.popups[i]));
        }
        onLoadFailed: {
            root.history = [];
            root.popups = [];
        }
    }

    FileView {
        id: seenStore
        path: root.seenPath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.lastSeen = Number(text() || 0) || 0;
            root.readMark = root.lastSeen;
            secureState.restart();
        }
        onLoadFailed: {
            root.lastSeen = 0;
            root.readMark = 0;
        }
    }

    // Der Server steckt in einem Loader: nur so laesst er sich wirklich
    // abschalten -- ein bloss unsichtbarer Server haelt den D-Bus-Namen
    // trotzdem fest.
    Loader {
        active: root.enabled
        sourceComponent: serverComponent
    }

    Component {
        id: serverComponent

        NotificationServer {
                keepOnReload: false

            bodySupported: true
            actionsSupported: true
            imageSupported: true
            persistenceSupported: true
            inlineReplySupported: false

                onNotification: notification => {
                // Ohne `tracked` raeumt Quickshell die Benachrichtigung sofort
                // wieder weg -- sie waere dann nur ein Signal ohne Inhalt.
                notification.tracked = true;

                const now = new Date();
                const duplicate = root.history.find(e =>
                    e.appName === notification.appName
                    && e.summary === notification.summary
                    && e.body === notification.body
                    && now.getTime() - e.time.getTime() <= root.dedupeWindow);
                const entry = {
                    // Zeitpunkt, Server-id und laufende Generation: ersetzt
                    // ein Client zweimal im selben Millisekundentakt, darf der
                    // close-Callback der alten Generation nie die neue loeschen.
                    "key": now.getTime() + ":" + notification.id + ":" + (++root.keySerial),
                    "id": notification.id,
                    "appName": notification.appName,
                    "summary": notification.summary,
                    "body": notification.body,
                    "appIcon": notification.appIcon ?? "",
                    "desktopEntry": notification.desktopEntry ?? "",
                    "urgency": notification.urgency,
                    "expireTimeout": notification.expireTimeout ?? 0,
                    "repeat": duplicate ? ((duplicate.repeat ?? 1) + 1) : 1,
                    "time": now,
                    "notification": notification
                };

                notification.closed.connect(() => {
                    root.popups = root.popups.filter(p => p.key !== entry.key);
                    entry.notification = null;
                    root.forgetPopupLifetime(entry.key);
                    root.save();
                });

                const showPopup = !root.dnd || root.shouldBypassDnd(notification);
                const keepHistory = showPopup || !root.isEphemeral(notification);
                const previousHistory = root.history.slice();
                root.history = keepHistory
                    ? root.retained([entry].concat(root.history.filter(e => !duplicate || e.key !== duplicate.key)), now.getTime())
                    : root.history;

                // Keep only the active toast stack alive. Once a toast leaves
                // the screen its immutable snapshot remains in history, but
                // the sender-side Notification object must be released.
                if (showPopup) {
                    root.popupRemainingFor(entry.key, root.popupDuration(entry));
                    const previousPopups = root.popups.slice();
                    const nextPopups = [entry].concat(root.popups.filter(e => !duplicate || e.key !== duplicate.key))
                        .slice(0, Math.max(1, root.maxPopupCount));
                    root.popups = nextPopups;
                    for (var p = 0; p < previousPopups.length; p++)
                        if (!nextPopups.some(item => item.key === previousPopups[p].key))
                            root.release(previousPopups[p], "expire");
                } else {
                    root.release(entry, "release");
                }

                for (var h = 0; h < previousHistory.length; h++)
                    if (!root.history.some(item => item.key === previousHistory[h].key)
                            && !root.popups.some(item => item.key === previousHistory[h].key))
                        root.release(previousHistory[h], "release");

                root.save();
            }
        }
    }
}
