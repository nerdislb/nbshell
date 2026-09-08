# Isolated Wayland lifecycle measurement

Run the production shell with a disposable HOME, D-Bus session, network namespace
and headless Umbriel. This neither installs files nor targets the live desktop.
Requires `bwrap`, `quickshell`, `grim`, `dbus-run-session`, a compatible Umbriel
executable and an accessible DRM render node.

```sh
python3 tests/wayland-lifecycle.py \
  --compositor /path/to/umbriel \
  --render-node /dev/dri/renderD128 \
  --output /path/to/new-results-directory
```

Idle actions are disabled only in the disposable test configuration so a
screensaver or automatic lock cannot contaminate the settling measurement.

The default opens and closes Settings and Modules 100 times each, checks for
exactly one mapped panel and the initially visible Settings heading, and samples PSS/RSS during cycles and a 60-second
settling period. Results, synthetic screenshots, and logs go to the output
directory even if a scenario fails. Missing prerequisites fail explicitly.
Use `--theme catppuccin-latte --motion reduced --width 1280 --height 720` for
another display case. `--settle-seconds 1800` extends the post-cycle observation.

Latency is measured from before the Quickshell IPC invocation until Umbriel
reports the layer mapped. It includes CLI startup and polling overhead; it is
**not first-frame presentation latency**. The shell uses Qt's software renderer.
These results do not establish physical input latency, GPU performance, complete
service behavior, session login/locking/suspend correctness, or equivalence with
Omarchy. The sandbox deliberately has no host system bus or personal services.
Use the separate native focus/AT-SPI tests for keyboard and accessibility checks.
