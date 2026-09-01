# Beta testing checklist

Use this checklist on a machine that has never run nbshell. A virtual machine
can validate files, but real Wayland hardware is required for display, input,
capture, and animation testing.

## Clean installation

- Clone the repository into a new user account.
- Run the minimal `./setup.sh` profile and read every proposed package.
- Enable the integration with `nbshell switch on`, then log out and in.
- Confirm that the bar, launcher, dashboard, settings, and power menu open.
- Confirm that optional modules fail quietly when their programs are absent.
- Run `nbshell --version`, `nbshell status`, and `umbriel validate`.
- Check the shell log after startup. Quickshell 0.3.1 may emit the documented
  transient PipeWire node-association diagnostics; verify that the selected
  input, output, volume, and mute controls still work before reporting them as
  a functional regression.
- With the full capture profile installed, use `grim` for reproducible visual
  comparison screenshots without changing nbshell's native capture workflow.

## Desktop behavior

- Test 100%, 125%, 150%, and 200% scale where the display supports it.
- Test one display, two displays, disconnect/reconnect, rotation, and suspend.
- Exercise scrolling, dwindle, and master layouts, close middle windows, open
  overview, and verify that floating windows remain untouched.
- Test keyboard-only navigation, Escape behavior, hover previews, and every
  bar edge and mode.
- When testing with assistive technology, use the native AT-SPI probe and keep
  the current Quickshell boundary in the report; internal QML metadata tests do
  not establish screen-reader traversal.
- Leave the shell idle for at least two hours and compare memory use.

## Upgrade and recovery

- Change a theme, module arrangement, and plugin setting.
- Pull the next revision and run `./install.sh`; personal state must remain.
- Disable one bundled plugin and install one reviewed external plugin.
- Verify Umbriel login, shell startup, `nbshell switch off`, TTY recovery, and
  restoration of the previous settings.
- Re-enable nbshell and confirm that the previous settings return.

## Report

Record GPU and driver, display layout, Umbriel and Quickshell versions, nbshell
revision, failed step, reproduction
sequence, and sanitized log excerpt. Never
include credentials, notification text, clipboard contents, network addresses,
or calendar data.
