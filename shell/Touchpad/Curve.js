// Editor gain controls are sampled as output velocities for libinput.
function defaults() { return { precision: 0.3, start: 0.8, end: 2.8, fast: 1.6 } }

function presetForScale(maximum) {
  var curve = defaults()
  var factor = Math.min(1, maximum / curve.fast)
  curve.precision = Math.max(0.01, Number((curve.precision * factor).toFixed(6)))
  curve.fast = Number((curve.fast * factor).toFixed(6))
  return curve
}

function copy(value) { return JSON.parse(JSON.stringify(value)) }

// Preserve the shape of saved three-handle curves when opening the new editor.
function normalize(curve) {
  if (curve.transition !== undefined)
    return { precision: curve.precision, start: 0, end: 2 * curve.transition, fast: curve.fast }
  return copy(curve)
}

function gain(curve, speed) {
  var t = Math.max(0, Math.min(1, (speed - curve.start) / (curve.end - curve.start)))
  return curve.precision + (curve.fast - curve.precision) * t * t * (3 - 2 * t)
}

function points(curve) {
  var out = []
  // Two samples beyond the visible 100% end keep extrapolation at constant gain.
  for (var i = 0; i <= 42; i++) out.push(Number((i * 0.1 * gain(curve, i * 0.1)).toFixed(6)))
  return out
}

// Draw the response that libinput actually interpolates, including its tail.
function sampledGain(curve, speed, samples) {
  var values = samples || points(curve)
  if (speed <= 0) return values[1] / 0.1
  var index = Math.min(values.length - 2, Math.floor(speed / 0.1))
  var fraction = speed / 0.1 - index
  return (values[index] + fraction * (values[index + 1] - values[index])) / speed
}

function adjust(curve, handle, value, precise, maximum) {
  var limit = maximum === undefined ? 10 : maximum
  var next = copy(curve)
  if (handle === 0) {
    next.precision = Math.max(0.01, Math.min(Math.max(limit, curve.precision), value))
    next.fast = Math.max(next.fast, next.precision)
  } else if (handle === 1) {
    var start = Math.max(0, Math.min(next.end - 0.2, value))
    next.start = Math.max(0, Math.min(next.end - 0.2, precise ? Math.round(start * 1000000) / 1000000 : Math.round(start * 20) / 20))
  } else if (handle === 2) {
    var end = Math.max(next.start + 0.2, Math.min(4, value))
    next.end = Math.max(next.start + 0.2, Math.min(4, precise ? Math.round(end * 1000000) / 1000000 : Math.round(end * 20) / 20))
  }
  else next.fast = Math.max(next.precision, Math.min(Math.max(limit, curve.fast), value))
  return next
}

function fromSettings(settings) {
  return {
    profile: settings.accel_profile === "custom" ? (settings.curve_preset || "custom") : settings.accel_profile,
    curve: normalize(settings.curve || defaults())
  }
}

if (typeof module !== "undefined") module.exports = { defaults, presetForScale, copy, normalize, gain, points, sampledGain, adjust, fromSettings }
