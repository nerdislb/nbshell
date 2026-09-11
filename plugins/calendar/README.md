# Calendar

A separate floating nbshell Calendar plugin: `io.github.nbshell.calendar`.
It owns its accounts and does not depend on Mail, khal configuration, vdirsyncer,
the existing Calendar service, the clock, or the dashboard. Enabling the plugin makes it available from the shell clock. Accounts are configured separately.

## Launch and setup

The plugin is bundled with nbshell and uses its shared theme and controls. Open it with:

```sh
nbshell extension open io.github.nbshell.calendar
```

The default month view uses a regular grid, a highlighted current day and title-first event tiles. “Calendars” reveals visibility controls. On narrow windows, days use a readable list. “+ more” opens the selected day's agenda. Week currently shows a seven-day list.

Hovering over the shell clock shows today and the next two days, with up to three events per day and an overflow count. The preview reads these same accounts and calendar visibility settings on demand and keeps its snapshot in memory for five minutes. Clicking the clock opens the full app.

Date and time are entered separately in the local time zone (24-hour format). All-day “Last day” is inclusive in the form and converted to the provider's exclusive end internally. Unchanged event timestamps preserve their original offset and seconds.

Runtime dependencies: Quickshell with the native `qs.Common`/`qs.Widgets` API,
Python 3.11+, `secret-tool`, an unlocked desktop Secret Service, and the Python
packages in `backend/requirements.txt`. The khal recurrence backend API is bounded
to the tested 0.14 release family. Dependencies are never installed automatically.
Missing packages, a locked keyring, and missing OAuth client configuration produce
explicit errors. A working desktop browser is needed for Google consent.

**iCloud:** open Accounts, select iCloud, enter an account label, your Apple Account
email and an app-specific password, then Connect. The backend discovers the
principal, calendar home and VEVENT collections starting at
`https://caldav.icloud.com/`. It verifies discovery before saving the account.
Only that host and Apple's numbered `pNN-caldav.icloud.com` shards are accepted.
Redirects, custom servers, URL credentials and cross-collection event writes are
refused. Create the app-specific password through Apple's account management;
do not use your main Apple password.

**Google:** create a Desktop OAuth client in a Google Cloud project with Calendar
API enabled and the consent screen/test-user access configured. Enter its client
ID and secret in Accounts, choose a label, then Sign in with Google. The browser
flow uses an ephemeral IPv4 loopback listener, random state and PKCE S256. It
requests only `calendar.events` and `calendar.calendarlist.readonly`, checks that
both were granted, and saves the refresh token and client secret in Secret
Service. No Gmail scope or Mail grant is reused. The listener closes on completion,
cancellation, window closure or a three-minute timeout. Reconnect if Google
revokes/expires the refresh grant; the plugin does not silently discard a grant
on a transient failure. Each new connection creates an independent local account.

Passwords, refresh tokens and client secrets travel through stdin to `secret-tool`,
never argv or plaintext configuration. Provider requests ignore ambient netrc and
proxy credentials and never follow redirects. Error messages do not echo provider
response bodies. Account labels, IDs, iCloud usernames, Google client IDs and
calendar visibility are stored in a mode-0600 `accounts.json` under
`$XDG_STATE_HOME/nbshell-calendar` (normally `~/.local/state/nbshell-calendar`).
`NBSHELL_CALENDAR_STATE` overrides that location for isolated testing. A file lock
serializes helpers. Disconnect removes the local account and its keyring item;
it neither deletes remote calendars nor revokes the provider grant.

## Operation

Agenda shows fourteen days; Week shows seven days aligned to the locale's first
weekday; Month shows a six-week grid, switching to a scrollable day list in narrow
windows. Dates and display times use the current locale. Tab/Shift+Tab visit
controls, Enter/Space activate them, and Left/Right move within view/provider
segments. Focus scrolls into view. Escape cancels confirmation, leaves an editor
or account page, then closes the window. Shared Theme tokens and controls provide
light/dark styling, visible focus, accessibility and Reduced Motion behavior.

Use Accounts to show/hide calendars. New event requires an explicit writable
account/calendar destination. Open an event to edit or delete it. Every write has
a named destination and a confirmation. Timed input uses ISO date-times with an
explicit UTC offset (for example `2026-09-11T10:00:00+02:00`); all-day input uses
ISO dates with an **exclusive** end. New timed events default to 09:00–10:00
with the local offset for that date. Switching to all-day includes each touched
local wall date, retaining an already-exclusive midnight end; a same-day timed
event becomes one all-day date with the following day as its end. Switching back
uses local midnight boundaries, with each boundary's own DST offset. Multi-day
spans are retained; original hours are not restored. Invalid fields stay unchanged
and show an error. Edited timed values are normalized to UTC by the backend.
The raw ISO editor is a first-version limitation; there is no date/time picker.

## Safety and first-version limits

- iCloud recurrence, exclusions, detached overrides and timezone expansion use
  khal and icalendar. Google expands instances server-side. There is no handwritten
  recurrence parser. khal's own supported recurrence horizon/rules apply; parsing
  failures mark that account stale rather than exposing an incomplete writable view.
- Recurring events and scheduled meetings are view-only, including deletes.
  Change those in the provider app. Event creation is non-recurring; RSVP,
  invitations, moving between calendars and custom CalDAV providers are out of scope.
- Existing iCalendar components and unknown properties are preserved when changing
  title/start/end; Google uses PATCH. The original resource is fetched again before
  an edit/delete. Write privileges are rediscovered, strong ETags are required,
  updates/deletes use `If-Match`, and CalDAV creates use `If-None-Match: *`.
  A conflict requires refresh and reopening the event; no force-overwrite exists.
- Display times are local; all-day dates remain dates. Floating iCalendar times
  display as local wall times and must receive an explicit offset before editing.
  Unsupported event fields remain preserved but are not editable in this version.
- Refresh is explicit. Last successful events remain in memory on failure and are
  visibly stale; all writes are disabled until refresh succeeds. There is no disk
  event cache, background sync daemon or queued offline write. Closing the window
  cancels its helper. A cancelled/timed-out write may already have reached the
  provider: refresh before retrying, especially after create.
- The helper limits a requested window to 100 days, Google pagination to 100 pages,
  individual replies to 16 MiB and each request to connection/read timeouts.
  It does not retry writes automatically. Very large calendars can be slow.

## Verification

From the repository root, set `CALENDAR_SCREENSHOT_OUTPUT` to an explicit writable
output directory outside a read-only source tree:

```sh
export PYTHONDONTWRITEBYTECODE=1
# Set TMPDIR to a writable directory outside the source tree when needed.
python3 -m unittest discover -s plugins/calendar/tests -p 'test_*.py' -v
bash plugins/calendar/tests/run-ui.sh
python3 plugins/calendar/tests/render-matrix.py "$CALENDAR_SCREENSHOT_OUTPUT"
python3 plugins/calendar/tests/smoke.py
python3 plugins/calendar/tests/read-only.py
bash shell/scripts/plugins.sh validate plugins/calendar
bash shell/scripts/plugins.sh design-check plugins/calendar --strict
```

Harnesses create synthetic imports, config, state and runtime directories beneath
`TMPDIR` (the platform temporary directory by default), then remove them even on
failure. Rendering retains only the explicitly requested screenshots. The
read-only check copies only the required sources, removes their write permissions,
verifies a write fails, and runs backend/QML/smoke/render tests with separate
writable outputs. It restores permissions only on its temporary copy for cleanup.

Tests use synthetic accounts and mocked provider transports; the OAuth callback test uses loopback only. Provider writes are not part of visual verification.
