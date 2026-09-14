.pragma library

// UI labels, editable prompts and local composer/queue interaction.
// Job parsing, ownership, attention, history and payload construction live in
// Rust; their historical JS baselines are confined to tests/oracles/agent.

var ACTIVE = ["queued", "running"]

var DRAFT_ASKS = [
  { id: "review", label: "Review", prompt: "Review this draft: is it clear, complete and right in tone for its recipient? Answer with your review, not a rewrite." },
  { id: "rewrite", label: "Rewrite", prompt: "Rewrite this draft so it reads clearly and naturally, keeping every fact and the owner's voice." },
  { id: "shorten", label: "Shorten", prompt: "Shorten this draft to the fewest words that still say everything it says." },
  { id: "expand", label: "Expand", prompt: "Expand this draft: fill in what a reader would need and the owner left implied, without inventing facts." },
  { id: "formal", label: "More formal", prompt: "Rewrite this draft in a more formal register, keeping every fact." },
  { id: "friendly", label: "Friendlier", prompt: "Rewrite this draft in a warmer, friendlier register, keeping every fact." },
  { id: "notes", label: "From notes", prompt: "The body is notes. Write the email they describe, to this recipient, in the owner's voice." }
]

var MAIL_TRANSFORM_FORMAT = "Use exactly this reply layout: Title: <mail title>, then a blank line, then Body: on its own line followed by the mail body. Do not include any other headers or commentary."

var MAIL_ASKS = [
  {label: "Summarize", prompt: "Summarize this mail and highlight its key points."},
  {label: "Explain", prompt: "Explain this mail in plain language, including any unfamiliar terms."},
  {label: "Action items", prompt: "List the requested actions, deadlines, and open questions in this mail."},
  {label: "Draft a reply", prompt: "Draft a reply to this mail. Flag any missing information instead of inventing facts."},
  {label: "Translate to Chinese", prompt: "Translate only the mail title and body into Chinese. Exclude sender, recipients, dates, metadata, and instructions."},
  {label: "Translate to English", prompt: "Translate only the mail title and body into English. Exclude sender, recipients, dates, metadata, and instructions."}
]

function isActive(job) {
  return !!job && ACTIVE.indexOf(String(job.state || "")) >= 0
}

function glyphState(job) {
  if (!job) return ""
  var state = String(job.state || "")
  if (state === "queued" || state === "running") return "running"
  if (state === "done") return String(job.question || "") !== "" ? "question" : "done"
  if (state === "failed") return "failed"
  if (state === "cancelled") return "cancelled"
  return ""
}

function workingText(job, now, preparationStarted) {
  var active = isActive(job)
  var start = active && Number(job.created) > 0 ? Number(job.created) * 1000 : preparationStarted
  var seconds = Math.max(0, Math.floor((now - start) / 1000))
  var duration = Math.floor(seconds / 60) + "m " + (seconds % 60) + "s"
  return "• " + (active ? "Working" : "Preparing") + " (" + duration
    + (active ? " • Esc to interrupt" : "") + " • / show commands)"
}

function progressText(job) {
  if (!job || !isActive(job)) return ""
  return String(job.progress || "").trim()
}

function stateLabel(job) {
  var glyph = glyphState(job)
  if (job && job.resultReady) return "Ready"
  if (glyph === "running") return String(job.stall || "") === "permission" ? "Stopped to ask" : "Working"
  if (glyph === "question") return "Has a question"
  if (glyph === "done") return "Done"
  if (glyph === "failed") return "Failed"
  if (glyph === "cancelled") return "Cancelled"
  return ""
}

function detailText(job) {
  if (!job) return ""
  if (String(job.question || "") !== "") return String(job.question)
  if (String(job.error || "") !== "") return String(job.error)
  return String(job.summary || "")
}

