// Pit Wall data layer: pure parse/format functions over the jolpica (Ergast)
// schedule + standings responses and the openf1 live-session feeds. No QML
// or network access here — the same file loads in Quickshell (via
// `import "Model.js" as Model`) and in node for the unit suite.

// Estimated session lengths, used only to decide when the pill should flip
// into live mode and start polling openf1. openf1's own date_start/date_end
// take over as the authority once a live session row exists.
var SESSION_DURATION_MS = {
  fp1: 60 * 60000,
  fp2: 60 * 60000,
  fp3: 60 * 60000,
  sprintQualifying: 45 * 60000,
  sprint: 60 * 60000,
  qualifying: 60 * 60000,
  race: 180 * 60000
}

var SESSION_LABELS = {
  fp1: "Practice 1",
  fp2: "Practice 2",
  fp3: "Practice 3",
  sprintQualifying: "Sprint Qualifying",
  sprint: "Sprint",
  qualifying: "Qualifying",
  race: "Race"
}

var SESSION_SHORT = {
  fp1: "FP1",
  fp2: "FP2",
  fp3: "FP3",
  sprintQualifying: "SQ",
  sprint: "SPRINT",
  qualifying: "QUALI",
  race: "RACE"
}

// Sanitize every string that comes from the APIs before it reaches a QML
// Text. Two reasons: (1) a first-party bar label renders as Qt AutoText,
// which promotes an HTML-looking string to StyledText — an `<img src=...>`
// in a driver/team name would make the shell process fetch a URL, and an
// oversized width= would blow out the bar; stripping angle brackets defuses
// both. (2) A pathologically long field is a layout-cost problem, so cap it.
function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[<>]/g, "").replace(/[\x00-\x1f\x7f]/g, "")
  var cap = max || 64
  return s.length > cap ? s.slice(0, cap) : s
}

function sessionStartMs(entry) {
  if (!entry || !entry.date) return NaN
  var time = entry.time || "00:00:00Z"
  return Date.parse(entry.date + "T" + time)
}

function pushSession(sessions, kind, entry) {
  var startMs = sessionStartMs(entry)
  if (isNaN(startMs)) return
  sessions.push({
    kind: kind,
    label: SESSION_LABELS[kind],
    short: SESSION_SHORT[kind],
    startMs: startMs,
    endMs: startMs + SESSION_DURATION_MS[kind]
  })
}

// jolpica /current.json -> { season, races: [...] }. Races keep their
// sessions sorted by start time; a race with no parseable sessions is
// dropped rather than surfaced as an empty weekend.
function parseSchedule(raw) {
  var empty = { season: "", races: [] }
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return empty }
  var table = data && data.MRData && data.MRData.RaceTable
  if (!table || !table.Races || !table.Races.length) return empty

  var races = []
  for (var i = 0; i < table.Races.length; i++) {
    var r = table.Races[i]
    var sessions = []
    pushSession(sessions, "fp1", r.FirstPractice)
    pushSession(sessions, "fp2", r.SecondPractice)
    pushSession(sessions, "fp3", r.ThirdPractice)
    pushSession(sessions, "sprintQualifying", r.SprintQualifying)
    pushSession(sessions, "sprint", r.Sprint)
    pushSession(sessions, "qualifying", r.Qualifying)
    pushSession(sessions, "race", { date: r.date, time: r.time })
    if (!sessions.length) continue
    sessions.sort(function(a, b) { return a.startMs - b.startMs })
    races.push({
      round: parseInt(r.round, 10) || 0,
      name: clean(r.raceName, 48),
      circuit: clean(r.Circuit ? r.Circuit.circuitName : "", 48),
      locality: r.Circuit && r.Circuit.Location ? (r.Circuit.Location.locality || "") : "",
      country: r.Circuit && r.Circuit.Location ? (r.Circuit.Location.country || "") : "",
      sessions: sessions
    })
  }
  races.sort(function(a, b) { return a.round - b.round })
  return { season: table.season || "", races: races }
}

// The bar's one question: what matters right now? Returns
//   { status: "live",  race, session }             during a session window
//   { status: "next",  race, session, msUntil }    between sessions
//   { status: "off" }                              season over / no data
function currentOrNext(races, nowMs) {
  var next = null
  var nextRace = null
  for (var i = 0; i < races.length; i++) {
    var sessions = races[i].sessions
    for (var j = 0; j < sessions.length; j++) {
      var s = sessions[j]
      if (nowMs >= s.startMs && nowMs < s.endMs)
        return { status: "live", race: races[i], session: s }
      if (s.startMs > nowMs && (!next || s.startMs < next.startMs)) {
        next = s
        nextRace = races[i]
      }
    }
  }
  if (!next) return { status: "off" }
  return { status: "next", race: nextRace, session: next, msUntil: next.startMs - nowMs }
}

