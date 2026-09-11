import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false
    property bool closingFromHost: false

    readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.nbshell.calendar"

    function open(payloadJson) {
        closingFromHost = false;
        opened = true;
        focusScope.refresh();
        Qt.callLater(() => focusScope.forceActiveFocus());
    }

    function close() {
        closingFromHost = true;
        opened = false;
        calendarService.cancel();
        focusScope.clearSecrets();
        closingFromHost = false;
    }

    function requestClose() {
        if (shell && typeof shell.hide === "function")
            shell.hide(pluginId);
        else
            close();
    }

    FloatingWindow {
        visible: root.opened
        title: "Calendar"
        color: Theme.panelSurface
        implicitWidth: Theme.cellW * 100
        implicitHeight: Theme.cellH * 36
        minimumSize: Qt.size(Theme.cellW * 30, Theme.cellH * 16)

        onVisibleChanged: {
            if (!visible && root.opened && !root.closingFromHost)
                root.requestClose();
        }

        PanelSurface {
            anchors.fill: parent

            CalendarView {
                id: focusScope
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                backend: calendarService
                onCloseRequested: root.requestClose()
            }
        }
    }
    Service { id: calendarService }
}
