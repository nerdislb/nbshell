const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const Model = require("../Model.js")

const fixture = (name) =>
  fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")

const scheduleRaw = fixture("jolpica-schedule.json")
const driversStandingsRaw = fixture("jolpica-driver-standings.json")
const constructorsRaw = fixture("jolpica-constructor-standings.json")
const openf1SessionsRaw = fixture("openf1-sessions.json")
const openf1DriversRaw = fixture("openf1-drivers.json")
const positionsRaw = fixture("openf1-position-tail.json")
const intervalsRaw = fixture("openf1-intervals-tail.json")

test("parseSchedule reads the season and orders races by round", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  assert.equal(schedule.season, "2026")
  assert.ok(schedule.races.length >= 12)
  const rounds = schedule.races.map((r) => r.round)
  assert.deepEqual(rounds, [...rounds].sort((a, b) => a - b))
})

test("parseSchedule captures the Dutch GP sprint weekend sessions in order", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const dutch = schedule.races.find((r) => r.name === "Dutch Grand Prix")
  assert.ok(dutch)
  assert.equal(dutch.locality, "Zandvoort")
  assert.deepEqual(
    dutch.sessions.map((s) => s.kind),
    ["fp1", "sprintQualifying", "sprint", "qualifying", "race"]
  )
  const race = dutch.sessions[dutch.sessions.length - 1]
  assert.equal(race.startMs, Date.parse("2026-08-23T13:00:00Z"))
  const starts = dutch.sessions.map((s) => s.startMs)
  assert.deepEqual(starts, [...starts].sort((a, b) => a - b))
})

test("parseSchedule tolerates garbage and empty input", () => {
  assert.deepEqual(Model.parseSchedule("not json"), { season: "", races: [] })
  assert.deepEqual(Model.parseSchedule(""), { season: "", races: [] })
  assert.deepEqual(Model.parseSchedule('{"MRData":{}}'), { season: "", races: [] })
})

test("currentOrNext finds the upcoming session between weekends", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  // Wednesday before the Dutch GP, 12:00 UTC.
  const now = Date.parse("2026-08-19T12:00:00Z")
  const state = Model.currentOrNext(schedule.races, now)
  assert.equal(state.status, "next")
  assert.equal(state.race.name, "Dutch Grand Prix")
  assert.equal(state.session.kind, "fp1")
  assert.equal(state.msUntil, Date.parse("2026-08-21T10:30:00Z") - now)
})

test("currentOrNext reports live during a session window", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const state = Model.currentOrNext(schedule.races, Date.parse("2026-08-23T13:45:00Z"))
  assert.equal(state.status, "live")
  assert.equal(state.session.kind, "race")
  assert.equal(state.race.name, "Dutch Grand Prix")
})

test("currentOrNext reports off after the season ends", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const state = Model.currentOrNext(schedule.races, Date.parse("2027-06-01T00:00:00Z"))
  assert.equal(state.status, "off")
})

test("countdown keeps the two most significant units, zero-padded for stable width", () => {
  assert.equal(Model.countdown(2 * 86400000 + 4 * 3600000), "2d 4h")
  assert.equal(Model.countdown(2 * 3600000 + 14 * 60000), "2h 14m")
  assert.equal(Model.countdown(1 * 3600000 + 5 * 60000), "1h 05m")
  assert.equal(Model.countdown(14 * 60000), "14m")
  // Sub-ten-minutes is zero-padded so the pill doesn't lose a character
  // exactly when the countdown is most worth watching.
  assert.equal(Model.countdown(9 * 60000), "09m")
  assert.equal(Model.countdown(60000), "01m")
  assert.equal(Model.countdown(10000), "now")
})

test("clean strips angle brackets and control chars, caps length, defusing rich-text sinks", () => {
  assert.equal(Model.clean("<img src=x onerror=1 width=90000>"), "img src=x onerror=1 width=90000")
  assert.equal(Model.clean("Red Bull Racing"), "Red Bull Racing")   // spaces + normal text survive
  assert.equal(Model.clean("VER\x01"), "VER")               // control chars gone
  assert.equal(Model.clean(null), "")
  assert.equal(Model.clean(undefined), "")
  assert.equal(Model.clean("x".repeat(200), 32).length, 32)
})

test("parsers sanitize API strings so no tag reaches a Text element", () => {
  const drivers = Model.parseDrivers(JSON.stringify([
    { driver_number: 1, name_acronym: "<img src=http://evil>", team_name: "Team <b>X</b>" }
  ]))
  assert.equal(drivers["1"].acronym.indexOf("<"), -1)
  assert.equal(drivers["1"].team.indexOf(">"), -1)

  const standings = Model.parseStandings(JSON.stringify({
    MRData: { StandingsTable: { StandingsLists: [{ DriverStandings: [
      { position: "1", points: "<x>", Driver: { familyName: "<img>", code: "<a>" }, Constructors: [{ name: "<b>" }] }
    ] }] } }
  }), "DriverStandings")
  assert.equal(standings[0].name.indexOf("<"), -1)
  assert.equal(standings[0].points.indexOf("<"), -1)

  const sched = Model.parseSchedule(JSON.stringify({
    MRData: { RaceTable: { season: "2026", Races: [
      { round: "1", raceName: "<img src=x>GP", date: "2026-03-01", time: "13:00:00Z",
        Circuit: { circuitName: "<b>Track</b>" } }
    ] } }
  }))
  assert.equal(sched.races[0].name.indexOf("<"), -1)
  assert.equal(sched.races[0].circuit.indexOf(">"), -1)
})

