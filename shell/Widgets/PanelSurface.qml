import QtQuick
import qs.Common

Rectangle {
    id: root

    property bool raised: false
    property bool accentBorder: false

    color: raised ? Theme.panelSurfaceRaised : Theme.panelSurface
    radius: Theme.radius
    border.width: Theme.borderWidth
    border.color: accentBorder ? Theme.focusBorder : Theme.panelBorder
}
