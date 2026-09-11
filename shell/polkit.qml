//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell.polkit
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.Common
import qs.Polkit

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    PolkitAgent { id: agent; path: "/dev/nerdi/nbshell/Polkit" }
    // Registration failure exits; the supervisor activates the fallback agent.
    Timer {
        interval: 5000
        running: !agent.isRegistered
        onTriggered: Qt.quit()
    }
    IpcHandler {
        target: "polkit"
        function status(): string {
            return JSON.stringify({registered: agent.isRegistered, active: agent.isActive});
        }
    }
    PanelWindow {
        id: window
        visible: agent.isActive && agent.flow !== null && !agent.flow.isCompleted
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { left: true; right: true; top: true; bottom: true }
        WlrLayershell.namespace: "nbshell:polkit"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible) dialog.focusInput()
        Rectangle { anchors.fill: parent; color: Theme.scrim }
        AuthDialog {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Math.max(1, parent.width - Theme.panelPadding * 2))
            height: Math.min(implicitHeight, Math.max(1, parent.height - Theme.panelPadding * 2))
            flow: agent.flow
        }
    }
}
