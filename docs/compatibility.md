# Compatibility and limitations

nbshell is an application shell for an existing Wayland compositor session. It
is not a Linux distribution, login manager, compositor, or security boundary.

## Supported baseline

The first beta targets:

- current Arch Linux or an Arch-based system;
- Niri 25.11 or newer with its JSON IPC available;
- current Quickshell from the Arch repositories;
- PipeWire/WirePlumber for audio;
- NetworkManager for the full network panel;
- a standard systemd user session;
- tmux for nbshell-native Agent Console session persistence.

Umbriel support is an experimental second backend with workspace discovery,
display management, and its native screenshot/screencast portal integrated.
The supported daily baseline remains Niri while native hardware coverage grows.
Exact runtime PiP geometry remains Niri-only. See
[Experimental Umbriel backend](umbriel.md).

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
- The grid-scroll mode builds paired Niri columns; it does not replace Niri's
  layout engine or provide Hyprland's binary tree.
- Theme synchronization cannot force already-open websites to repaint.
- Some provider integrations depend on unofficial or rate-limited services.
- There is no stable configuration-migration guarantee before version 1.0.
- Only English UI and documentation are supported for the first public beta.

Test nbshell before relying on it on a production machine and keep a backup of
the Niri and nbshell configuration directories.
