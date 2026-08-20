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

The data model and API design are adapted from
[`omarchy-pit-wall-entry`](https://github.com/jeremylongshore/omarchy-pit-wall-entry)
by Jeremy Longshore under the MIT License. The nbshell host, service split,
and popout UI are native to nbshell.

The plugin makes read-only, keyless HTTPS requests to:

- `api.jolpi.ca` every 15 minutes for schedule and standings;
- `api.openf1.org` every 20 seconds only while a session is live.

Responses are capped at 8 MB and requests time out after 15 seconds. No
account, API key, or local data storage is used.
