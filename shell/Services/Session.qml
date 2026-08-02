pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Sitzung beenden, sperren, neu starten.
//
// Alles ueber logind bzw. den Kompositor -- kein eigener Mechanismus:
//
//   sperren     der Sperrbildschirm aus der Config (Vorgabe hyprlock).
//               nbshell baut BEWUSST keinen eigenen: ein Fehler darin sperrt
//               einen aus dem eigenen Rechner aus.
//   abmelden    `niri msg action quit`, damit niri sauber herunterfaehrt.
//   Rest        systemctl -- das kennt jede Distribution.
Singleton {
    id: root

    readonly property string lockCommand: Config.value("lockCommand", "hyprlock")

    readonly property var actions: [
        {
            "id": "lock",
            "label": "Sperren",
            "key": "s"
        },
        {
            "id": "logout",
            "label": "Abmelden",
            "key": "a"
        },
        {
            "id": "suspend",
            "label": "Bereitschaft",
            "key": "b"
        },
        {
            "id": "hibernate",
            "label": "Ruhezustand",
            "key": "r"
        },
        {
            "id": "reboot",
            "label": "Neu starten",
            "key": "n"
        },
        {
            "id": "poweroff",
            "label": "Ausschalten",
            "key": "x"
        }
    ]

    function run(id) {
        switch (id) {
        case "lock":
            Quickshell.execDetached(["sh", "-c", root.lockCommand]);
            return true;
        case "logout":
            Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]);
            return true;
        case "suspend":
            Quickshell.execDetached(["systemctl", "suspend"]);
            return true;
        case "hibernate":
            Quickshell.execDetached(["systemctl", "hibernate"]);
            return true;
        case "reboot":
            Quickshell.execDetached(["systemctl", "reboot"]);
            return true;
        case "poweroff":
            Quickshell.execDetached(["systemctl", "poweroff"]);
            return true;
        }
        return false;
    }

    function labelOf(id) {
        const a = actions.find(x => x.id === id);
        return a ? a.label : id;
    }
}
