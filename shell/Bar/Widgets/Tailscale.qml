import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    shown: Tailnet.available
    quiet: Tailnet.state !== "Running"
    slotChars: 3
    interactive: true
    label: "VPN"
    icon: "󰖂"
    text: Tailnet.onlinePeers
    color: Tailnet.state === "Running" ? Theme.green : Theme.yellow

    onPopoutVisibleChanged: if (popoutVisible) Tailnet.refresh()

    popout: Component {
        Column {
            id: panel
            property var closePopout: null
            readonly property real rowWidth: 42 * Theme.cellW
            spacing: Theme.cellH * 0.25

            Line { text: "TAILSCALE  —  " + Tailnet.state.toUpperCase(); color: Tailnet.state === "Running" ? Theme.green : Theme.yellow }
            Line {
                width: panel.rowWidth
                text: Tailnet.host + (Tailnet.ip ? "  ·  " + Tailnet.ip : "")
                color: Theme.fg
                elide: Text.ElideRight
                TapHandler { onTapped: Tailnet.copy(Tailnet.ip) }
            }
            Line { text: "DEVICES  (" + Tailnet.onlinePeers + " online)"; color: Theme.fgDim }

            Repeater {
                model: Tailnet.peers
                Rectangle {
                    id: peerRow
                    required property var modelData
                    width: panel.rowWidth
                    height: Theme.cellH * 2.2
                    radius: Theme.radius
                    color: hover.hovered ? Theme.hover : "transparent"

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.cellW / 2
                        Line { width: parent.width; text: (peerRow.modelData.online ? "●  " : "○  ") + peerRow.modelData.host; color: peerRow.modelData.online ? Theme.green : Theme.muted; elide: Text.ElideRight }
                        Line { width: parent.width; text: peerRow.modelData.dns || peerRow.modelData.ip; color: Theme.fgDim; elide: Text.ElideRight }
                    }
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Tailnet.copy(peerRow.modelData.dns || peerRow.modelData.ip) }
                }
            }

            ActionButton {
                text: "Open admin panel"
                tone: "primary"
                onTriggered: Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin/machines"])
            }
        }
    }
}
