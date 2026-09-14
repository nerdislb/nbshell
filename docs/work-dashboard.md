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

## Desktop work cards

The optional **Work Desk** lives above the wallpaper and below normal windows.
It does not replace the wallpaper, reserve window space, or alter the AI bar.

```sh
nbshell work on
nbshell work off
nbshell work toggle
nbshell work status
nbshell work module sessions off
nbshell work module activity on
nbshell work module git on
nbshell work module device toggle
nbshell work module quotas on
nbshell work project /absolute/project/path
```

**Mod+Alt+I** toggles the whole desk. The command palette also offers **Desktop
work cards**. The header has individual module switches and a Hide button.
Settings persist across shell restarts; new installations default to disabled.
Click a control to give the desktop keyboard focus, then use Tab / Enter.
Escape hides the desk while it owns focus. Session focus scrolls into view.
Normal windows keep priority over the desktop's on-demand keyboard focus.

Working/attention sessions use a horizontal card grid, followed by local daily
activity, Git projects and ten compact recent-session rows. **Show all** expands
the remaining recent sessions. Narrow displays stack telemetry below sessions;
the whole desk scrolls when needed. Translucent rounded panels and compact
module chips follow the Infomarchy preview composition, using native theme
colors and controls. Light themes use higher surface opacity for readability.
The optional activity module uses existing AiUsage daily CLI token totals; it is
not an hourly heatmap and does not claim to cover OpenClaw usage.

Device data reuses CPU, RAM, network and battery services. Root-filesystem free
space, hostname and uptime are sampled locally once per minute only while the
device module is enabled. No public-IP request, GPU wakeup or new daemon.
Quotas reuse AiUsage and its existing refresh cadence; module switches do not
stop shared services used elsewhere in the shell.

The dashboard and desktop share one WorkState cache. Session-detail requests
run when either WORK is open or the desktop sessions/Git modules need them.
Git runs when either dashboard WORK or desktop Git is enabled. Disabling the
desk releases its demand; already-running bounded probes may finish. No new
probes are scheduled for disabled consumers.

Explicitly pinned directories are stored in `workProjects`, alongside paths
supplied by sessions (12 total). To clear pinned directories:
`nbshell set workProjects '[]'`. Pinning never assigns that project to a session
whose project metadata is missing. Git is local-only: no fetch, push or commit.

### Regression coverage

`tests/wayland-work-desktop.py` runs the real shell in a disposable, network-
isolated Umbriel session. It checks empty and long session data, responsive
layout, pointer/Enter module toggles, expanded-list focus containment, Tab back
to the header, Escape, and shared dashboard/desktop demand. Supply Quickshell,
Umbriel, its built `pointer-client`, and a DRM render node; use `--width`,
`--height`, `--theme`, `--motion`, and `--screenshots` for visual coverage.
The host's configuration and display geometry are not changed by this test.
