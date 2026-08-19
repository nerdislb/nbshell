import QtQuick
import qs.Common

Rectangle {
    id: root

    property string text: ""
    property bool selected: false
    property bool danger: false
    signal triggered()

    implicitWidth: label.implicitWidth + Theme.spaceXl * 2
    implicitHeight: Theme.controlHeight
    radius: Theme.radius
    color: Theme.controlFill(hover.hovered, selected, tap.pressed)
    border.width: Theme.controlBorderWidth(hover.hovered, selected, danger)
    border.color: Theme.controlBorder(hover.hovered, selected, danger)
    opacity: enabled ? 1 : 0.45

    Line {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? Theme.readable(Theme.red, root.color, 4.5)
            : (root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg)
        font.pixelSize: Theme.fontBody
    }

    HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: root.enabled; onTapped: root.triggered() }
}
