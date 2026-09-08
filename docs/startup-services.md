# Service startup and demand

Session observers must remain available before their UI is opened. Startup
retains lock/idle handling, notifications, audio/display observers, wallpaper
and theme propagation, agent session attention, and update monitoring. Task,
note and habit stores keep their existing synchronization and count behavior.
The process-list snapshot still supports the synchronous cached `procs top`
reply. Nearby already scans only on demand; Dictation watches a state file.
Zen PiP observes new compositor windows so automatic PiP handling works without
opening a control first. Removing these startup references blindly would change
behavior, not just save initialization work.

Two independently verified demand boundaries are narrower:

- `AiUsage` is instantiated by a configured AI widget, the dashboard, or an
  explicit AI IPC request. A session without those consumers does not search
  for provider helpers, fetch provider usage or scan local usage statistics at
  login. After first use, its existing refresh cadence remains active. Agent
  session tracking is separate and continues to start normally. An immediate
  first `ai status` reports provider discovery while that work is pending.
- `Cursor` continues observing theme/size settings from startup. It enumerates
  available themes only when standalone or embedded Settings is opened. A
  successful enumeration is cached for the session; repeated requests while
  loading are coalesced. Invalid results remain retryable. `refresh()` still
  supports explicit enumeration. Existing cursor settings continue applying
  without opening Settings.

## Verification

`tests/startup-services.py` runs the real Cursor singleton with private XDG
paths and a synthetic helper. It checks startup application, absence of startup
enumeration, duplicate-demand coalescing, caching and failure/retry.

The existing isolated Wayland harness also exercises real consumers:

```sh
python3 tests/wayland-lifecycle.py --compositor /path/to/umbriel \
  --render-node /dev/dri/renderD128 --output /path/to/new-results \
  --cycles 1 --settle-seconds 0 --startup-profile
```

Add `--startup-ai-widget` to verify that configured AI widgets still initialize
usage at login. Add `--startup-embedded-settings` to exercise the main menu's
Settings page before the standalone panel. Both paths must enumerate cursor
choices once and keep those choices on reopening.

Instrumentation is inserted only into the disposable source copy. It records
service names and direct QML `Process` starts, never command arguments. Service
files with an existing `onStarted` handler are excluded from process tracing;
detached commands and descendant processes are not counted. The six-second
startup snapshot uses a clock-only bar unless the AI widget flag is supplied,
with private configuration, no provider accounts, and no external network.

A before/after probe on this fixture recorded 26 versus 22 instrumented process
starts, with the removed four starts occurring on subsequent demand. With the
AI widget configured, its three usage helpers still run at startup, leaving 25
starts. These are counts for this fixture, not all system processes and not a
claim of proportional login-time, CPU or memory improvement. PSS snapshots in
the artifacts are diagnostic and are not a controlled memory benchmark.
