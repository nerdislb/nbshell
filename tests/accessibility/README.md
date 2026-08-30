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

On Quickshell 0.3.1 with Qt 6.11.2 under Wayland, both the production nbshell
process and an isolated `FloatingWindow` launched with process-local
`QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` registered only an empty application root.
An ordinary Qt Quick `Window` in the same session exported its frame, panel, and
label correctly. This isolates the current blocker to Quickshell's window
integration; it does not indicate a missing AT-SPI bus, broken Qt installation,
or failed QML `Accessible` metadata.

Do not set `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` globally. Use it only for a
bounded isolated diagnostic process. Do not commit generated snapshots.
