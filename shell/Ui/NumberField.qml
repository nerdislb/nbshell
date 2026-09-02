import QtQuick
import QtQuick.Controls
import qs.Commons

// Theme-adapted numeric field for portable qs.Ui plugins.
SpinBox {
  id: root

  property string label: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  signal modified(real next)

  editable: false
  implicitWidth: Style.space(126)
  implicitHeight: Style.space(30)
  font.family: fontFamily
  font.pixelSize: fontSize
  Accessible.name: label
  onValueModified: modified(value)

  // Intentional internal display item: NumberField is a read-only SpinBox, not
  // a free-text input. Accessibility remains owned by the SpinBox root.
  contentItem: TextInput {
    text: root.textFromValue(root.value, root.locale)
    color: root.foreground
    font: root.font
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    readOnly: true
    selectByMouse: false
    Accessible.ignored: true
  }

  background: BorderSurface {
    color: Style.controlFill(root.activeFocus ? "focus" : "normal", root.foreground, root.accent)
    borderSpec: Border.controlSpec(root.activeFocus ? "focus" : "normal", root.foreground, root.accent)
    radius: Style.cornerRadius
  }

  up.indicator: Text {
    x: root.width - width - Style.space(8)
    height: root.height
    text: "+"
    color: root.up.pressed ? root.accent : root.foreground
    font: root.font
    verticalAlignment: Text.AlignVCenter
  }

  down.indicator: Text {
    x: Style.space(8)
    height: root.height
    text: "−"
    color: root.down.pressed ? root.accent : root.foreground
    font: root.font
    verticalAlignment: Text.AlignVCenter
  }
}
