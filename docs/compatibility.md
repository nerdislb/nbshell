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
and the screenshot/screencast portal. Fresh installations use the reviewed
baseline. The explicit Umbriel updater can follow newer upstream heads, but only
from clean expected-origin checkouts and only after both projects build and pass
their tests.

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
- Pixel Buds batteries and confirmed noise control require `pbpctrl`; other
  advanced headsets use BudsLink and its user-session D-Bus service;
- AI, gaming, mail, music, capture, and streaming tools have their own visible
  dependency checks.

## Known beta limitations

- Third-party QML plugins run unsandboxed with the current user's permissions.
- Quickshell 0.3.1 can log transient `PwNode` device-association errors while
  its PipeWire registry is still receiving a graph. The same messages reproduce
  in a minimal Quickshell PipeWire configuration without nbshell code; on the
  tested PipeWire 1.6.8 system the graph settled with valid default input and
  output devices. nbshell collapses duplicate output rows by PipeWire node name
  while retaining the preferred object. Report any missing device or audio
  failure rather than treating a warning alone as a broken installation.
- Native screen-reader traversal of Quickshell surfaces is not functional yet.
  With accessibility forced on for an isolated diagnostic process, both
  `PanelWindow` and `FloatingWindow` expose only the AT-SPI application root;
  an ordinary Qt Quick `Window` in the same session exports its frame and label.
  Keyboard operation and internal Qt accessibility contracts remain tested,
  but they do not replace a traversable AT-SPI tree. Quickshell fixed the
  application-lifecycle cause upstream in commit `916a0dd`; the current Arch
  `quickshell` 0.3.1 package predates that fix, so nbshell keeps this limitation
  visible until a containing Quickshell release reaches the supported baseline.
  An isolated build at that commit exported both managed windows and labels,
  confirming the upstream correction without replacing the packaged runtime.
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
