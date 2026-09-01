pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Sitzung beenden, sperren, neu starten.
//
// Alles ueber logind bzw. den Kompositor -- kein eigener Mechanismus:
//
//   sperren     Hyprlock/PAM, gestaltet durch nbshells sicheren Wrapper.
//               nbshell baut BEWUSST keinen eigenen: ein Fehler darin sperrt
//               einen aus dem eigenen Rechner aus.
//   abmelden    Umbriel `session-quit`, for a clean compositor shutdown.
//   Rest        systemctl -- das kennt jede Distribution.
Singleton {
    id: root

    readonly property string lockScript: Qt.resolvedUrl("../scripts/lockscreen.py").toString().replace("file://", "")
    // Use the exact source currently displayed by Wallpaper.qml. Passing it
    // to the lock process also covers the short interval before an atomic
    // config write becomes visible to a separate process.
    readonly property string activeWallpaper: Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "")

    function lockArgs(action) {
        return ["env", "NBSHELL_LOCK_WALLPAPER=" + root.activeWallpaper, root.lockScript, action];
    }

    readonly property var actions: [
        {
            "id": "lock",
            "label": "Lock",
            "key": "s"
        },
        {
            "id": "logout",
            "label": "Log out",
            "key": "a"
        },
        {
            "id": "suspend",
            "label": "Suspend",
            "key": "b"
        },
        {
            "id": "hibernate",
            "label": "Hibernate",
            "key": "r"
        },
        {
            "id": "reboot",
            "label": "Restart",
            "key": "n"
        },
        {
            "id": "poweroff",
            "label": "Power off",
            "key": "x"
        }
    ]

    function run(id) {
        switch (id) {
        case "lock":
            Quickshell.execDetached(root.lockArgs("lock"));
            return true;
        case "logout":
            Compositor.logout();
            return true;
        case "suspend":
            // Der Wrapper startet zuerst den echten Wayland-Locker und bricht
            // ab, falls dieser vor dem Suspend wieder stirbt.
            Quickshell.execDetached(root.lockArgs("suspend"));
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
