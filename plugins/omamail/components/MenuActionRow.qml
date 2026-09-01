import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  required property string text
  required property color textColor
  required property string panelFontFamily
  property color tone: textColor
  property var collection: []
  property int cursorIndex: -1
  readonly property bool selected: collection.indexOf(root) === cursorIndex

  signal activated()
  activeFocusOnTab: enabled
  Accessible.role: Accessible.MenuItem
  Accessible.name: root.text
  Accessible.focusable: enabled
  Accessible.onPressAction: if (enabled) root.activated()
  Keys.onPressed: function(event) {
    if (!enabled || event.isAutoRepeat) return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activated()
      event.accepted = true
    }
  }

  implicitHeight: Style.spacing.popupRowHeight
  radius: Style.cornerRadius
  opacity: enabled ? 1.0 : 0.4
  color: hover.hovered || selected || activeFocus
    ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.08)
    : "transparent"

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.text
    color: root.tone
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  HoverHandler { id: hover }
  TapHandler { onTapped: root.activated() }
}
