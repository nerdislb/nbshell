# Compatibility and limitations

nbshell is an application shell for an existing Wayland compositor session. It
is not a Linux distribution, login manager, compositor, or security boundary.

## Supported baseline

The first beta targets:

- current Arch Linux or an Arch-based system;
- current Umbriel built from its official repository;
- Niri 25.11 or newer retained as the recovery fallback;
- current Quickshell from the Arch repositories;
- PipeWire/WirePlumber for audio;
- NetworkManager for the full network panel;
- a standard systemd user session;

Umbriel is the recommended daily backend, with workspace discovery, display
management, and its native screenshot/screencast portal integrated. It is young
software and can change rapidly, so the installer deliberately preserves Niri
as a selectable recovery session. Exact runtime PiP geometry and nbshell's
specialized paired grid-scroll remain Niri-only. See the
[Umbriel compositor guide](umbriel.md).

Intel and AMD graphics use only normal Wayland interfaces. NVIDIA should work
with a correctly configured modern Wayland driver, but still needs wider beta
testing. Multi-monitor layout, fractional scale, rotation, and disabled outputs
are supported through Niri or Umbriel's native output facilities.

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
- Umbriel uses its native scrolling/dwindle layouts. The paired grid-scroll
  mode remains available in the Niri fallback session.
- Theme synchronization cannot force already-open websites to repaint.
- Some provider integrations depend on unofficial or rate-limited services.
- There is no stable configuration-migration guarantee before version 1.0.
- Only English UI and documentation are supported for the first public beta.

Test nbshell before relying on it on a production machine and keep the Niri
session plus backups of both compositor and nbshell configuration directories.
