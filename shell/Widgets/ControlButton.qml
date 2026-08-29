import QtQuick
import qs.Common

InteractiveSurface {
    id: root

    property string text: ""
    property bool selected: false
    property bool danger: false
    accessibleName: text
    accessibleSelected: selected
    accessiblePressed: tap.pressed

    implicitWidth: label.implicitWidth + Theme.spaceXl * 2
    implicitHeight: Theme.controlHeight
    radius: Theme.radius
    color: Theme.controlFill(hover.hovered || activeFocus, selected, tap.pressed)
    border.width: activeFocus ? Theme.borderWidth : Theme.controlBorderWidth(hover.hovered, selected, danger)
    border.color: activeFocus ? Theme.focusBorder : Theme.controlBorder(hover.hovered, selected, danger)
    opacity: enabled ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: Theme.motionFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.motionFast } }
    Behavior on opacity { NumberAnimation { duration: Theme.motionFast } }

    Line {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? Theme.readable(Theme.red, root.color, 4.5)
            : (root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg)
        font.pixelSize: Theme.fontBody
    }

    HoverHandler {
        id: hover
        enabled: root.interactive && root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: tap
        enabled: root.interactive && root.enabled
        onTapped: {
            root.forceActiveFocus();
            root.activate();
        }
    }
}
