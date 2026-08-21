# Pit Wall for nbshell

Pit Wall shows the next Formula 1 session in the nbshell bar and provides the
weekend schedule, live timing, and championship standings in a native popout.
The popout's **Open window** action launches a resizable floating timing board
that can stay visible for the whole session. It uses the same central service,
so opening both views never duplicates API polling.

The window can also be controlled from the command line:

```sh
nbshell extension open pit-wall
nbshell extension toggle pit-wall
nbshell extension close pit-wall
```

Press `R` in the window to refresh the schedule and standings, or `Esc` to
close it. Live timing continues to refresh automatically every 20 seconds.

## Free live timing

Install the optional local SignalR bridge once:

```sh
~/.config/nbshell/plugins/pit-wall/scripts/setup-live.sh
```

Restart nbshell afterwards. During a live session, Pit Wall starts the bridge
on demand, reads the public Formula 1 timing stream every two seconds, and
stops it again after the session. The bridge runs without root privileges and
does not require an F1 account. Its Python environment lives under
`~/.local/share/nbshell/pit-wall`; it is never enabled as a login service.

The data model and API design are adapted from
[`omarchy-pit-wall-entry`](https://github.com/jeremylongshore/omarchy-pit-wall-entry)
by Jeremy Longshore under the MIT License. The nbshell host, service split,
and popout UI are native to nbshell.

The plugin makes read-only, keyless HTTPS requests to:

- `api.jolpi.ca` every 15 minutes for schedule and standings;
- `livetiming.formula1.com` through the optional local SignalR bridge while a
  session is live;
- `api.openf1.org` every 20 seconds as a fallback when that bridge is absent.

The HTTP responses are capped at 8 MB and requests time out after 15 seconds.
The bridge keeps only one transient JSON snapshot in the user runtime directory;
it does not retain sessions or telemetry.

OpenF1 historical data is free, but its provider requires a paid Sponsor API
key for data from a session that is still running or ended less than 30 minutes
ago. Without that key, Pit Wall still shows the Jolpica schedule and current
session state, and explicitly marks live timing as locked instead of presenting
an unexplained empty table. The SignalR bridge avoids that limitation, but it
uses an undocumented Formula 1 endpoint and may need maintenance if the provider
changes its protocol.
