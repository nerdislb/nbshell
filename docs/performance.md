# Performance

nbshell keeps the bar, wallpaper, notification popups, OSD, runtime services,
and IPC handlers resident. Larger surfaces that are not useful in the
background—such as display settings, the process list, dashboard, notes, and
the wallpaper picker and unified Library—are created only while open and
destroyed after closing. Launcher window, clipboard, and calculator providers
reuse state already held by the shell. File search starts a capped `fd` process
only for an explicit `@` query. System reports, demo capture, and video exports
are CLI jobs and leave no resident helper behind.

The systemd service also configures jemalloc for Quickshell:

```text
MALLOC_CONF=thp:never,narenas:4,dirty_decay_ms:3000
```

Quickshell on Arch links against jemalloc. Limiting arenas and preventing
small allocations from using transparent huge pages substantially reduces
idle private memory. A user can override `MALLOC_CONF` in a later systemd user
drop-in if a different allocator policy is required.

## Measuring

Use proportional set size rather than RSS when comparing shell revisions. Qt
and graphics libraries map many shared pages that RSS counts in every process:

```bash
pid=$(systemctl --user show nbshell.service -p MainPID --value)
grep -E '^(Rss|Pss|Pss_Anon|AnonHugePages):' /proc/$pid/smaps_rollup
```

Measure after the shell has been idle for several seconds. Open and close each
surface once, wait again, and repeat the measurement to distinguish the clean
startup baseline from caches retained after normal use. Performance numbers
are diagnostics rather than release-test thresholds because GPU drivers,
screen count, plugins, and enabled modules materially change them.

## Runaway application protection

nbshell can optionally enable systemd-oomd for graphical applications:

```bash
nbshell memory-guard setup
nbshell memory-guard status
nbshell memory-guard remove
```

The shell and its Umbriel resume guard run in `session.slice`; applications
remain in `app.slice`. When enabled, systemd-oomd may reclaim an application
cgroup after `app.slice` stays above 60% memory pressure for 20 seconds, with
swap exhaustion as a second backstop. This protects the interactive desktop
without adding a resident nbshell process. The setting is opt-in because an
OOM decision can close an application that has not saved its work.

`remove` deletes only nbshell's app-slice policy. It deliberately leaves the
shared systemd-oomd daemon enabled in case another desktop component uses it.
