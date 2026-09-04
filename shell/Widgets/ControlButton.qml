import QtQuick
import qs.Common

InteractiveSurface {
    id: root

    property string text: ""
    property bool selected: false
    property bool danger: false
    property color textColor: Theme.fg
    property color selectedTextColor: Theme.selectedForeground(Theme.accent)
    property Item pointerFocusTarget: null
    accessibleName: text
    accessibleSelected: selected
    accessiblePressed: tap.pressed

    implicitWidth: label.implicitWidth + Theme.spaceXl * 2
    implicitHeight: Theme.controlHeight
    radius: Theme.radius
    color: Theme.controlFill(hover.hovered || visualFocus, selected, tap.pressed)
    border.width: visualFocus ? Theme.borderWidth : Theme.controlBorderWidth(hover.hovered, selected, danger)
    border.color: visualFocus ? Theme.focusBorder : Theme.controlBorder(hover.hovered, selected, danger)
    opacity: enabled ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: Theme.motionFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.motionFast } }
    Behavior on opacity { NumberAnimation { duration: Theme.motionFast } }

    Line {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? Theme.readable(Theme.red, root.color, 4.5)
            : (root.selected ? root.selectedTextColor : root.textColor)
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
            if (root.pointerFocusTarget)
                root.pointerFocusTarget.forceActiveFocus(Qt.MouseFocusReason);
            else
                root.forceActiveFocus(Qt.MouseFocusReason);
            root.activate();
        }
    }
}