function finishedNote(job) {
  var glyph = glyphState(job)
  var subject = String(job && job.subject ? job.subject : "").trim()
  var about = subject === "" ? "the message" : "“" + subject + "”"
  // A look for events was not asked for by name: it says something only
  // when it found something, and nothing at all when it found nothing.
  if (isEventsJob(job)) {
    var found = glyph === "done" && Array.isArray(job.events) ? job.events.length : 0
    return found > 0 ? "The agent found " + (found === 1 ? "an event" : found + " events") + " in " + about : ""
  }
  if (glyph === "question") return "The agent has a question about " + about
  if (glyph === "done") return "The agent finished with " + about
  if (glyph === "failed") return "The agent failed on " + about
  if (glyph === "cancelled") return "The AI session for " + about + " was closed"
  return ""
}

function pluralizeMessages(count) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  return n === 1 ? "1 message" : n + " messages"
}

function draftAsks() {
  var out = []
  for (var i = 0; i < DRAFT_ASKS.length; i++) {
    var ask = DRAFT_ASKS[i]
    var prompt = ask.prompt + " Work only on the mail title and body; do not rewrite addresses, dates, metadata, or this instruction."
    if (ask.id !== "review") prompt = prompt.replace("Answer with your review, not a rewrite.", "") + " " + MAIL_TRANSFORM_FORMAT
    out.push({id: ask.id, label: ask.label, prompt: prompt})
  }
  return out
}

function draftAnswer(job, output, transcript) {
  if (!job || (isActive(job) && !job.resultReady) || glyphState(job) === "failed" || job.question) return ""
  var text = String(output || "")
  var rows = Array.isArray(transcript) ? transcript : []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].role === "user" && rows[i].text.indexOf(MAIL_TRANSFORM_FORMAT) >= 0) {
      var body = /^Title: [^\r\n]*\r?\n\r?\nBody:\r?\n([\s\S]*)$/.exec(text)
      return body ? body[1] : ""
    }
  }
  return text
}

// Editor change indicator only; ownership remains accountId plus draftKey.
function draftFingerprint(fields) {
  var v = fields || {}
  var text = JSON.stringify([v.from || "", v.to || "", v.subject || "", v.body || ""])
  var hash = 2166136261
  for (var i = 0; i < text.length; i++) { hash ^= text.charCodeAt(i); hash = (hash * 16777619) >>> 0 }
  return String(hash)
}

function mailAsks(multiple) {
  var asks = []
  for (var i = 0; i < MAIL_ASKS.length; i++) {
    var ask = MAIL_ASKS[i]
    asks.push({label: ask.label, prompt: ask.prompt + " Work only from the mail title and body."
      + (ask.label.indexOf("Translate") === 0 ? " " + MAIL_TRANSFORM_FORMAT : "")})
  }
  asks.push({id: "rewrite", label: "Rewrite", prompt: "Rewrite only the mail title and body for clarity, preserving facts. Exclude addresses, dates, metadata and instructions. " + MAIL_TRANSFORM_FORMAT})
  if (multiple) asks.unshift({label: "Compare mails", prompt: "Compare these mails, summarize what changed, and list shared action items and unresolved questions."})
  return asks
}

function chatEntries(value) {
  var rows = Array.isArray(value) ? value : []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i]
    if (!entry || ["user", "assistant", "status"].indexOf(entry.role) < 0 || typeof entry.text !== "string") continue
    out.push({role: entry.role, text: entry.text})
  }
  return out
}

function createdOrder(job) {
  return Number(job && job.createdOrder || Number(job && job.created || 0) * 1000000000)
}

function commandSuggestions(text, choices) {
  var value = String(text || "")
  var match = /(?:^|\n)\/([a-z-]*)$/.exec(value)
  if (!match) return {start: -1, items: []}
  var items = []
  for (var i = 0; i < choices.length; i++) {
    var choice = choices[i]
    var command = String(choice.id || choice.label.toLowerCase().replace(/ /g, "-"))
    if (command.indexOf(match[1]) === 0 || choice.label.toLowerCase().indexOf(match[1]) === 0)
      items.push({command: command, label: choice.label, prompt: choice.prompt})
  }
  return {start: value.lastIndexOf("/"), items: items}
}

