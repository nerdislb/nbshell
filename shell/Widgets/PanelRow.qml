import QtQuick
import qs.Common

InteractiveSurface {
    id: root

    property string title: ""
    property string detail: ""
    property string value: ""
    property string glyph: ""
    property bool selected: false
    property color tone: Theme.accent
    property real contentLeftPadding: root.glyph !== "" ? Theme.spaceLg : Theme.spaceXl

    interactive: false
    keyboardFocusable: interactive
    accessibleRole: interactive ? Accessible.Button : Accessible.StaticText
    accessibleName: title
    accessibleDescription: [detail, value].filter(part => part !== "").join("; ")
    accessibleSelected: selected
    accessiblePressed: tap.pressed

    implicitWidth: Theme.cellW * 36
    implicitHeight: Theme.rowHeight
    radius: Theme.radius
    color: selected ? Theme.selectedSurface(tone) : Theme.controlFill(hover.hovered || visualFocus, false, tap.pressed)
    border.width: visualFocus ? Theme.borderWidth : Theme.controlBorderWidth(hover.hovered, selected, false)
    border.color: visualFocus ? Theme.focusBorder : Theme.controlBorder(hover.hovered, selected, false)

    Line {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spaceLg
        anchors.verticalCenter: parent.verticalCenter
        visible: root.glyph !== ""
        text: root.glyph
        color: root.selected ? Theme.selectedForeground(root.tone) : Theme.fgDim
        font.pixelSize: Theme.fontTitle
    }

    Column {
        anchors.left: root.glyph !== "" ? icon.right : parent.left
        anchors.leftMargin: root.contentLeftPadding
        anchors.right: valueText.left
        anchors.rightMargin: Theme.spaceMd
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Line { width: parent.width; text: root.title; color: root.selected ? Theme.selectedForeground(root.tone) : Theme.fg; font.pixelSize: Theme.fontBody; elide: Text.ElideRight }
        Line { width: parent.width; visible: root.detail !== ""; text: root.detail; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
    }

    Line {
        id: valueText
        anchors.right: parent.right
        anchors.rightMargin: Theme.spaceXl
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.selected ? Theme.selectedForeground(root.tone) : Theme.fgDim
    }

    HoverHandler { id: hover; enabled: root.interactive && root.enabled; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        id: tap
        enabled: root.interactive && root.enabled
        onTapped: {
            root.forceActiveFocus();
            root.activate();
        }
    }
}
