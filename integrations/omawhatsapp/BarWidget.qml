import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    readonly property var oma: Plugins.serviceFor("omawhatsapp")
    readonly property int unread: oma ? Math.max(0, Number(oma.notificationUnreadCount || 0)) : 0

    shown: true
    quiet: false
    label: "WA"
    icon: "󰖣"
    text: unread > 0 ? (unread > 99 ? "99+" : String(unread)) : ""
    slotChars: unread > 0 ? 3 : 0
    color: oma && oma.ready ? (unread > 0 ? Theme.green : Theme.barAccent) : Theme.textDim
    interactive: true

    onClicked: Plugins.toggle("omawhatsapp", "{}")
    onMiddleClicked: if (oma) oma.dismissNotifications("")
    onRightClicked: if (oma) oma.refresh()
}