// Selected commands keep their prompt out of the editable presentation text.
function expandCommands(text, tokens) {
  var result = text
  for (var i = tokens.length - 1; i >= 0; i--)
    result = result.slice(0, tokens[i].start) + tokens[i].prompt + result.slice(tokens[i].end)
  return result
}

function editCommands(before, after, tokens) {
  var start = 0
  while (start < before.length && start < after.length && before[start] === after[start]) start++
  var oldEnd = before.length
  var newEnd = after.length
  while (oldEnd > start && newEnd > start && before[oldEnd - 1] === after[newEnd - 1]) { oldEnd--; newEnd-- }
  var from = start
  var to = oldEnd
  var kept = []
  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    if ((start < token.end && oldEnd > token.start)
        || (start === oldEnd && start > token.start && start < token.end)) {
      from = Math.min(from, token.start)
      to = Math.max(to, token.end)
    } else kept.push(token)
  }
  var inserted = after.slice(start, newEnd)
  var delta = inserted.length - (to - from)
  var shifted = []
  for (var j = 0; j < kept.length; j++) {
    var item = kept[j]
    var offset = item.start >= to ? delta : 0
    shifted.push({start: item.start + offset, end: item.end + offset, prompt: item.prompt})
  }
  return {text: before.slice(0, from) + inserted + before.slice(to), tokens: shifted,
    cursor: from + inserted.length}
}

function historyLabel(job) {
  return new Date(Number(job.created || 0) * 1000).toLocaleString() + " · " + String(job.requestPreview || job.subject || "Conversation")
}

function pendingJob(jobs, currentJob, scopeMatches, conversationId, previousId) {
  var rows = Array.isArray(jobs) ? jobs : []
  if (!rows.length && scopeMatches && currentJob) rows = [currentJob]
  var result = null
  for (var i = 0; i < rows.length; i++) {
    var job = rows[i]
    if (conversationId === "") {
      if (!scopeMatches || !currentJob || job.id !== currentJob.id || String(job.id) === previousId) continue
    } else if (String(job.conversationId || job.id) !== conversationId) continue
    if (!result || createdOrder(job) > createdOrder(result)) result = job
  }
  return result
}

function pendingLimit(messages, text) {
  if (messages.length >= 20) return "The queue is full. Wait for a reply or remove a pending message."
  var size = text.length
  for (var i = 0; i < messages.length; i++) size += messages[i].length
  if (text.length > 65536 || size > 262144) return "This pending message is too long. Shorten it before sending."
  return ""
}

// ------------------------------------------------------------ suggested events

// A message the owner opens is handed to the agent to look for calendar
// events in — a meeting, a dinner, a flight, a deadline — when the setting
// is on and the text so much as mentions a date or a time. The look is a
// background job: it draws no glyph, asks for no attention and answers to
// no row; its findings are the card the reader shows. Rust runs the look and
// reads the array out of the answer; what is here is the gate before it and
// the words after it.
function isEventsJob(job) {
  return !!job && String(job.kind || "") === "events"
}

// Whether the text says when: a clock time, a month with a day, a numeric
// date, a day said relative to today, or a weekday bound to a plan ("on
// Thursday", "next Fri"). Cheap, and it decides only whether the agent is
// worth asking — but not generous: a look costs a model call with the whole
// message in it, and a bare "May", "March" or "Sunday" in running prose is
// a word, not a plan. The short forms are read only beside a number.
var MONTH_ANY = "january|february|march|april|may|june|july|august|september|october|november|december"
  + "|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec"
var DAY_ANY = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
  + "|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun"
