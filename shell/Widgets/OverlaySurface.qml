import QtQuick
import qs.Common

// Shared geometry for centered, full-screen shell overlays. Callers still
// choose their useful content size, but edge safety, centering, surface role,
// and border language no longer drift from window to window.
MotionSurface {
    id: root

    property real preferredWidth: Theme.overlayWidthLarge
    property real preferredHeight: Theme.overlayHeightLarge
    property real edgeMarginX: Theme.overlayMarginX
    property real edgeMarginY: Theme.overlayMarginY

    width: Math.max(1, Math.min(preferredWidth, (parent?.width ?? preferredWidth) - edgeMarginX * 2))
    height: Math.max(1, Math.min(preferredHeight, (parent?.height ?? preferredHeight) - edgeMarginY * 2))
    anchors.centerIn: parent
    accentBorder: true
}
