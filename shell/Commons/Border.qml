pragma Singleton

import QtQuick
import qs.Common

QtObject {
  function none() { return { widths: { top: 0, right: 0, bottom: 0, left: 0 }, color: "transparent" } }
  function flat(color, width) {
    const w = Number(width === undefined ? Theme.borderWidth : width)
    return { widths: { top: w, right: w, bottom: w, left: w }, color: color }
  }
  function controlSpec(state, foreground, accent) {
    if (state === "normal") return flat(Theme.panelBorder, Theme.borderWidth)
    return flat(Theme.focusBorder, Theme.borderWidth)
  }
  function controlHasWidth(state) { return state !== "selected" }
  function localOrSurfaceSpec(surface, role, localColor, defaultColor, width) { return flat(localColor, width) }
  function top(spec) { return spec && spec.widths ? Number(spec.widths.top || 0) : 0 }
  function right(spec) { return spec && spec.widths ? Number(spec.widths.right || 0) : 0 }
  function bottom(spec) { return spec && spec.widths ? Number(spec.widths.bottom || 0) : 0 }
  function left(spec) { return spec && spec.widths ? Number(spec.widths.left || 0) : 0 }
  function color(spec) { return spec && spec.color !== undefined ? spec.color : "transparent" }
  function uniformWidth(spec) { return top(spec) }
  function canUseNative(spec) { return true }
  function needsOverlay(spec) { return false }
}