var DATE_HINTS = [
  new RegExp("\\b(" + MONTH_ANY + ")\\.?\\s+\\d{1,2}\\b", "i"),
  new RegExp("\\b\\d{1,2}(st|nd|rd|th)?\\s+(" + MONTH_ANY + ")\\b", "i"),
  new RegExp("\\b(on|next|this|every|by|until|till|before)\\s+(" + DAY_ANY + ")\\b", "i"),
  new RegExp("\\b(" + DAY_ANY + ")\\.?,?\\s+(\\d{1,2}\\b|at\\b|morning|afternoon|evening|night)", "i"),
  /\b\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}\b/,
  /\b\d{4}-\d{2}-\d{2}\b/,
  /\b\d{1,2}:\d{2}\b/,
  /\b\d{1,2}\s?(am|pm)\b/i,
  /\b(tomorrow|tonight|next (week|month)|this (week|weekend|evening|afternoon|morning))\b/i
]
function mentionsDate(text) {
  var value = String(text || "")
  if (value === "") return false
  for (var i = 0; i < DATE_HINTS.length; i++) if (DATE_HINTS[i].test(value)) return true
  return false
}

// Mail no person wrote to the owner: a notification, a bounce, a newsletter,
// a list — or one Gmail already filed under a category. A bank's notice
// and a CI run both mention dates, and neither is asking the owner to
// dinner; a look at them is a model call for `[]`. Read from what the row
// already carries, so it costs nothing.
var AUTOMATED_LOCAL = /^(no-?reply|noreply|do-?not-?reply|donotreply|mailer-daemon|postmaster|bounces?|notifications?|alerts?|newsletters?|digests?|updates?|news|info|marketing|support|billing|receipts?|orders?)([@.+_-]|$)/i
var AUTOMATED_WITHIN = /(no-?reply|donotreply|do-not-reply|notifications?@|mailer-daemon|bounce)/i
var CATEGORY_LABELS = ["CATEGORY_PROMOTIONS", "CATEGORY_UPDATES", "CATEGORY_FORUMS", "CATEGORY_SOCIAL"]
function automatedMail(summary) {
  var row = summary || {}
  var email = String(row.from && row.from.email ? row.from.email : "").trim().toLowerCase()
  if (AUTOMATED_LOCAL.test(email) || AUTOMATED_WITHIN.test(email)) return true
  var labels = Array.isArray(row.labelIds) ? row.labelIds : []
  for (var i = 0; i < labels.length; i++) if (CATEGORY_LABELS.indexOf(String(labels[i])) >= 0) return true
  return false
}

// The whole gate before the model: mail from a person, not from a list —
// the reader knows a list by its List-Unsubscribe header — that says when.
function worthALook(summary, text, listMail) {
  if (listMail === true || automatedMail(summary)) return false
  return mentionsDate(text)
}

// A message from two months ago is about events that have passed; the
// agent is not asked about it. Nor about one whose date is unknown: a
// look costs an agent run, and "no idea when" is not a reason to spend one.
var EVENTS_MAX_AGE_MS = 60 * 24 * 3600 * 1000
function tooOldForEvents(messageMs, nowMs) {
  var when = Number(messageMs) || 0
  if (when <= 0) return true
  return Number(nowMs) - when > EVENTS_MAX_AGE_MS
}

// How many looks may run at once. Opening a mailbox's worth of mail one
// message after another must not fan out into one agent per message.
var EVENTS_IN_FLIGHT = 2

// The one fixed ask a look carries. The rules around it are the worker's.
var EVENTS_PROMPT = "Find the calendar events in this message."

// The look the projection holds for a message, in its account — running or
// finished — or null. A look that failed or was cancelled answered nothing
// and is not held, so the message may be looked at again.
function lookFor(looks, accountId, messageId) {
  var account = String(accountId || "")
  var id = String(messageId || "")
  if (account === "" || id === "" || !looks) return null
  var own = looks[account]
  return own && own[id] ? own[id] : null
}

function suggestionKey(jobId, index) {
  return String(jobId || "") + ":" + Math.max(0, Math.floor(Number(index) || 0))
}

