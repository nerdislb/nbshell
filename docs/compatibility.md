# Compatibility and limitations

nbshell is a desktop shell for the Umbriel Wayland compositor. It is not a
Linux distribution, display manager, compositor, or independent security
boundary.

## Supported baseline

The current beta targets:

- current Arch Linux or an Arch-based system;
- the reviewed Umbriel and portal revisions installed by `setup-umbriel.sh`;
- current Quickshell from the Arch repositories;
- PipeWire/WirePlumber for audio;
- NetworkManager for the full network panel;
- a standard systemd user session.

Umbriel provides workspace discovery, output management, session lock, Xwayland,
and the screenshot/screencast portal. It is still evolving, so nbshell pins and
tests reviewed revisions instead of installing an unreviewed moving branch.

Intel and AMD graphics use normal Wayland interfaces. NVIDIA requires a modern
Wayland driver and still benefits from wider beta testing. Multi-monitor layout,
fractional scale, rotation, refresh-rate selection, and disabled outputs are
managed through Umbriel's output facilities.

## Optional hardware and services

The shell starts without optional tools. Their matching controls become useful
only when the dependency is installed or the service is available:

- Bluetooth requires BlueZ;
- calendar sync requires khal and optionally vdirsyncer;
- phone features require KDE Connect, adb, scrcpy, or the webcam helper;
- headset battery reporting requires a device supported by headsetcontrol;
- AI, gaming, mail, music, capture, and streaming tools have their own visible
  dependency checks.

## Known beta limitations

- Third-party QML plugins run unsandboxed with the current user's permissions.
- Umbriel currently has no IPC action for arbitrary corner movement of an
  already open floating PiP window.
- Theme synchronization cannot force already-open websites to repaint.
- Some provider integrations depend on unofficial or rate-limited services.
- There is no stable configuration-migration guarantee before version 1.0.
- Only English UI and documentation are supported for the first public beta.

Test nbshell before relying on it on a production machine and keep backups of
both Umbriel and nbshell configuration directories. The independent recovery
paths are Orbital's agreety configuration and a normal TTY, not a second desktop
compositor.
