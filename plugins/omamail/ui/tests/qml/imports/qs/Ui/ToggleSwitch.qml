import QtQuick
import QtQuick.Controls

Switch {
  property string accessibleName: ""
  property bool busy: false
  property bool interactive: true
  property bool cursorRing: interactive
  property bool hasCursor: false
  implicitWidth: 52
  implicitHeight: 34
  property color foreground: "transparent"
  property color accent: "transparent"
}
