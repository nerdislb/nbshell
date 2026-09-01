pragma Singleton
import QtQuick

QtObject {
  readonly property real cornerRadius: 2
  readonly property real normalBorderWidth: 1
  readonly property var font: ({
    family: "monospace", title: 22, subtitle: 16, heading: 18, body: 14, bodySmall: 13, caption: 11,
    icon: 16, iconSmall: 14
  })
  readonly property var spacing: ({
    controlPaddingX: 8, controlPaddingY: 5, inputPaddingY: 5,
    controlHeight: 30, controlGap: 6, sm: 3, md: 6
  })
  readonly property var motion: ({ attention: 0, loopFast: 1, loopSlow: 1, reduced: true })

  function space(value) { return Number(value) }
  function hoverFillFor(_foreground, accent) { return accent }
  function selectedFillFor(_foreground, accent) { return accent }
  function selectionFillFor(_foreground, accent) { return accent }
  function pressedFillFor(_foreground, accent) { return accent }
  function normalFillFor(_foreground, _accent) { return "transparent" }
  function normalBorderFor(foreground, _accent) { return foreground }
  function hoverBorderFor(_foreground, accent) { return accent }
}
