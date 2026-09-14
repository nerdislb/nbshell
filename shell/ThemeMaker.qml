import QtQuick
import QtQuick.Window as Windows
import Quickshell
import "ThemeMaker" as Editor

// A separate engine keeps draft colors out of the desktop's ThemeExport path.
ShellRoot {
    Windows.Window {
        id: window
        title: "Theme Maker"
        visible: true
        width: 1240
        height: 840
        minimumWidth: 520
        minimumHeight: 480
        color: maker.chromeBackground
        Editor.ThemeMaker {
            id: maker
            anchors.fill: parent
            windowActive: window.active && window.visible
            onCloseRequested: window.close()
        }
        onClosing: event => {
            if (maker.busy) {
                event.accepted = false;
                maker.message = "Wait for the current operation to finish before closing.";
            } else if (maker.dirty && !maker.allowClose) {
                event.accepted = false;
                maker.confirmClose = true;
            } else Qt.quit();
        }
    }
}
