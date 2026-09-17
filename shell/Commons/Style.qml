pragma Singleton

import QtQuick
import qs.Common

QtObject {
  id: root

  readonly property real cornerRadius: Theme.radius
  readonly property real normalBorderWidth: Theme.borderWidth
  readonly property real hoverBorderWidth: Theme.borderWidth
  readonly property real focusBorderWidth: Theme.borderWidth
  readonly property real selectedBorderWidth: 0
  readonly property QtObject font: QtObject {
    readonly property string family: Theme.fontFamily
    readonly property real caption: Theme.fontCaption
    readonly property real bodySmall: Theme.fontSize
    readonly property real body: Theme.fontBody
    readonly property real subtitle: Theme.fontSubtitle
    readonly property real title: Theme.fontTitle
    readonly property real heading: Theme.fontHeading
    readonly property real display: Theme.fontDisplay
    readonly property real displayLarge: Theme.fontDisplay
    readonly property real iconSmall: Theme.fontSize
    readonly property real icon: Theme.fontBody
    readonly property real iconLarge: Theme.fontHeading
  }
  readonly property QtObject spacing: QtObject {
    readonly property real hairline: Theme.borderWidth
    readonly property real xxs: Math.max(1, Math.round(Theme.spaceXs * 0.66))
    readonly property real xs: Theme.spaceXs
    readonly property real sm: Theme.spaceSm
    readonly property real md: Theme.spaceMd
    readonly property real lg: Theme.spaceLg
    readonly property real xl: Theme.spaceXl
    readonly property real xxl: Math.round(Theme.spaceXl * 1.25)
    readonly property real xxxl: Math.round(Theme.spaceXl * 1.5)
    readonly property real huge: Math.round(Theme.spaceXl * 2)
    readonly property real labelGap: Theme.spaceSm
    readonly property real controlGap: Theme.spaceSm
    readonly property real controlHeight: Theme.controlHeight
    readonly property real controlPaddingX: Theme.spaceMd
    readonly property real controlPaddingY: Theme.spaceSm
    readonly property real inputPaddingY: Theme.spaceSm
    readonly property real popupRowHeight: Theme.rowHeight
    readonly property real rowGap: Theme.spaceMd
    readonly property real rowPaddingX: Theme.spaceLg
    readonly property real panelGap: Theme.spaceLg
    readonly property real panelPadding: Theme.panelPadding
    readonly property real popupPadding: Theme.panelPadding
    readonly property real dropdownWidth: Theme.cellW * 30
    readonly property real searchableDropdownWidth: Theme.cellW * 34
    readonly property real numberFieldWidth: Theme.cellW * 16
    readonly property real searchablePopupMinHeight: Theme.cellH * 14
  }
  readonly property QtObject motion: QtObject {
    readonly property int effects: Theme.motionEffectsDefault
    readonly property int attention: Theme.motionAttention
    readonly property int loopFast: Theme.motionLoopFast
    readonly property int loopSlow: Theme.motionLoopSlow
    readonly property bool reduced: Theme.reducedMotion
  }
  readonly property QtObject bar: QtObject {
    readonly property real iconCanvas: Theme.barIconCanvas
    readonly property real iconFont: Theme.fontBody
    readonly property real iconSlot: Theme.barIconSlot
    readonly property real statusSlot: Theme.barIconSlot
    readonly property real sizeHorizontal: Theme.barHeight
    readonly property real sizeVertical: Theme.barHeight
  }

  // Hälfte von Umbriels Aussenabstand, wie Omarchys Style.gapsOut die Hälfte
  // von Hyprlands general:gaps_out ist.
  readonly property real gapsOut: Config.gap

  // Zustandsalphas wie im Original. Die Farben bleiben nbshells Rollen
  // (Akzent für Auswahl und Fokus) — das ist eine bewusste Abweichung, siehe
  // docs/ui-porting.md.
  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.08
  readonly property real selectedFillAlpha: 0.18
  readonly property real pressedFillAlpha: 0.22
  readonly property real focusFillAlpha: hoverFillAlpha
  readonly property real selectionFillAlpha: 0.35
  readonly property real normalBorderAlpha: 0.4
  readonly property real hoverBorderAlpha: 0.25
  readonly property real selectedBorderAlpha: 1.0
  readonly property real focusBorderAlpha: hoverBorderAlpha

  function space(value) { return Math.round(Number(value) * Theme.uiScale) }
  function spaceReal(value) { return Number(value) * Theme.uiScale }
  function normalFillFor(foreground, accent) { return Theme.panelSurfaceRaised }
  function hoverFillFor(foreground, accent) { return Theme.hover }
  function focusFillFor(foreground, accent) { return Theme.hover }
  function selectedFillFor(foreground, accent) { return Theme.selectedSurface(accent) }
  function pressedFillFor(foreground, accent) { return Theme.mix(Theme.bg, accent, 0.26) }
  function selectionFillFor(foreground, accent) { return Theme.selectedSurface(accent) }
  function normalStateColor(foreground, accent, urgent) { return foreground ?? Color.foreground }
  function hoverStateColor(foreground, accent, urgent) { return foreground ?? Color.foreground }
  function focusStateColor(foreground, accent, urgent) { return accent ?? Color.accent }
  function selectedStateColor(foreground, accent, urgent) { return Theme.selectedForeground(accent) }
  function pressedStateColor(foreground, accent, urgent) { return accent ?? Color.accent }
  function selectionStateColor(foreground, accent, urgent) { return accent ?? Color.accent }
  function normalBorderFor(foreground, accent, urgent) {
    if (urgent) return Theme.alpha(Theme.red, 0.8)
    return Theme.panelBorder
  }
  function hoverBorderFor(foreground, accent, urgent) {
    if (urgent) return Theme.alpha(Theme.red, 0.8)
    return Theme.focusBorder
  }
  function focusBorderFor(foreground, accent, urgent) {
    if (urgent) return Theme.alpha(Theme.red, 0.8)
    return Theme.focusBorder
  }
  function selectedBorderFor(foreground, accent, urgent) {
    if (urgent) return Theme.alpha(Theme.red, 0.8)
    return "transparent"
  }

  // Upstream (qs.Commons) ruft diese Helfer mit Booleans und dem Fokus zuerst
  // auf:
  //   Style.controlFill(focused, hot, foreground, accent)
  //   Style.controlBorder(focused, hot, foreground, accent)
  //   Style.controlBorderWidth(focused, hot)
  // nbshell-eigene Bausteine rufen controlFill() stattdessen mit einem
  // Statusstring auf:
  //   Style.controlFill("focus" | "hover-cursor" | "selected" | "active"
  //                     | "pressed" | "normal", foreground, accent)
  // Beides muss funktionieren: ein portiertes Original darf unverändert
  // laufen, ein bestehender nbshell-Baustein darf nicht brechen. Über die
  // Argumentzahl sind die beiden Formen eindeutig unterscheidbar.
  function controlFill(stateOrFocused, hotOrForeground, foregroundOrAccent, accent) {
    if (arguments.length >= 4)
      return upstreamControlFill(stateOrFocused, hotOrForeground, foregroundOrAccent, accent)
    return stateFill(stateOrFocused, hotOrForeground, foregroundOrAccent)
  }

  function upstreamControlFill(focused, hot, foreground, accent) {
    if (focused) return focusFillFor(foreground, accent)
    if (hot) return hoverFillFor(foreground, accent)
    return normalFillFor(foreground, accent)
  }

  function stateFill(state, foreground, accent) {
    if (state === "pressed") return pressedFillFor(foreground, accent)
    if (state === "selected" || state === "active") return selectedFillFor(foreground, accent)
    if (state === "hover-cursor" || state === "focus") return hoverFillFor(foreground, accent)
    return normalFillFor(foreground, accent)
  }

  function controlBorder(focused, hot, foreground, accent, urgent) {
    if (focused) return focusBorderFor(foreground, accent, urgent)
    if (hot) return hoverBorderFor(foreground, accent, urgent)
    return normalBorderFor(foreground, accent, urgent)
  }

  function controlBorderWidth(focused, hot) {
    if (focused) return focusBorderWidth
    if (hot) return hoverBorderWidth
    return normalBorderWidth
  }

  function stateBorderFor(state, foreground, accent) {
    if (state === "selected" || state === "active") return selectedBorderFor(foreground, accent)
    if (state === "hover-cursor" || state === "focus") return focusBorderFor(foreground, accent)
    return normalBorderFor(foreground, accent)
  }
  function stateBorderWidth(state) {
    return state === "selected" || state === "active" ? selectedBorderWidth : normalBorderWidth
  }
}
