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

## Settings and Modules focus regression

`tests/wayland-panel-focus.py` runs the real production shell under a private
headless Umbriel session, D-Bus, HOME and runtime namespace. It requires
`bwrap`, `wtype`, `python-atspi`, a built Umbriel `pointer-client`, and an explicit
Quickshell executable containing the accessibility export fix. It does not
install anything or send input to the live desktop.

```bash
python3 tests/wayland-panel-focus.py \
  --quickshell /path/to/quickshell-build/src/quickshell \
  --compositor /path/to/umbriel \
  --pointer-client /path/to/umbriel-build/tests/pointer-client \
  --render-node /dev/dri/renderD128
```

Choose an available render node explicitly. Optional `--theme catppuccin-latte`,
`--motion reduced`, `--width 1920` and `--height 1080` select additional cases.
The default is Tokyo Night, standard motion, 800×600. Missing prerequisites or
an empty AT-SPI tree fail explicitly; they are not successful skips.

The regression checks named native focus, Tab/Shift+Tab between panes, arrow
navigation, keyboard/pointer/AT-SPI activation, module reorder/removal and
cross-group movement, empty-group recovery, scroll visibility, and removal of
closed panels from both the compositor and AT-SPI trees. Temporary configuration
is disposable. Captured output does not establish visual focus quality, motion
timing, physical-keyboard behavior or Orca speech acceptance.

Geometry checks use native AT-SPI output bounds in both axes and read-only
diagnostic IPC injected into a disposable copy of the shell. The IPC measures
the actual focused row against every clipping QML ancestor in scene coordinates;
it does not alter production focus or scroll behavior. Only the visible,
non-embedded Settings instance registers the Settings probe. Source and installed
QML remain untouched by the harness. Initial rows, both panes, and every step of
the scroll traversal are checked, not just the final position.

Use `--screenshots /path/to/new-directory` to export synthetic screenshots of
initial, scrolled and empty-group states. This requires `grim`; the output
directory must not already exist. These images require human visual inspection.

Use `--orca-log /path/to/new-log.txt` to run the installed Orca in the same
isolated session. This was exercised with Orca 50.2, including its native
`READY=1` notification. It checks real focus-to-speech-text generation, ordered
pane/row announcements, changing setting values, and the empty-group fallback.
The private Orca customization only enables line-buffered diagnostic output;
focus processing and speech generation are not mocked. Selected input steps
wait for a fresh expected utterance: otherwise Orca may legitimately discard
an intermediate focus event superseded by the next rapid test key.

Speech Dispatcher is deliberately unavailable in this mode. No host audio,
physical input, user Orca preferences, or desktop session bus is exposed.
A passing log does **not** establish audible synthesis, pronunciation, physical
keyboard behavior, or subjective screen-reader usability. The log path must not
already exist; logs contain only the disposable test session's synthetic data.

Run the clipping predicate's boundary and negative-control tests together with
the AT-SPI probe tests:

```bash
python3 -m unittest discover -s tests/accessibility -p 'test_*.py'
```
