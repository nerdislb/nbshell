import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool leftAlign: true
  property bool enabled: true
  property color foreground: Color.foreground
  property color paneColor: Color.background
  property color chromeColor: Style.normalFillFor(foreground, Color.accent)
  property Item chromeHost: null
  property Item joinTarget: null
  property real joinRadius: Math.max(Style.cornerRadius, Style.space(10))
  property real joinGutter: Style.space(12)

  signal clicked()

  readonly property Item joinLayer: chromeHost && chromeHost.parent
    ? chromeHost.parent : null

  width: parent ? parent.width : implicitWidth
  implicitWidth: labelRow.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Math.max(Style.space(32),
    labelRow.implicitHeight + Style.spacing.controlPaddingY * 2)
  height: implicitHeight
  z: selected ? 2 : 0

  Accessible.role: Accessible.Button
  Accessible.name: root.text || root.tooltipText
  Accessible.description: root.tooltipText
  Accessible.onPressAction: root.clicked()

  Rectangle {
    id: joinFill
    visible: root.selected
    color: root.paneColor
    x: Style.space(8)
    y: 0
    width: parent.width - x + Style.space(8)
    height: parent.height
    radius: root.joinRadius
    z: -1
  }

  Rectangle {
    id: joinBridge
    parent: root.selected && root.joinLayer ? root.joinLayer : root
    visible: root.selected && root.joinLayer
    color: root.paneColor
    z: 4
    height: root.height
    radius: root.joinRadius
    width: {
      var host = root.chromeHost
      var target = root.joinTarget
      var _ = root.x + root.y + (host ? host.x + host.width : 0)
        + (target ? target.x : 0)
      if (!visible || !host) return 1
      var origin = host.x + host.width - 2
      var endX = target ? target.x + root.joinGutter : origin + root.joinGutter
      return Math.max(2, Math.min(Style.space(22), endX - origin))
    }
    x: {
      var _ = root.x + (root.chromeHost ? root.chromeHost.x + root.chromeHost.width : 0)
      if (!visible || !root.chromeHost) return 0
      return root.chromeHost.x + root.chromeHost.width - 2
    }
    y: {
      var _ = root.x + root.y + root.height
        + (root.joinLayer ? root.joinLayer.height : 0)
      if (!visible || !joinBridge.parent) return 0
      return root.mapToItem(joinBridge.parent, 0, 0).y
    }
  }

  BorderSurface {
    id: idleFill
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    visible: !root.selected
    radius: root.joinRadius
    color: mouseArea.pressed ? Style.pressedFillFor(root.foreground, Color.accent)
      : mouseArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent)
      : "transparent"
    borderSpec: Border.none()
  }

  Row {
    id: labelRow
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign
      ? Style.spacing.controlPaddingX + Style.space(8) : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: Style.spacing.controlGap

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected
        ? Style.selectedStateColor(root.foreground, Color.accent)
        : root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.text !== ""
      text: root.text
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: root.selected
      elide: Text.ElideRight
      width: root.leftAlign
        ? Math.max(20, root.width - Style.spacing.controlPaddingX * 2
          - (root.iconText !== "" ? Style.font.icon + parent.spacing : 0))
        : implicitWidth
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
  }
}
