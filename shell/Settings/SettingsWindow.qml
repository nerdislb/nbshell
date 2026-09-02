import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
    id: root

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"

    WlrLayershell.namespace: "nbshell:settings"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.settingsOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function requestClose(done) { menu.requestClose(done); }
    function requestOpen() { menu.requestOpen(); }

    SettingsMenu {
        id: menu
        anchors.fill: parent
        externalLifecycle: true
    }
}
