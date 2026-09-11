import QtQuick
import qs.Common
import qs.Widgets

Cell {
    id: root

    widgetId: "home"
    interactive: true
    custom: true
    active: Runtime.menuOpen || Runtime.dashboardOpen
    color: Theme.barFg
    accessibilityName: "Home"
    Accessible.description: "Open menu. Right-click or press Shift+F10 to open dashboard."

    function openDashboard() {
        if (!root.enabled)
            return;
        Runtime.closeMenu();
        Runtime.dashboardOpen = true;
    }

    onClicked: {
        Runtime.dashboardOpen = false;
        Runtime.openMenu();
    }
    onRightClicked: root.openDashboard()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            if (!event.isAutoRepeat)
                root.openDashboard();
            event.accepted = true;
        }
    }

    Image {
        source: Qt.resolvedUrl("../../Assets/nbshell-floppy.png")
        height: Math.round(Theme.cellH)
        width: height
        fillMode: Image.PreserveAspectFit
        smooth: false
        mipmap: false
    }
}