test("pillText renders countdown and live variants", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const next = Model.currentOrNext(schedule.races, Date.parse("2026-08-21T08:30:00Z"))
  assert.equal(Model.pillText(next), "FP1 2h 00m")
  const live = Model.currentOrNext(schedule.races, Date.parse("2026-08-23T13:45:00Z"))
  assert.equal(Model.pillText(live, "NOR"), "RACE ▸ NOR")
  assert.equal(Model.pillText(live, ""), "RACE ▸ LIVE")
  assert.equal(Model.pillText({ status: "off" }), "")
  assert.equal(Model.pillText(null), "")
})

test("parseStandings reads drivers with code, team, points", () => {
  const rows = Model.parseStandings(driversStandingsRaw, "DriverStandings")
  assert.ok(rows.length >= 20)
  assert.equal(rows[0].pos, 1)
  assert.equal(rows[0].code, "ANT")
  assert.equal(rows[0].team, "Mercedes")
  assert.equal(rows[0].points, "219")
})

test("parseStandings reads constructors", () => {
  const rows = Model.parseStandings(constructorsRaw, "ConstructorStandings")
  assert.ok(rows.length >= 10)
  assert.equal(rows[0].name, "Mercedes")
  assert.equal(rows[0].points, "379")
  assert.equal(rows[1].name, "Ferrari")
})

test("parseStandings tolerates garbage", () => {
  assert.deepEqual(Model.parseStandings("nope", "DriverStandings"), [])
  assert.deepEqual(Model.parseStandings("{}", "DriverStandings"), [])
})

test("parseDrivers maps driver numbers to acronyms and teams", () => {
  const map = Model.parseDrivers(openf1DriversRaw)
  assert.equal(map["1"].acronym, "NOR")
  assert.equal(map["1"].team, "McLaren")
  assert.ok(Object.keys(map).length >= 18)
})

test("latestByDriver keeps only the newest row per driver", () => {
  const rows = [
    { driver_number: 5, date: "2026-08-23T14:00:00+00:00", position: 3 },
    { driver_number: 5, date: "2026-08-23T14:05:00+00:00", position: 1 },
    { driver_number: 7, date: "2026-08-23T13:59:00+00:00", position: 2 }
  ]
  const latest = Model.latestByDriver(rows)
  assert.equal(latest["5"].position, 1)
  assert.equal(latest["7"].position, 2)
})

test("leaderboard joins position, driver, and interval feeds in order", () => {
  const rows = Model.leaderboard(positionsRaw, openf1DriversRaw, intervalsRaw, 0)
  assert.ok(rows.length >= 15)
  const positions = rows.map((r) => r.pos)
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b))
  assert.equal(rows[0].gap, "LEADER")
  for (const row of rows) {
    assert.ok(row.acronym.length >= 2)
    assert.equal(typeof row.gap, "string")
  }
})

test("leaderboard respects the row limit and bad input", () => {
  const rows = Model.leaderboard(positionsRaw, openf1DriversRaw, intervalsRaw, 10)
  assert.equal(rows.length, 10)
  assert.deepEqual(Model.leaderboard("garbage", "{}", "[]", 10), [])
  assert.deepEqual(Model.leaderboard("[]", "{}", "[]", 10), [])
})

test("mergeEvents folds tail batches into accumulated state", () => {
  const first = Model.mergeEvents({}, JSON.stringify([
    { driver_number: 5, date: "2026-08-23T14:00:00+00:00", position: 3 },
    { driver_number: 7, date: "2026-08-23T14:00:01+00:00", position: 1 }
  ]))
  const second = Model.mergeEvents(first, JSON.stringify([
    { driver_number: 5, date: "2026-08-23T14:05:00+00:00", position: 1 },
    { driver_number: 7, date: "2026-08-23T13:59:00+00:00", position: 9 }
  ]))
  assert.equal(second["5"].position, 1)   // newer event wins
  assert.equal(second["7"].position, 1)   // stale event ignored
  assert.notEqual(first, second)          // new object, not in-place mutation
  assert.equal(first["5"].position, 3)
  assert.equal(Model.mergeEvents(first, "garbage"), first)
  assert.equal(Model.mergeEvents(first, "[]"), first)
})

