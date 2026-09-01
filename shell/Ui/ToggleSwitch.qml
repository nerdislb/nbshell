import QtQuick
import QtQuick.Controls
import qs.Commons

// Theme-adapted Qt switch for portable qs.Ui plugins.
Switch {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property bool busy: false
  property string accessibleName: ""

  enabled: !busy
  implicitWidth: Style.space(34)
  implicitHeight: Style.space(18)
  padding: 0
  Accessible.name: accessibleName !== "" ? accessibleName : "Toggle"
  opacity: enabled ? 1 : 0.55

  indicator: BorderSurface {
    x: 0
    y: Math.round((root.height - height) / 2)
    width: root.implicitWidth
    height: root.implicitHeight
    radius: height / 2
    color: Style.controlFill(root.checked ? "selected" : (root.activeFocus ? "focus" : "normal"), root.foreground, root.accent)
    borderSpec: Border.controlSpec(root.activeFocus ? "focus" : "normal", root.foreground, root.accent)

    Rectangle {
      width: parent.height - Style.space(4)
      height: width
      radius: width / 2
      y: Style.space(2)
      x: root.checked ? parent.width - width - Style.space(2) : Style.space(2)
      color: root.checked ? root.accent : root.foreground
    }
  }

  contentItem: Item {}
}
