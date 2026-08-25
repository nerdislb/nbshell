# Performance

nbshell keeps the bar, wallpaper, notification popups, OSD, runtime services,
and IPC handlers resident. Larger surfaces that are not useful in the
background—such as display settings, the process list, dashboard, notes, and
the wallpaper picker—are created only while open and destroyed after closing.

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
