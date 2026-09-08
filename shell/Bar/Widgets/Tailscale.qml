import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    shown: Tailnet.available
    readonly property bool connected: Tailnet.state === "Running"
    readonly property bool needsAttention: Tailnet.state === "NeedsLogin" || Tailnet.state === "NeedsMachineAuth"
    readonly property string stateDescription: connected ? "connected"
        : Tailnet.state === "NeedsLogin" ? "sign-in required"
        : Tailnet.state === "NeedsMachineAuth" ? "device approval required"
        : Tailnet.state === "Starting" ? "starting"
        : "disconnected"

    interactive: true
    label: "VPN"
    // Cell uses this nonempty marker for its icon/text display contract.
    // The native dot mark below supplies the actual icon.
    icon: "tailscale"
    custom: true
    color: connected ? Theme.barFg : (needsAttention ? Theme.yellow : Theme.fgDim)
    accessibilityName: "Tailscale, " + stateDescription
        + ", " + Tailnet.onlinePeers + " online devices"

    Item {
        width: root.wantIcon ? Theme.barIconSlot : fallback.implicitWidth
        height: Theme.cellH

        Item {
            id: mark
            anchors.centerIn: parent
            visible: root.wantIcon
            width: Theme.barIconHeight
            height: width
            // Ratios describe the brand's nine-dot silhouette, not UI spacing.
            readonly property real dotSize: width * 0.24

            Repeater {
                model: 9
                Rectangle {
                    required property int index
                    width: mark.dotSize
                    height: width
                    radius: width / 2
                    x: (index % 3) * (mark.width - width) / 2
                    y: Math.floor(index / 3) * (mark.height - height) / 2
                    color: root.shownColor
                    opacity: (index >= 3 && index <= 5) || index === 7 ? 1 : 0.24
                }
            }

            Rectangle {
                visible: !root.connected && !root.needsAttention
                anchors.centerIn: parent
                width: parent.width * 1.22
                height: Theme.borderWidth * 2
                radius: height / 2
                rotation: -45
                color: root.shownColor
            }

            Rectangle {
                visible: root.needsAttention
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.6
                height: width
                radius: width / 2
                color: root.shownColor
                Line {
                    anchors.centerIn: parent
                    text: "!"
                    font.pixelSize: parent.height * 0.85
                    font.bold: true
                    color: Theme.on(root.shownColor)
                }
            }
        }

        Line {
            id: fallback
            anchors.centerIn: parent
            visible: !root.wantIcon
            text: root.shownText
            color: root.shownColor
        }
    }

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
