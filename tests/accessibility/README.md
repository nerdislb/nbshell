# Native AT-SPI diagnostics

`atspi_probe.py` captures a bounded JSON snapshot of an application's native
AT-SPI tree. Snapshots may contain visible labels or descriptions, so the probe
writes mode-`0600` files under `/tmp` by default.

```bash
python3 tests/accessibility/atspi_probe.py \
  --pid "$(systemctl --user show nbshell.service -p MainPID --value)"
```

Optional focus-event capture blocks for the requested interval:

```bash
python3 tests/accessibility/atspi_probe.py --events-seconds 10
```

Exit codes:

- `0`: a non-empty application tree was captured;
- `2`: no matching application was exported;
- `3`: the application was registered, but its exported tree contained only the
  application root.

Run unit tests with:

```bash
python3 -m unittest -v tests/accessibility/test_atspi_probe.py
```

## Current Quickshell boundary

On Quickshell 0.3.1 with Qt 6.11.2 under Wayland, the production nbshell process
was not registered while accessibility was inactive. An isolated Quickshell
process with both `PanelWindow` and `FloatingWindow`, `UseQApplication`, and
process-local `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` registered only an empty
application root. An ordinary Qt Quick `Window` in the same session exported
its frame and label correctly. This isolates the current blocker to Quickshell's
application/window integration; it does not indicate a missing AT-SPI bus,
broken Qt installation, or failed QML `Accessible` metadata.

Upstream Quickshell issue
[#1006](https://github.com/quickshell-mirror/quickshell/issues/1006) identifies
the cause as Quickshell destroying Qt Quick's accessibility hooks when it
replaced its initial application object. Commit
[`916a0dd`](https://github.com/quickshell-mirror/quickshell/commit/916a0dd90cf2e349116381e0abbbfcf94387eb77)
removes that replacement and is seven commits ahead of `v0.3.1`. The installed
Arch `quickshell` 0.3.1 package predates the fix. Keep the expected-empty result
for that baseline until a containing release is installed and re-tested.

An isolated build at `916a0dd` was also tested in the same session with one
`PanelWindow` and one `FloatingWindow`. The probe returned exit code `0`, five
nodes, two frame children, and both expected labels. This confirms the upstream
fix while keeping installed-package and source-build evidence distinct.

Do not set `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` globally. Use it only for a
bounded isolated diagnostic process. Do not commit generated snapshots.