// Compact countdown: keeps the two most significant units so the pill stays
// narrow. "2d 4h" -> "1h 05m" -> "14m" -> "now".
function countdown(msUntil) {
  if (msUntil <= 30000) return "now"
  var totalMinutes = Math.round(msUntil / 60000)
  var days = Math.floor(totalMinutes / 1440)
  var hours = Math.floor((totalMinutes % 1440) / 60)
  var minutes = totalMinutes % 60
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
  // Zero-pad the bare-minutes branch too, so the pill keeps a constant width
  // as the countdown ticks under ten minutes (54m -> 09m, not 54m -> 9m).
  return (minutes < 10 ? "0" : "") + minutes + "m"
}

// Bar pill text. Countdown mode: "QUALI 2h 14m". Live mode with a known
// leader: "RACE ▸ VER"; an abnormal track status outranks the leader:
// "RACE ▸ SC". Live with neither yet: "RACE ▸ LIVE".
function pillText(state, leaderAcronym, trackTag) {
  if (!state || state.status === "off") return ""
  if (state.status === "live")
    return state.session.short + " ▸ " + (trackTag || leaderAcronym || "LIVE")
  return state.session.short + " " + countdown(state.msUntil)
}

// jolpica standings -> [{pos, name, code, points, wins}]. kind is
// "DriverStandings" or "ConstructorStandings"; both live at the same path.
function parseStandings(raw, kind) {
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return [] }
  var lists = data && data.MRData && data.MRData.StandingsTable && data.MRData.StandingsTable.StandingsLists
  if (!lists || !lists.length) return []
  var rows = lists[0][kind]
  if (!rows) return []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var entry = {
      pos: parseInt(row.position, 10) || (i + 1),
      points: clean(row.points || "0", 6),
      wins: parseInt(row.wins, 10) || 0
    }
    if (row.Driver) {
      entry.name = clean(row.Driver.familyName || row.Driver.driverId, 32)
      entry.code = clean(row.Driver.code, 6)
      entry.team = clean(row.Constructors && row.Constructors[0] ? row.Constructors[0].name : "", 32)
    } else if (row.Constructor) {
      entry.name = clean(row.Constructor.name || row.Constructor.constructorId, 32)
      entry.code = ""
      entry.team = ""
    } else {
      continue
    }
    out.push(entry)
  }
  return out
}

// openf1 /drivers -> { "1": {acronym, team, name}, ... } keyed by
// driver_number as a string so QML property lookups stay simple.
function parseDrivers(raw) {
  var rows
  try { rows = JSON.parse(String(raw || "")) } catch (e) { return {} }
  if (!rows || !rows.length) return {}
  var map = {}
  for (var i = 0; i < rows.length; i++) {
    var d = rows[i]
    if (d.driver_number === undefined || d.driver_number === null) continue
    map[String(d.driver_number)] = {
      acronym: clean(d.name_acronym || ("#" + d.driver_number), 6),
      team: clean(d.team_name, 32),
      name: d.full_name || d.broadcast_name || ""
    }
  }
  return map
}

// openf1 emits an append-only event stream; the current state per driver is
// the latest row by date. Works for /position and /intervals alike.
function latestByDriver(rows) {
  var latest = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var key = String(row.driver_number)
    if (!latest[key] || String(row.date) > String(latest[key].date)) latest[key] = row
  }
  return latest
}

// Fold a fresh batch of openf1 events into an accumulated per-driver state
// map. Live polling fetches only the last couple of minutes of events, so
// drivers with no recent event keep their previously known row. Returns a
// NEW object — QML bindings only re-evaluate on whole-property reassignment.
function mergeEvents(existing, rawRows) {
  var base = existing || {}
  var rows
  try { rows = JSON.parse(String(rawRows || "")) } catch (e) { return base }
  if (!rows || !rows.length) return base
  var out = {}
  for (var k in base) out[k] = base[k]
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var key = String(row.driver_number)
    if (!out[key] || String(row.date) > String(out[key].date)) out[key] = row
  }
  return out
}

// Gap column: leader shows "LEADER"; lapped cars keep openf1's "+N LAPS"
// string; everyone else gets a fixed-precision "+s.ttt" so the column
// doesn't jitter as precision varies.
function gapText(intervalRow, isLeader) {
  if (isLeader) return "LEADER"
  if (!intervalRow) return ""
  var gap = intervalRow.gap_to_leader
  if (gap === null || gap === undefined || gap === "") return ""
  if (typeof gap === "string") { gap = clean(gap, 12); return gap.charAt(0) === "+" ? gap : "+" + gap }
  return "+" + Number(gap).toFixed(3)
}

// Ordered leaderboard rows from accumulated state maps:
// [{pos, num, acronym, team, gap}], truncated to limit (0 = all).
function boardRows(posMap, gapsMap, driversMap, limit, detailsMap) {
  var drivers = driversMap || {}
  var gaps = gapsMap || {}
  var details = detailsMap || {}
  var rows = []
  for (var num in posMap) {
    var p = posMap[num]
    var d = drivers[num] || { acronym: "#" + num, team: "" }
    rows.push({
      pos: p.position,
      num: num,
      acronym: d.acronym,
      team: d.team,
      gap: "",
      details: details[num] || ({})
    })
  }
  rows.sort(function(a, b) { return a.pos - b.pos })
  for (var i = 0; i < rows.length; i++)
    rows[i].gap = gapText(gaps[rows[i].num], i === 0)
  if (limit > 0 && rows.length > limit) rows = rows.slice(0, limit)
  return rows
}

