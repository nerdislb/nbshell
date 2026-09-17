import QtQuick
import qs.Common
import qs.Widgets

InteractiveSurface {
    id: root
    property string label: ""
    property string iconSource: ""
    property string fallback: label.slice(0, 1).toUpperCase()
    property real glyphSize: Theme.controlHeight - Theme.spaceXs
    property bool running: false
    property bool selected: false
    readonly property bool hovered: hover.hovered
    signal contextRequested()
    accessibleName: label
    accessibleDescription: "Click to open; Menu key or right-click for app actions"
    accessibleSelected: selected
    accessiblePressed: tap.pressed
    implicitWidth: Theme.controlHeight + Theme.spaceXl
    implicitHeight: implicitWidth
    radius: Theme.radius
    color: Theme.controlFill(hovered || visualFocus, selected, tap.pressed)
    border.width: visualFocus ? Theme.borderWidth : 0
    border.color: Theme.focusBorder
    Image {
        id: appImage
        anchors.centerIn: parent
        width: root.glyphSize
        height: width
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
    }
    Line {
        anchors.centerIn: parent
        visible: appImage.status !== Image.Ready
        text: root.fallback
        font.pixelSize: Math.round(Theme.fontTitle * root.glyphSize / (Theme.controlHeight - Theme.spaceXs))
        color: root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spaceXs
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.selected ? Theme.spaceLg : Theme.spaceSm
        height: Theme.borderWidth * 2
        color: root.selected ? Theme.accent : Theme.fgDim
        visible: root.running
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (button === Qt.RightButton) root.contextRequested();
            else root.activate();
        }
    }
    Keys.onMenuPressed: root.contextRequested()
}
