pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Common

// Benachrichtigungen.
//
// Hier haengt der Server selbst -- nbshell meldet sich als
// org.freedesktop.Notifications an. Diesen Namen bekommt genau EIN Prozess:
// das ist die eine Stelle, an der sich zwei Shells nicht vertragen.
//
// Deshalb ist er VORGABEMAESSIG AUS (`notifications` in der Config).
// Der Grund ist haerter als "sie stoeren sich": `dms.service` ist
// `Type=dbus` mit `BusName=org.freedesktop.Notifications` -- systemd haelt DMS
// erst fuer gestartet, wenn dieser Name auftaucht. Nimmt nbshell ihn, bleibt
// die DMS-Unit ewig in "activating" haengen und wird schliesslich als
// fehlgeschlagen neu gestartet, obwohl der Prozess laeuft.
//
// Umschalten also bewusst: `nbshell notify server on`, und dazu
// `systemctl --user stop dms.service`.
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

    readonly property bool enabled: Config.value("notifications", false)

    readonly property bool dnd: Config.value("dnd", false)
    readonly property int popupTimeout: Config.value("notifyTimeout", 6000)
    readonly property int keep: Config.value("notifyKeep", 50)

    // Wie alt eine Karte hoechstens sein darf, um einen Neustart der Shell zu
    // ueberleben. Ohne Grenze staende nach einer Nacht im Standby der ganze
    // Stapel von gestern wieder da.
    readonly property int popupRevive: Config.value("notifyReviveMs", 300000)

    // Alles, was hereinkam -- neueste zuerst.
    property var history: []

    // Was gerade als Karte am Rand steht.
    property var popups: []

    readonly property int count: history.length

    // Gesucht wird ueber den Schluessel, NICHT ueber das Objekt: was ein
    // Repeater als `modelData` herausgibt, ist eine eigene Verpackung desselben
    // Werts -- `!==` trifft damit immer zu, und die Karte bliebe ewig stehen.
    // Genau so ist es passiert.
    function dismissPopup(key) {
        popups = popups.filter(p => p.key !== key);
        save();
    }

    function drop(key) {
        const entry = history.find(p => p.key === key) ?? popups.find(p => p.key === key);
        popups = popups.filter(p => p.key !== key);
        history = history.filter(p => p.key !== key);
        entry?.notification?.dismiss();
        save();
    }

    function clear() {
        const items = history.slice();
        history = [];
        popups = [];
        for (var i = 0; i < items.length; i++)
            items[i].notification?.dismiss();
        save();
    }

    function setDnd(value) {
        Config.set("dnd", value);
        if (value) {
            popups = [];
            save();
        }
    }

    function invoke(key, action) {
        action.invoke();
        dismissPopup(key);
    }

    // Zeit als "vor 3 min", nicht als Uhrzeit: bei einer Benachrichtigung
    // interessiert der Abstand, nicht der Zeitpunkt.
    function ago(date) {
        const secs = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
        if (secs < 60)
            return "gerade";
        if (secs < 3600)
            return "vor " + Math.floor(secs / 60) + " min";
        if (secs < 86400)
            return "vor " + Math.floor(secs / 3600) + " h";
        return "vor " + Math.floor(secs / 86400) + " d";
    }

    // ── Archiv auf der Platte ────────────────────────────────────────────
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/notifications.json"

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
                    "urgency": e.urgency,
                    "time": e.time.getTime(),
                    "pending": pending.some(p => p.key === e.key)
                }));
        store.setText(JSON.stringify(out));
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
                        "urgency": e.urgency,
                        "time": new Date(e.time),
                        "pending": e.pending === true,
                        "notification": null
                    })).slice(0, root.keep);

            root.history = restored;
            // Nur was beim Beenden noch am Rand stand und nicht laengst
            // veraltet ist, kommt zurueck auf den Bildschirm.
            root.popups = restored.filter(e => e.pending && (now - e.time.getTime()) < root.popupRevive);
        }
        onLoadFailed: {
            root.history = [];
            root.popups = [];
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
                const entry = {
                    // Zeitpunkt UND id: die id allein wiederholt sich nach
                    // einem Neustart des Servers.
                    "key": now.getTime() + ":" + notification.id,
                    "id": notification.id,
                    "appName": notification.appName,
                    "summary": notification.summary,
                    "body": notification.body,
                    "urgency": notification.urgency,
                    "time": now,
                    "notification": notification
                };

                root.history = [entry].concat(root.history).slice(0, root.keep);

                // Bei "Nicht stoeren" landet sie nur in der Liste. `transient`
                // heisst: das Programm will sie zeigen, aber nicht aufbewahren --
                // trotzdem in die Liste, sonst verschwindet sie spurlos.
                if (!root.dnd)
                    root.popups = [entry].concat(root.popups);

                root.save();

                notification.closed.connect(() => {
                    root.popups = root.popups.filter(p => p.key !== entry.key);
                    root.save();
                });
            }
        }
    }
}
