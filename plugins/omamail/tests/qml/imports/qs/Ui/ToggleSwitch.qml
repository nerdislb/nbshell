import QtQuick

Item {
  property string accessibleName: ""
  property bool checked: false
  property bool busy: false
  property color foreground: "transparent"
  property color accent: "transparent"
  signal toggled()
}
