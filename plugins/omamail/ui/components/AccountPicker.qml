import QtQuick
import QtQuick.Controls as QQC
import qs.Commons

// Keep the mailbox selector local: nbshell's compatibility API has no Dropdown.
// Qt owns keyboard navigation, popup placement, dismissal and accessibility.
QQC.ComboBox {
  id: root

  required property var options
  required property string value
  required property color foreground
  required property color accent
  required property string fontFamily
  signal changed(string value)

  model: options
  textRole: "label"
  valueRole: "value"
  currentIndex: {
    for (var i = 0; i < options.length; i++)
      if (String(options[i].value) === value) return i
    return -1
  }
  onActivated: root.changed(String(currentValue))

  font.family: fontFamily
  font.pixelSize: Style.font.bodySmall
  implicitHeight: Style.spacing.controlHeight
  palette.text: foreground
  palette.buttonText: foreground
  palette.windowText: foreground
  palette.button: Style.normalFillFor(foreground, accent)
  palette.base: Style.normalFillFor(foreground, accent)
  palette.window: Style.normalFillFor(foreground, accent)
  palette.highlight: Style.selectedFillFor(foreground, accent)
  palette.highlightedText: Style.selectedStateColor(foreground, accent)

  contentItem: Text {
    text: root.displayText
    textFormat: Text.PlainText
    font: root.font
    color: root.foreground
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
  }
  delegate: QQC.ItemDelegate {
    required property int index
    required property var modelData
    width: root.width
    implicitHeight: Style.spacing.popupRowHeight
    highlighted: root.highlightedIndex === index
    font: root.font
    contentItem: Text {
      text: String(modelData.label || "")
      textFormat: Text.PlainText
      font: root.font
      color: root.foreground
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
  }
}
