.pragma library

var SEARCH_TYPES = ["track", "artist", "album", "playlist"]
var MUTE_THRESHOLD = 0.001
var UNMUTE_FLOOR = 0.05

function clampUnit(value) {
  return Math.max(0, Math.min(1, Number(value) || 0))
}

function shallowCopy(value) {
  var copy = ({})
  if (!value || typeof value !== "object" || Array.isArray(value)) return copy
  for (var key in value) copy[key] = value[key]
  return copy
}

function assign(target, source) {
  var next = target && typeof target === "object" && !Array.isArray(target)
    ? target : ({})
  if (!source || typeof source !== "object" || Array.isArray(source)) return next
  for (var key in source) next[key] = source[key]
  return next
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed === null ? fallback : parsed
  } catch (e) {
    return fallback
  }
}

function barTrackText(title, artist, showTitle, showArtist) {
  var cleanTitle = String(title || "").trim()
  var cleanArtist = String(artist || "").trim()
  var parts = []
  if (showArtist && cleanArtist) parts.push(cleanArtist)
  if (showTitle && cleanTitle) parts.push(cleanTitle)
  return parts.join(" - ")
}

function canScrollBarText(showTitle, showArtist) {
  return showTitle === true || showArtist === true
}

function normalizedScrollSpeed(value) {
  var speed = Number(value)
  if (!isFinite(speed)) speed = 1
  return Math.round(Math.max(0.25, Math.min(3, speed)) * 4) / 4
}

function normalizedShortcutPlayer(value) {
  var text = String(value || "")
  if (text === "Mini player") return "Mini player"
  return "Full player"
}

function repeatModeLabel(mode) {
  var value = String(mode || "off")
  if (value === "track") return "This song"
  if (value === "context") return "All"
  return "Off"
}

function nextVolume(current, delta) {
  return clampUnit((Number(current) || 0) + (Number(delta) || 0))
}

function shouldRememberVolume(value) {
  return clampUnit(value) > MUTE_THRESHOLD
}

function unmuteVolume(previous) {
  return Math.max(UNMUTE_FLOOR, Number(previous) || 0)
}

function seekPosition(position, delta, length) {
  var next = Math.max(0, (Number(position) || 0) + (Number(delta) || 0))
  var maximum = Math.max(0, Number(length) || 0)
  return maximum > 0 ? Math.min(maximum, next) : next
}

function arrayValues(values) {
  if (Array.isArray(values)) return values
  if (!values || typeof values === "string") return []
  var length = Number(values.length)
  if (!isFinite(length) || length <= 0) return []
  var result = []
  for (var i = 0; i < Math.floor(length); i++) result.push(values[i])
  return result
}

function parseStringList(value, maximum) {
  var source = value
  if (typeof source === "string") source = parseJson(source, [])
  if (!Array.isArray(source)) return []
  var limit = Math.max(1, Number(maximum) || 50)
  var result = []
  for (var i = 0; i < source.length && result.length < limit; i++) {
    var item = String(source[i] || "").trim()
    if (item && result.indexOf(item) < 0) result.push(item)
  }
  return result
}

function touchHistory(history, term, maximum) {
  var next = parseStringList(history, maximum)
  var value = String(term || "").trim()
  if (!value) return next
  var existing = next.indexOf(value)
  if (existing >= 0) next.splice(existing, 1)
  next.unshift(value)
  return next.slice(0, Math.max(1, Number(maximum) || 12))
}

function touchBoundedOrder(order, key, limit) {
  if (!Array.isArray(order)) return ""
  var name = String(key || "")
  if (!name) return ""
  var maximum = Math.max(0, Math.floor(Number(limit) || 0))
  var oldIndex = order.indexOf(name)
  if (oldIndex >= 0) order.splice(oldIndex, 1)
  order.push(name)
  return order.length > maximum ? String(order.shift() || "") : ""
}

function redact(value) {
  var text = String(value || "")
  text = text.replace(/(cookie\s*[:=]\s*)[^\s;]+/ig, "$1<redacted>")
  text = text.replace(/(authorization\s*:\s*)[^\s]+/ig, "$1<redacted>")
  text = text.replace(/(SAPISIDHASH\s+)[^\s]+/ig, "$1<redacted>")
  return text
}

function millisecondsToClock(milliseconds) {
  var seconds = Math.max(0, Math.floor((Number(milliseconds) || 0) / 1000))
  var minutes = Math.floor(seconds / 60)
  var remainder = seconds % 60
  if (minutes >= 60) {
    var hours = Math.floor(minutes / 60)
    minutes = minutes % 60
    return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":"
      + (remainder < 10 ? "0" : "") + remainder
  }
  return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
}

function playbackSliderFeedbackComplete(sourceValue, pendingValue, sourcePending,
    elapsedMs, tolerance, minimumMs, timeoutMs) {
  var elapsed = Math.max(0, Number(elapsedMs) || 0)
  var timeout = Math.max(1, Number(timeoutMs) || 1)
  if (elapsed >= timeout) return true
  var minimum = Math.max(0, Number(minimumMs) || 0)
  var difference = Math.abs((Number(sourceValue) || 0)
    - (Number(pendingValue) || 0))
  return elapsed >= minimum && sourcePending !== true
    && difference <= Math.max(0, Number(tolerance) || 0)
}

