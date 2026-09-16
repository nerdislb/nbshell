# Speed test alignment

## Scope recorded before implementation

Round 21 uses Omarchy Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`,
`shell/Ui/SpeedTestOverlay.qml` and `shell/plugins/panels/speedtest/Panel.qml`.
Adapt its paired 270-degree gauges, 46 ticks, hubless needle, centered title,
readout and retry action. Preserve nbshell's speedtest-cli/Ookla selection,
ping plausibility filter, server label and persistent expanding scale.
No fast.com switch, bar/global-token changes or automatic dependency installs.

Intentional differences: theme-derived contrast instead of fixed white on black;
static measuring status and unknown values rather than simulated live values
or an ignition sweep (the native backend returns the final result only).
Shared motion tokens and Reduced Motion govern real value transitions.
Retain Enter/Space retry, Escape and outside close; add a visible accessible
retry/close path and cancel backend work when the surface is dismissed.


## Implementation and deliberate adaptations

- Native `SpeedWindow` adapts the actual upstream `SpeedDial` Shape paths, ticks,
  glow and needle. The pinned MIT notice remains in `LICENSES/THIRD_PARTY_MIT.md`
  and attribution is recorded in `THIRD_PARTY.md`.
- The 210px dial, 48px gap and specialist geometry use the existing menu font
  scale. Narrow outputs scale needle/tick offsets and numeric typography with
  the dial; unit/direction captions remain legible and do not overlap. Long
  server names wrap in a bounded Flickable, with focus-revealing Tab navigation.
- Uses theme foreground/accent on a 90% theme-background scrim rather than
  upstream's fixed-white/78%-black treatment. This deliberately supports light
  themes. No additional palette or shared token changes.
- The persistent native scale still expands to the next 50 Mbit/s and never
  shrinks after a lower measurement; upstream resets among predefined stops.
  Actual zero is displayed as zero, unknown/error as a dash. Ping outside
  `(0, 5000)` ms is omitted, preserving the native plausibility guard.
- Visible Close and a disabled “Measuring…” action supplement upstream's retry.
  Enter/Space, pointer and accessible retry share the same running guard;
  autorepeat cannot launch a new test when the previous one has just finished.
- The global `net speed` toggle and all existing callers remain unchanged.
  The loader now waits for both MotionSurface dismissal and backend exit.
  Reopening during cancellation queues a fresh measurement after teardown.
- `speedtest.sh` retains its public JSON entry point and execs `speedtest.py`.
  The same speedtest-cli preference, Ookla fallback, flags and unit conversions
  remain. No new provider, credentials, package installation or license policy.
  The already-existing Ookla accept-license/GDPR flags are unchanged.
- The adapter owns a child process group, bounds the measurement to 120s,
  handles SIGTERM/SIGINT and cleans up descendants (including TERM-ignoring
  workers). A pending-cancel flag covers cancellation while Popen returns;
  no signal mask is inherited by the client. Successful, failed and timed-out
  runs also clean up the group. An uncatchable kill/crash is not a graceful
  dismissal guarantee.

## Verification

`tests/speedtest-lifecycle.py` runs production QML and the production Python
adapter against a private fake speedtest-cli with real child processes. It has
no host network, D-Bus, clipboard or config access. Thirty assertions pass per
run: dark 1280×800 and light 420×600 with Reduced Motion (60 total).

Checks include measured/zero/unknown/error states, scale persistence, literal
long provider names, bounded layout, non-overlapping labels, Tab/focus return,
held-key guards, all retry/close paths, descendant cleanup and rapid reopen.
`tests/test_speedtest.py` adds six tests for both backend conversions, invalid
values, missing client, failed/malformed output, timeout and actual signal
cancellation; it is part of `tests/qml.sh`. The 120 shared QML tests also pass.

```sh
python3 tests/wayland-lifecycle.py --compositor /usr/local/bin/umbriel \
  --render-node /dev/dri/renderD128 --output /tmp/speedtest-dark \
  --speedtest-contract --pointer-client /path/to/pointer-client \
  --width 1280 --height 800 --qt-backend rhi
```

Repeat with `--width 420 --height 600 --theme catppuccin-latte --motion reduced`.
The output directory must not exist. The pale background window in test images
is a synthetic focus-return target. Before, pinned unmodified upstream gauge
render, after, light/narrow, error and focus screenshots were inspected.

Design/Umbriel contracts, Python compilation and shell syntax checks pass.
The global PlainText scan retains four pre-existing Omamail findings:
CalendarSettings:171 and SettingsPage:280,308,316; none in this surface.
A bounded subscription-only Sonnet review returned no response within 60s;
independent approval remains unavailable (earlier alternatives in this alignment
session also reached quota/timeouts). No paid fallback or auth changes.


Installed via `./install.sh`, source/runtime files compared byte-for-byte,
service active and complete Umbriel configuration validated. The real installed
surface was opened and inspected while speedtest-cli was running. After the
live run the surface was closed and no measurement processes remained. The
native `speedScale` entry was added with 450 Mbit/s; reconstructing the prior
configuration without that single field reproduces its original SHA256.
No other user settings changed. Actual bandwidth figures were not retained or
claimed from the subsequently closed window; successful result rendering and
unit conversion are proven by the isolated fixtures, not a saved live result.
