# Performance code review — 2026-08-28

Provider: OpenAI Codex

## Scope and method

Reviewed runtime paths in `shell/Bar/`, `shell/Widgets/`, non-security-sensitive
`shell/Services/`, `integrations/`, and enabled plugin implementations. The audit
enumerated 520 QML/JavaScript/shell sites involving timers, processes, loaders,
models, repeaters, completion handlers, and change handlers, then traced the
always-on and short-interval paths. Authentication, lock/greeter, IPC, update,
installer, and user-configuration paths were not edited.

The review concentrated on child-process polling, timer lifetime, hidden surface
loading, feedback loops, binding/model churn, synchronous I/O, and retained or
unbounded data. Existing lazy surface checks in `tests/performance-smoke.sh` and
memory-pressure checks in `tests/memory-guard.sh` were also reviewed.

## Implemented improvements

### Network throughput sampler

Before, each one-second sample while the system popout was visible started this
pipeline from `shell/Services/Net.qml`:

```text
sh -> ip + awk + cat(rx_bytes) + cat(tx_bytes)
```

That is five child processes per tick (up to 300 child processes per minute of
panel visibility). The new sampler reads `/proc/net/route` and `/proc/net/dev`
with Quickshell `FileView` objects. It preserves the one-second cadence, default
route selection, interface-change reset, counter-delta calculation, and the
existing visibility gate. After: zero child processes per sample.

### Pit Wall live snapshot

Before, an enabled live bridge started `/usr/bin/cat` every two seconds to read
its JSON snapshot: 30 child processes per minute during live timing. The service
now reloads the same bounded snapshot with `FileView`; parsing and state updates
are unchanged. After: zero child processes per snapshot.

Together these changes remove up to 330 child-process launches per minute when
both affected views are active. This is a structural count from the explicit
commands and timer intervals, not a synthetic wall-clock benchmark; process
startup cost varies by machine.

## Regression coverage and verification

`tests/performance-smoke.sh` now asserts both direct-file implementations and
guards against restoring the former command-based samplers. The procfs parsing
helper also has fixture-based tests for route flags, interface selection, and
RX/TX counter columns. Verification run:

- `bash tests/performance-smoke.sh` — pass
- `node tests/net-metrics.test.js` — pass (also run by the smoke test)
- `node plugins/pit-wall/tests/model.test.js` — 26/26 pass
- `git diff --check` — pass

## Findings retained without changes

- `SysInfo` reads small procfs files every two seconds. Its expensive detail
  subprocess is already gated by panel visibility, including optional GPU work.
- Wi-Fi and Bluetooth scans are explicitly bounded and disabled when their
  panels close; no extra timer was found.
- Audio uses PipeWire observers for live values. Codec and route subprocesses
  run only on user action instead of polling.
- `MotionLoader` and top-level shell loaders keep heavyweight surfaces
  unmounted until requested. Bar widgets remain resident by design for immediate
  feedback and external popout handling.
- Weather refreshes every 15 minutes by default and has script-side caching;
  lowering that cadence further could make user-configured behavior surprising.
- Pit Wall fallback mode can issue five OpenF1 requests every 20 seconds during
  a live event. They are bounded, overlap-protected, and necessary to assemble
  distinct API feeds. Consolidating them requires a provider/API design change.
- Several services periodically read cheap local state (`/proc`, `/sys`, or
  small runtime files). Their intervals and visibility/feature gates are
  reasonable; replacing them without a reliable event source would risk stale
  UI state.
- Reactive array sorting/filtering in network, Bluetooth, audio, and plugin
  models allocates new arrays on source changes. These collections are bounded
  by devices/streams and update event-wise, so caching would add invalidation
  complexity without credible benefit.

No unbounded runtime model or cache was found in the owned paths. No additional
change met the audit's high-confidence, behavior-preserving threshold.
