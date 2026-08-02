pragma Singleton

import QtQuick
import Quickshell
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
Singleton {
    id: root

    readonly property bool enabled: Config.value("notifications", false)

    readonly property bool dnd: Config.value("dnd", false)
    readonly property int popupTimeout: Config.value("notifyTimeout", 6000)
    readonly property int keep: Config.value("notifyKeep", 50)

    // Alles, was hereinkam -- neueste zuerst.
    property var history: []

    // Was gerade als Karte am Rand steht.
    property var popups: []

    readonly property int count: history.length

    // Gesucht wird ueber die id, NICHT ueber das Objekt: was ein Repeater als
    // `modelData` herausgibt, ist eine eigene Verpackung desselben Werts --
    // `!==` trifft damit immer zu, und die Karte bliebe ewig stehen. Genau so
    // ist es passiert.
    function dismissPopup(id) {
        popups = popups.filter(p => p.id !== id);
    }

    function drop(id) {
        const entry = history.find(p => p.id === id) ?? popups.find(p => p.id === id);
        popups = popups.filter(p => p.id !== id);
        history = history.filter(p => p.id !== id);
        entry?.notification?.dismiss();
    }

    function clear() {
        const items = history.slice();
        history = [];
        popups = [];
        for (var i = 0; i < items.length; i++)
            items[i].notification?.dismiss();
    }

    function setDnd(value) {
        Config.set("dnd", value);
        if (value)
            popups = [];
    }

    function invoke(id, action) {
        action.invoke();
        dismissPopup(id);
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

                const entry = {
                    "notification": notification,
                    "time": new Date(),
                    "id": notification.id
                };

                root.history = [entry].concat(root.history).slice(0, root.keep);

                // Bei "Nicht stoeren" landet sie nur in der Liste. `transient`
                // heisst: das Programm will sie zeigen, aber nicht aufbewahren --
                // trotzdem in die Liste, sonst verschwindet sie spurlos.
                if (!root.dnd)
                    root.popups = [entry].concat(root.popups);

                notification.closed.connect(() => {
                    root.popups = root.popups.filter(p => p.id !== entry.id);
                });
            }
        }
    }
}
