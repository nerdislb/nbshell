import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool enabled: true
  property bool hasCursor: false
  property color foreground: Color.foreground
  property real iconSize: Style.font.icon
  property real chickletSize: Style.space(32)

  signal clicked()
  signal hovered(bool isHovered)

  readonly property bool hot: mouseArea.containsMouse || root.hasCursor
  readonly property color pillBorder: root.hot || root.selected
    ? Style.hoverBorderFor(root.foreground, Color.accent)
    : Style.normalBorderFor(root.foreground, Color.accent)

  implicitWidth: chickletSize
  implicitHeight: chickletSize
  width: chickletSize
  height: chickletSize

  Accessible.role: Accessible.Button
  Accessible.name: root.tooltipText
  Accessible.description: root.tooltipText
  Accessible.onPressAction: if (root.enabled) root.clicked()

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: mouseArea.pressed && root.enabled
      ? Style.pressedFillFor(root.foreground, Color.accent)
      : (root.selected
        ? Style.selectedFillFor(root.foreground, Color.accent)
        : (root.hot && root.enabled
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : Qt.rgba(0, 0, 0, 0)))
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: root.pillBorder
    opacity: root.enabled ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
  }

  Text {
    anchors.centerIn: parent
    text: root.iconText
    color: root.selected
      ? Style.selectedStateColor(root.foreground, Color.accent)
      : root.foreground
    font.family: Style.font.family
    font.pixelSize: root.iconSize
    opacity: root.enabled ? 1 : 0.45
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
    onContainsMouseChanged: root.hovered(containsMouse)
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && root.hot
    text: root.tooltipText
  }
}