// One-shot join of the three raw openf1 feeds — the merge/boardRows pipeline
// collapsed for callers (and tests) that hold complete event histories.
function leaderboard(positionsRaw, driversRaw, intervalsRaw, limit) {
  var posMap = mergeEvents({}, positionsRaw)
  var num
  var any = false
  for (num in posMap) { any = true; break }
  if (!any) return []
  var gapsMap = mergeEvents({}, intervalsRaw)
  var drivers = typeof driversRaw === "string" ? parseDrivers(driversRaw) : (driversRaw || {})
  return boardRows(posMap, gapsMap, drivers, limit)
}

// openf1 /sessions rows carry authoritative start/end. Returns the session
// active at nowMs, or null. Used to trust openf1 over the jolpica estimate
// once live polling has begun.
function pickLiveSession(raw, nowMs) {
  var rows
  try { rows = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!rows || !rows.length) return null
  for (var i = 0; i < rows.length; i++) {
    var s = rows[i]
    var start = Date.parse(s.date_start)
    var end = Date.parse(s.date_end)
    if (!isNaN(start) && !isNaN(end) && nowMs >= start && nowMs < end && !s.is_cancelled)
      return s
  }
  return null
}

// Fold openf1 /race_control events into a track-wide status. Event stream
// examples (real, Hungary 2026): category "SafetyCar" with message
// "VSC DEPLOYED" / "SAFETY CAR DEPLOYED" / "VSC ENDING", and category "Flag"
// with scope "Track" carrying GREEN / CLEAR / YELLOW / DOUBLE YELLOW / RED /
// CHEQUERED. Sector- and driver-scoped flags are deliberately ignored — the
// pill reports the whole track, not one marshal post. Events are applied in
// date order on top of `current`, so overlapping tail polls stay correct
// (the newest event always decides). Returns the new status string:
// green | yellow | sc | vsc | red | chequered.
function foldTrackStatus(current, raw) {
  var status = current || "green"
  var rows
  try { rows = JSON.parse(String(raw || "")) } catch (e) { return status }
  if (!rows || !rows.length) return status
  var sorted = rows.slice().sort(function(a, b) {
    // A valid comparator must return 0 for equal keys; openf1 race-control
    // timestamps are second-precision, so ties are real and mis-ordering one
    // could flip which status (e.g. RED) the pill shows.
    var da = String(a.date), db = String(b.date)
    return da < db ? -1 : (da > db ? 1 : 0)
  })
  for (var i = 0; i < sorted.length; i++) {
    var ev = sorted[i]
    var message = String(ev.message || "").toUpperCase()
    if (ev.category === "SafetyCar") {
      // "ENDING"/"IN THIS LAP" mean the interruption is wrapping up, but the
      // track is only green again when the CLEAR/GREEN flag arrives.
      if (message.indexOf("VIRTUAL") !== -1 || message.indexOf("VSC") !== -1) {
        if (message.indexOf("DEPLOYED") !== -1) status = "vsc"
      } else if (message.indexOf("DEPLOYED") !== -1) {
        status = "sc"
      }
      continue
    }
    if (ev.category !== "Flag" || ev.scope !== "Track") continue
    var flag = String(ev.flag || "").toUpperCase()
    if (flag === "RED") status = "red"
    else if (flag === "YELLOW" || flag === "DOUBLE YELLOW") status = "yellow"
    else if (flag === "GREEN" || flag === "CLEAR") status = "green"
    else if (flag === "CHEQUERED") status = "chequered"
  }
  return status
}

// Compact pill tag for an abnormal track status; empty when the pill should
// just show the leader (green-flag running, or the race is over).
function statusTag(status) {
  if (status === "sc") return "SC"
  if (status === "vsc") return "VSC"
  if (status === "red") return "RED"
  if (status === "yellow") return "YEL"
  return ""
}

// Leader acronym straight off already-joined leaderboard rows.
function leaderAcronym(rows) {
  return rows && rows.length ? rows[0].acronym : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    clean: clean,
    parseSchedule: parseSchedule,
    currentOrNext: currentOrNext,
    countdown: countdown,
    pillText: pillText,
    parseStandings: parseStandings,
    parseDrivers: parseDrivers,
    latestByDriver: latestByDriver,
    mergeEvents: mergeEvents,
    boardRows: boardRows,
    gapText: gapText,
    leaderboard: leaderboard,
    pickLiveSession: pickLiveSession,
    foldTrackStatus: foldTrackStatus,
    statusTag: statusTag,
    leaderAcronym: leaderAcronym
  }
}
