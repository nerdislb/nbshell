import QtQuick
import qs.Common

// Shared geometry for full-screen shell overlays. Most surfaces stay centered;
// bar extensions can opt into the same top-docked geometry without inventing
// another surface language.
MotionSurface {
    id: root

    property real preferredWidth: Theme.overlayWidthLarge
    property real preferredHeight: Theme.overlayHeightLarge
    property real edgeMarginX: Theme.overlayMarginX
    property real edgeMarginY: Theme.overlayMarginY
    property bool dockedTop: false
    property real dockOffset: Theme.barHeight + Theme.spaceSm

    width: Math.max(1, Math.min(preferredWidth, (parent?.width ?? preferredWidth) - edgeMarginX * 2))
    height: Math.max(1, Math.min(preferredHeight,
        (parent?.height ?? preferredHeight) - (dockedTop ? dockOffset + edgeMarginY : edgeMarginY * 2)))
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: dockedTop ? parent.top : undefined
    anchors.topMargin: dockedTop ? dockOffset : 0
    anchors.verticalCenter: dockedTop ? undefined : parent.verticalCenter
    accentBorder: true
}
