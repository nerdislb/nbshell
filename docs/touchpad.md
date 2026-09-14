# Touchpad

Open **System → Touchpad**, or run `nbshell touchpad`.

Native Umbriel settings with pointer-curve mathematics adapted from
[Trackpad Plus](https://github.com/davefano/omarchy-trackpad-plus), revision
`d6847f8ac05a0cf59f4502a17368d330fba357cb` (2026.09.13.1).
Andrew Kent and David Fano's MIT notice is retained in
`shell/Touchpad/LICENSE.trackpad-plus`.

## Try a Mac-inspired response

1. Choose **MAC-INSPIRED**. At the default 1× editor range, the preset uses
   0.1875× precision, 20% acceleration start, 70% end, and 1× fast swipes.
2. Press **APPLY & TRY**, then use the numbered targets or your usual apps.
3. Use **RESTORE PREVIOUS** to switch back. Discard any unapplied draft first.

This is an approximation of pointer acceleration, not macOS scroll momentum,
gestures, or haptic feedback. Hardware, display scale, and personal preference
matter. The upstream author's M2-specific low-gain settings are not applied
automatically to a PC trackpad.

## Controls

- System inherits the acceleration profile from the underlying config/libinput;
  Adaptive and Flat explicitly select those profiles.
- Mac-inspired initializes the editable curve; editing makes it Custom.
- Drag P/S/E/F in the graph, or focus a handle and use arrow keys. Shift makes
  larger steps. Numeric fields and sliders provide the same controls.
- The editor range changes the chart scale, not an existing curve. Choosing the
  Mac preset again uses the current range, as in the original.
- Pointer speed is retained when using a custom curve but is not applied there.
- Scroll speed is separate and applies to **all touchpads** (Umbriel: 0.1–10×).
- Tap, natural scrolling, disable-while-typing, and physical click method can be
  explicit or inherited. Existing per-device rules take precedence.
- Changes stay in a draft until Apply; Escape/Close asks before discarding one.
  Nothing is applied merely by opening this window or choosing a preset.

## Persistence and recovery

The first Apply adds `nbshell-touchpad.toml` to the main Umbriel config's include
list. Other settings are preserved. The managed file contains both active
settings and one previous snapshot; do not hand-edit its machine-readable
header. Restore swaps between the current and previous snapshot, including
across restarts. Restoring the first edit restores inheritance, leaving an
inactive managed file and its harmless include in place.

Before writing watched config files, the helper validates a temporary candidate
with the installed Umbriel and checks custom samples with libinput. A stale
revision or conflicting main-file override rejects the draft. Config snapshots
in `~/.config/nbshell/touchpad/pending.json` recover interrupted writes on the
next operation. Recovery refuses to overwrite external edits; retain the
journal and resolve the reported file conflict. Compositor availability and
writable storage are necessary for runtime recovery.

Settings target `~/.config/umbriel/config.toml` (or the corresponding
`XDG_CONFIG_HOME` location). Sessions started with a different `umbriel -c`
configuration are not supported by this first version.

## Current limits

This is a native settings port, not a compatible Omarchy plugin host. It does
not install Omarchy, Hyprland, a background input daemon, or a compositor patch.
Per-device enable/disable and independent per-device scroll factors are not
exposed. libinput validates the curve object, but device acceptance and actual
pointer feel still depend on hardware; check the Umbriel log if an option has
no effect. Application-specific scrolling can differ.

## Verification

```sh
python3 tests/test_touchpad.py
bash tests/touchpad-ui.sh
python3 -m py_compile shell/scripts/touchpad.py
bash -n bin/nbshell
umbriel validate
```

The UI test uses the actual Quickshell engine and native components with an
in-memory draft, including pointer and keyboard events, drag handles, narrow
geometry, dark/light captures, error/empty states, and Reduced Motion. It never
applies input settings. Backend tests use temporary config files and real
Umbriel/libinput validation, with simulated reload failures and crash recovery.
