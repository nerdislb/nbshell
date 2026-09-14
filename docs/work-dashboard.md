# Work dashboard (first version)

Open the dashboard's **WORK** tab, press **4** in the dashboard, or run:

```sh
nbshell dashboard view work
```

The page combines the existing Herdr session monitor with a read-only local
OpenClaw gateway adapter. Sessions needing input appear first, then working
sessions. OpenClaw only reports **Working** or **Idle**, based on its live run
flag; inactivity is not interpreted as a request for input.

Select a row with the pointer or Tab + Enter to open the exact OpenClaw session
in the browser or focus its existing Herdr session. Escape closes the dashboard.
OpenClaw progress-card step summaries are shown when available. Markdown-only
cards are not rendered. Session titles are metadata, not transcript previews.

Git summaries show branch, changed entries (including untracked entries), and
conflicts for explicitly supplied local session directories. Missing project
metadata is displayed as **Project not provided**; no repository is guessed.
Git runs locally with optional locks and fsmonitor hooks disabled. Nothing is
committed, fetched, staged, or uploaded.

## Limits and lifecycle

- Session detail requests run only while WORK is open, using the existing
  three-second monitor. No new daemon, quota source, Ollama task, or history scan.
- At most 40 OpenClaw rows and 12 progress cards are requested per detail refresh.
  Archived, hidden, and incognito sessions are excluded from the displayed list.
- At most 12 distinct project directories are checked every 15 seconds while
  visible, with four workers and a two-second timeout per Git command.
- A stopped Herdr server or unavailable gateway produces an explicit status
  error, not a fabricated idle/empty success. Herdr is not started automatically.
- The adapter supports the existing local, non-TLS OpenClaw gateway configuration.
  Credentials stay in the existing monitor and are never included in row data
  or links. OpenClaw browser authentication remains separate and unchanged.
- Bar appearance and wallpaper behavior are unchanged.
