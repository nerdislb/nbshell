pragma Singleton
import QtQuick

QtObject {
  readonly property color background: Qt.rgba(0.1, 0.1, 0.1, 1)
  readonly property color urgent: Qt.rgba(1, 0, 0, 1)
  readonly property var popups: ({background: Qt.rgba(0.1, 0.1, 0.1, 1), border: Qt.rgba(0.5, 0.5, 0.5, 0.5)})
  readonly property color foreground: Qt.rgba(1, 1, 1, 1)
  readonly property color accent: Qt.rgba(1, 0.5, 0, 1)
}
