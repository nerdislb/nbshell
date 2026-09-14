import QtQuick
import QtQuick.Window as Windows
import Quickshell
import qs.Common
import "Touchpad" as Input

ShellRoot {
    Windows.Window {
        id: window
        title: "Touchpad · nbshell"
        visible: true
        width: Theme.cellW * 88
        height: Theme.cellH * 42
        minimumWidth: Theme.cellW * 36
        minimumHeight: Theme.cellH * 20
        color: Theme.panelSurface
        Input.TouchpadPanel {
            id: panel
            anchors.fill: parent
            onCloseRequested: window.close()
        }
        onClosing: event => {
            if (panel.busy) {
                event.accepted = false;
                panel.message = "Wait for the current operation to finish.";
            } else if (panel.dirty && !panel.allowClose) {
                event.accepted = false;
                panel.confirmClose = true;
            } else Qt.quit();
        }
    }
}