test("boardRows reads accumulated maps directly", () => {
  const posMap = Model.mergeEvents({}, positionsRaw)
  const gapsMap = Model.mergeEvents({}, intervalsRaw)
  const drivers = Model.parseDrivers(openf1DriversRaw)
  const rows = Model.boardRows(posMap, gapsMap, drivers, 5)
  assert.equal(rows.length, 5)
  assert.equal(rows[0].gap, "LEADER")
})

test("gapText formats leader, lapped, and numeric gaps", () => {
  assert.equal(Model.gapText(null, true), "LEADER")
  assert.equal(Model.gapText(null, false), "")
  assert.equal(Model.gapText({ gap_to_leader: "+2 LAPS" }, false), "+2 LAPS")
  assert.equal(Model.gapText({ gap_to_leader: 1.2345 }, false), "+1.234")
  assert.equal(Model.gapText({ gap_to_leader: null }, false), "")
})

test("pickLiveSession trusts openf1 windows and skips cancelled rows", () => {
  const during = Date.parse("2026-08-21T10:45:00Z")
  const live = Model.pickLiveSession(openf1SessionsRaw, during)
  assert.ok(live)
  assert.equal(live.session_name, "Practice 1")
  const between = Date.parse("2026-08-21T12:00:00Z")
  assert.equal(Model.pickLiveSession(openf1SessionsRaw, between), null)
  assert.equal(Model.pickLiveSession("junk", during), null)
})

const raceControlRaw = fixture("openf1-race-control.json")

test("foldTrackStatus replays the real Hungary VSC sequence correctly", () => {
  const events = JSON.parse(raceControlRaw)
  // Up to just after VSC deployment (14:22:55Z): status is vsc.
  const untilVsc = events.filter((e) => e.date <= "2026-07-26T14:23:00+00:00")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify(untilVsc)), "vsc")
  // "VSC ENDING" alone does not clear it — only TRACK CLEAR does.
  const untilEnding = events.filter((e) => e.date <= "2026-07-26T14:24:15+00:00")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify(untilEnding)), "vsc")
  const untilClear = events.filter((e) => e.date <= "2026-07-26T14:24:30+00:00")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify(untilClear)), "green")
  // Whole session ends on the chequered flag.
  assert.equal(Model.foldTrackStatus("green", raceControlRaw), "chequered")
})

test("foldTrackStatus handles SC, red, track yellows; ignores sector/driver flags", () => {
  const mk = (over) => Object.assign({ category: "Flag", scope: "Track", flag: null, message: "", date: "2026-01-01T00:00:00" }, over)
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([
    { category: "SafetyCar", message: "SAFETY CAR DEPLOYED", date: "1" }
  ])), "sc")
  assert.equal(Model.foldTrackStatus("sc", JSON.stringify([
    mk({ flag: "GREEN", message: "TRACK CLEAR", date: "2" })
  ])), "green")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([mk({ flag: "RED" })])), "red")
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([mk({ flag: "DOUBLE YELLOW" })])), "yellow")
  // Sector-scoped yellow and driver-scoped flags do not touch the pill.
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([
    mk({ flag: "YELLOW", scope: "Sector", sector: 7 }),
    mk({ flag: "BLUE", scope: "Driver", driver_number: 55 })
  ])), "green")
  // Garbage and empty batches keep the current status.
  assert.equal(Model.foldTrackStatus("vsc", "junk"), "vsc")
  assert.equal(Model.foldTrackStatus("vsc", "[]"), "vsc")
  // Out-of-order batch: newest event decides regardless of array order.
  assert.equal(Model.foldTrackStatus("green", JSON.stringify([
    mk({ flag: "GREEN", message: "TRACK CLEAR", date: "9" }),
    { category: "SafetyCar", message: "VSC DEPLOYED", date: "3" }
  ])), "green")
})

test("statusTag maps abnormal statuses only", () => {
  assert.equal(Model.statusTag("sc"), "SC")
  assert.equal(Model.statusTag("vsc"), "VSC")
  assert.equal(Model.statusTag("red"), "RED")
  assert.equal(Model.statusTag("yellow"), "YEL")
  assert.equal(Model.statusTag("green"), "")
  assert.equal(Model.statusTag("chequered"), "")
  assert.equal(Model.statusTag(undefined), "")
})

test("pillText: track status outranks the leader while live", () => {
  const schedule = Model.parseSchedule(scheduleRaw)
  const live = Model.currentOrNext(schedule.races, Date.parse("2026-08-23T13:45:00Z"))
  assert.equal(Model.pillText(live, "NOR", "SC"), "RACE ▸ SC")
  assert.equal(Model.pillText(live, "NOR", ""), "RACE ▸ NOR")
  assert.equal(Model.pillText(live, "", ""), "RACE ▸ LIVE")
})

test("leaderAcronym reads the front of the field", () => {
  const rows = Model.leaderboard(positionsRaw, openf1DriversRaw, intervalsRaw, 0)
  assert.equal(Model.leaderAcronym(rows), rows[0].acronym)
  assert.equal(Model.leaderAcronym([]), "")
})
