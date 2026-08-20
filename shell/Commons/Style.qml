pragma Singleton

import QtQuick
import qs.Common

QtObject {
  id: root

  readonly property real cornerRadius: Theme.radius
  readonly property real normalBorderWidth: Theme.borderWidth
  readonly property QtObject font: QtObject {
    readonly property string family: Theme.fontFamily
    readonly property real caption: Theme.fontCaption
    readonly property real bodySmall: Theme.fontSize
    readonly property real body: Theme.fontBody
    readonly property real subtitle: Theme.fontSubtitle
    readonly property real title: Theme.fontTitle
    readonly property real heading: Theme.fontHeading
    readonly property real displayLarge: Theme.fontDisplay
    readonly property real iconSmall: Theme.fontSize
    readonly property real icon: Theme.fontBody
    readonly property real iconLarge: Theme.fontHeading
  }
  readonly property QtObject spacing: QtObject {
    readonly property real xs: Theme.spaceXs
    readonly property real sm: Theme.spaceSm
    readonly property real md: Theme.spaceMd
    readonly property real lg: Theme.spaceLg
    readonly property real xl: Theme.spaceXl
    readonly property real labelGap: Theme.spaceSm
    readonly property real controlGap: Theme.spaceSm
    readonly property real controlHeight: Theme.controlHeight
    readonly property real controlPaddingX: Theme.spaceMd
    readonly property real controlPaddingY: Theme.spaceSm
    readonly property real inputPaddingY: Theme.spaceSm
    readonly property real popupRowHeight: Theme.rowHeight
  }
  readonly property QtObject bar: QtObject {
    readonly property real iconCanvas: Theme.barIconCanvas
    readonly property real iconFont: Theme.fontBody
    readonly property real iconSlot: Theme.barIconSlot
    readonly property real statusSlot: Theme.barIconSlot
    readonly property real sizeHorizontal: Theme.barHeight
  }

  function space(value) { return Math.round(Number(value) * Theme.uiScale) }
  function normalFillFor(foreground, accent) { return Theme.panelSurfaceRaised }
  function hoverFillFor(foreground, accent) { return Theme.hover }
  function focusFillFor(foreground, accent) { return Theme.hover }
  function selectedFillFor(foreground, accent) { return Theme.selectedSurface(accent) }
  function pressedFillFor(foreground, accent) { return Theme.mix(Theme.bg, accent, 0.26) }
  function selectionFillFor(foreground, accent) { return Theme.selectedSurface(accent) }
  function selectedStateColor(foreground, accent) { return Theme.selectedForeground(accent) }
  function normalBorderFor(foreground, accent) { return Theme.panelBorder }
  function hoverBorderFor(foreground, accent) { return Theme.focusBorder }
  function controlFill(state, foreground, accent) {
    if (state === "pressed") return pressedFillFor(foreground, accent)
    if (state === "selected" || state === "active") return selectedFillFor(foreground, accent)
    if (state === "hover-cursor" || state === "focus") return hoverFillFor(foreground, accent)
    return normalFillFor(foreground, accent)
  }
}
