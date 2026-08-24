# Experimental Umbriel backend

nbshell can keep Niri as the daily compositor while testing
[Umbriel](https://github.com/noctalia-dev/umbriel) as a second backend. Umbriel
replaces the compositor, not Quickshell or the nbshell interface.

This backend is experimental. Umbriel describes its configuration and behavior
as actively evolving. Niri remains installed as the safe fallback.

## Current milestone

The shell now detects `UMBRIEL_SOCKET` and exposes one compositor-neutral
service to its UI. The first Umbriel adapter supports:

- live window, focus, and keyboard-layout events through Umbriel JSON IPC;
- complete workspace display (including empty workspaces) and switching through
  the standard `ext-workspace-v1` protocol;
- notification window activation and logout;
- shell key bindings and the main floating-window rules;
- native scrolling/dwindle switching through `Mod+Backspace`;
- live multi-display mode, scale, transform, placement, and enable controls;
- screenshots and screen sharing through xdg-desktop-portal-umbriel;
- native idle DPMS and focused-output selection for screen recordings;
- top-left hot corner, `Mod+O`, and four-finger swipe for Umbriel's overview;
- theme-synchronized Umbriel colors, borders, and corner radius.

Umbriel's native dwindle layout is used as the compositor equivalent of the
nbshell grid toggle. Exact runtime resizing and corner cycling of an already
open PiP window remains Niri-only because Umbriel currently exposes no floating
window geometry action; the opening rule still makes PiP floating and places it
in the lower-right corner.

## Install the complete stack

On Arch Linux, the optional setup script installs build dependencies, builds
Umbriel and its portal from their official repositories, installs them below
`~/.local`, adds the login-session entry, and then deploys nbshell:

```bash
./setup-umbriel.sh
```

The script refuses to overwrite a source checkout with local changes. It adds
only the Umbriel session entry to `/usr/share/wayland-sessions`; it does not
remove or modify the Niri entry.

## Safe nested test

After installing the stack, run:

```bash
./install.sh
nbshell compositor nested
```

The command starts Umbriel inside the current desktop and runs a copied
Quickshell configuration inside it. The copied path gives the nested shell a
separate instance identity, so it cannot replace the normal nbshell process.
Umbriel uses `Alt` as `Mod` in this nested profile. Close the experiment with
`Alt+Escape`.

The command does not modify the active Niri configuration.

## Native Umbriel session

The installer places the integration files in `~/.config/umbriel/`:

- `nbshell-colors.toml` — generated from the active nbshell theme;
- `nbshell.toml` — shell bindings and window/layer rules;
- `nbshell-nested.toml` — isolated development profile.
- `nbshell-outputs.toml` — display settings managed by the shell.

If no Umbriel configuration exists, nbshell creates this minimal entry point:

```toml
[include]
files = ["nbshell-colors.toml", "nbshell.toml"]
```

Log out and choose **Umbriel** in the greeter for the native test. The session
starts the normal `graphical-session.target`, so the enabled nbshell service and
portal start with the compositor. Choose **Niri** in the greeter to return to
the established session. Nested validation covers rendering, IPC, outputs,
workspaces, Xwayland startup, and portal screenshots; a native session is still
required to validate DRM, suspend, locking, and the complete streaming workflow
on each machine.