// The events a finished look found, less the ones the owner has waved away
// this session, each with the key that names it. A look still running has
// found nothing yet.
function eventSuggestions(look, dismissed) {
  var job = look || null
  var gone = Array.isArray(dismissed) ? dismissed : []
  if (!isEventsJob(job) || String(job.state || "") !== "done") return []
  var events = Array.isArray(job.events) ? job.events : []
  var out = []
  for (var k = 0; k < events.length; k++) {
    var event = events[k] || {}
    var key = suggestionKey(job.id, k)
    if (gone.indexOf(key) >= 0) continue
    var startMs = Number(event.startMs) || 0
    if (String(event.title || "").trim() === "" || startMs <= 0) continue
    var endMs = Number(event.endMs) || 0
    out.push({
      key: key, jobId: String(job.id), index: k,
      title: String(event.title).trim(),
      startMs: startMs,
      endMs: endMs > startMs ? endMs : startMs + 3600000,
      allDay: event.allDay === true,
      location: String(event.location || "").trim(),
      notes: String(event.notes || "").trim()
    })
  }
  return out
}

// "Thu 12 Sep, 19:00–20:00", "Thu 12 Sep (all day)", "Fri 12 Sep 2027, 09:00 – Sat 13 Sep 2027, 17:00":
// the year only when it is not this one, the end only when it is not the
// hour after the start.
var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
function suggestionWhen(suggestion, nowMs) {
  var s = suggestion || {}
  var start = new Date(Number(s.startMs) || 0)
  if (!isFinite(start.getTime()) || start.getTime() <= 0) return ""
  var now = new Date(Number(nowMs) || Date.now())
  function two(n) { return n < 10 ? "0" + n : String(n) }
  function day(d) {
    var text = DAY_NAMES[d.getDay()] + " " + d.getDate() + " " + MONTH_NAMES[d.getMonth()]
    return d.getFullYear() !== now.getFullYear() ? text + " " + d.getFullYear() : text
  }
  function clock(d) { return two(d.getHours()) + ":" + two(d.getMinutes()) }
  var end = new Date(Number(s.endMs) || 0)
  if (s.allDay === true) {
    var lastDay = isFinite(end.getTime()) && end.getTime() > start.getTime() ? new Date(end.getTime() - 1) : start
    return day(start) + (day(lastDay) !== day(start) ? " – " + day(lastDay) : "") + " (all day)"
  }
  if (!isFinite(end.getTime()) || end.getTime() <= start.getTime()) return day(start) + ", " + clock(start)
  var sameDay = end.getFullYear() === start.getFullYear() && end.getMonth() === start.getMonth() && end.getDate() === start.getDate()
  if (sameDay) return day(start) + ", " + clock(start) + "–" + clock(end)
  return day(start) + ", " + clock(start) + " – " + day(end) + ", " + clock(end)
}

// What the composer opens with, and whose calendar. The composer creates
// timed events on one day, so a whole day opens as nine to ten and an
// event that runs past midnight ends at the day's last minute, with the
// notes saying what the message actually put — the owner reads the form
// before anything is written, which is the point of opening it.
function eventPrefill(suggestion, accountId) {
  var s = suggestion || {}
  var start = Number(s.startMs) || 0
  var end = Number(s.endMs) || 0
  var notes = String(s.notes || "")
  function add(line) { notes = (notes === "" ? "" : notes + "\n\n") + line }
  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
  }
  if (s.allDay === true) {
    var at = new Date(start)
    var last = end > start ? new Date(end - 1) : at
    at.setHours(9, 0, 0, 0)
    start = at.getTime()
    end = start + 3600000
    add(sameDay(last, at) ? "All day, as the message put it."
      : "All day through " + suggestionWhen({ startMs: last.getTime(), endMs: last.getTime() }, Date.now()).split(",")[0] + ", as the message put it.")
  } else if (end > start && !sameDay(new Date(start), new Date(end))) {
    var dayEnd = new Date(start)
    dayEnd.setHours(23, 59, 0, 0)
    add("The message has it ending " + suggestionWhen({ startMs: end, endMs: end }, Date.now()) + ".")
    end = dayEnd.getTime()
  }
  return { title: String(s.title || ""), startMs: start, endMs: end > start ? end : start + 3600000,
    location: String(s.location || ""), description: notes, accountId: String(accountId || "") }
}
