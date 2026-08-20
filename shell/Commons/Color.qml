pragma Singleton

import QtQuick
import qs.Common

QtObject {
  readonly property color foreground: Theme.fg
  readonly property color background: Theme.panelSurface
  readonly property color accent: Theme.accent
  readonly property color urgent: Theme.red
  readonly property QtObject popups: QtObject {
    readonly property color background: Theme.panelSurface
    readonly property color border: Theme.panelBorder
  }
  readonly property QtObject tooltip: QtObject {
    readonly property color text: Theme.fg
    readonly property color background: Theme.panelSurfaceRaised
    readonly property color border: Theme.panelBorder
  }
}