function mediaRowShouldCompact(titleWidth, availableWidth, actionCount) {
  var title = Math.max(0, Number(titleWidth) || 0)
  var available = Math.max(0, Number(availableWidth) || 0)
  var actions = Math.max(0, Math.floor(Number(actionCount) || 0))
  return actions > 0 && title > available
}

function lyricsSong(trackId, title, artist, album, duration, coverUrl,
    positionSeconds) {
  var id = String(trackId || "").trim()
  var songTitle = String(title || "").trim()
  var songArtist = String(artist || "").trim()
  if (!id || !songTitle || !songArtist) return null
  var songDuration = Math.max(0, Number(duration) || 0)
  var songPosition = Math.max(0, Number(positionSeconds) || 0)
  if (songDuration > 0) songPosition = Math.min(songPosition, songDuration)
  return {
    id: id.indexOf("ytm:") === 0 ? id : "ytm:track:" + id,
    title: songTitle,
    artist: songArtist,
    album: String(album || "").trim(),
    duration: songDuration,
    coverUrl: String(coverUrl || "").trim(),
    positionSeconds: songPosition
  }
}

function optionalPluginState(installed, enabled) {
  if (installed !== true) return "missing"
  return enabled === true ? "ready" : "disabled"
}

function optionalPluginSetupCommand(state, pluginId, repositoryUrl) {
  var availability = String(state || "")
  var id = String(pluginId || "").trim()
  var url = String(repositoryUrl || "").trim()
  if (availability === "missing" && url)
    return ["omarchy", "plugin", "add", url, "--enable", "--yes"]
  if (availability === "disabled" && id)
    return ["omarchy", "plugin", "enable", id, "--section", "center"]
  return []
}

function isUtilityTab(tab) {
  var area = String(tab || "")
  return area === "setup" || area === "login"
}

function rememberContentTab(tab) {
  var area = String(tab || "")
  return !area || isUtilityTab(area) ? "" : area
}

function previousContentTab(tab, lastContentTab) {
  if (!isUtilityTab(tab)) return ""
  var previous = String(lastContentTab || "home")
  return isUtilityTab(previous) ? "home" : previous
}

function searchScope(tab, detailItem, selectedPlaylist, homeType, libraryType) {
  var area = String(tab || "")
  if (area === "detail" && detailItem)
    return { available: true, label: String(detailItem.name || "this page") }
  if (area === "playlists" && selectedPlaylist)
    return { available: true, label: String(selectedPlaylist.name || "playlist") }
  if (area === "library")
    return { available: true, label: String(libraryType || "library") }
  if (area === "home")
    return { available: true, label: "home" }
  if (area === "queue")
    return { available: true, label: "queue" }
  return { available: false, label: "" }
}

function universalSearchVisible(tab, active) {
  var area = String(tab || "")
  return area === "search" || (active === true && !isUtilityTab(area))
}

function filteredSorted(items, filterText, sortKey) {
  var source = Array.isArray(items) ? items : []
  var term = String(filterText || "").trim().toLowerCase()
  var key = String(sortKey || "default")
  if (!term && key === "default") {
    var complete = true
    for (var candidate = 0; candidate < source.length; candidate++) {
      if (!source[candidate]) {
        complete = false
        break
      }
    }
    if (complete) return source
  }

  var rows = []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    if (!item) continue
    if (term) {
      var haystack = [item.name, item.subtitle, item.album, item.description]
        .join(" ").toLowerCase()
      if (haystack.indexOf(term) < 0) continue
    }
    rows.push({ item: item, index: i })
  }
  if (key !== "default") {
    rows.sort(function(a, b) {
      var left
      var right
      if (key === "duration") {
        left = Number(a.item.durationMs) || 0
        right = Number(b.item.durationMs) || 0
      } else {
        left = String(key === "artist" ? a.item.subtitle
          : (key === "album" ? a.item.album : a.item.name) || "").toLowerCase()
        right = String(key === "artist" ? b.item.subtitle
          : (key === "album" ? b.item.album : b.item.name) || "").toLowerCase()
      }
      if (left < right) return -1
      if (left > right) return 1
      return a.index - b.index
    })
  }
  var result = []
  for (var r = 0; r < rows.length; r++) result.push(rows[r].item)
  return result
}

function qualityKbps(label) {
  var value = String(label || "")
  if (value.indexOf("96") === 0) return 96
  if (value.indexOf("160") === 0) return 160
  return 320
}

function qualityLabel(kbps) {
  if (Number(kbps) <= 96) return "96 kbps"
  if (Number(kbps) <= 160) return "160 kbps"
  return "320 kbps"
}

function typeLabel(type, plural) {
  var labels = {
    track: { singular: "Song", plural: "Songs" },
    artist: { singular: "Artist", plural: "Artists" },
    album: { singular: "Album", plural: "Albums" },
    playlist: { singular: "Playlist", plural: "Playlists" }
  }
  var entry = labels[String(type || "")]
  if (!entry) return plural ? "results" : "item"
  return plural ? entry.plural : entry.singular
}

function videoIdOf(item) {
  if (!item) return ""
  return String(item.videoId || (item.type === "track" ? item.id : "") || "")
}

function artistSubtitleSuffix() {
  return ""
}
