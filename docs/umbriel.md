# Umbriel compositor

nbshell uses [Umbriel](https://github.com/noctalia-dev/umbriel) as its
recommended daily compositor. Umbriel replaces the compositor, not Quickshell
or the nbshell interface; Niri remains installed as a recovery fallback.

Umbriel describes its configuration and behavior as actively evolving. That is
why nbshell keeps its Niri backend, configuration, and greeter entry working
instead of treating the main-compositor decision as irreversible.

## Current milestone

The shell now detects `UMBRIEL_SOCKET` and exposes one compositor-neutral
service to its UI. The first Umbriel adapter supports:

- live window, focus, and keyboard-layout events through Umbriel JSON IPC;
- complete workspace display (including empty workspaces) and switching through
  the standard `ext-workspace-v1` protocol;
- notification window activation and logout;
- shell key bindings and the main floating-window rules;
- PrettyZap/WhatsApp launch and focus through `Mod+Shift+M`;
- native scrolling/dwindle switching through `Mod+Backspace`;
- live multi-display mode, scale, transform, placement, and enable controls;
- screenshots and screen sharing through xdg-desktop-portal-umbriel;
- native idle DPMS and focused-output selection for screen recordings;
- top-left hot corner, `Mod+Tab`, and four-finger swipe for Umbriel's overview;
- theme-synchronized Umbriel colors, borders, and corner radius.

Umbriel's native dwindle layout is used as the compositor equivalent of the
nbshell grid toggle. Exact runtime resizing and corner cycling of an already
open PiP window remains Niri-only because Umbriel currently exposes no floating
window geometry action; the opening rule still makes PiP floating and places it
in the lower-right corner.

The primary keyboard vocabulary matches the Niri profile: `Mod+F` maximizes,
`Mod+Shift+F` toggles fullscreen, `Mod+Shift+V` toggles floating, `Mod+Tab`
opens the overview, and `Mod+O` pins the shell island. Launcher, theme, bar,
audio, workspace, output, width, wheel-navigation, DPMS, and session bindings
use their established Niri chords where Umbriel provides an equivalent action.

## Install the complete stack

On Arch Linux, the normal setup installs build dependencies, builds Umbriel and
its portal from their official repositories, installs them below `~/.local`,
adds the login-session entry, deploys nbshell, and retains Niri:

```bash
./setup.sh
```

Use `./setup-umbriel.sh` to add Umbriel to an existing files-only/Niri setup,
or `./setup.sh --niri-only` to deliberately skip the recommended compositor.

The script refuses to overwrite a source checkout with local changes. It adds
only the Umbriel session entry to `/usr/share/wayland-sessions`; it does not
remove or modify the Niri entry.

## Updates

Dashboard → Tools → **Desktop updates** checks the installed Umbriel and portal
commits against the official noctalia-dev repositories. An update is offered
only when both source trees are clean and still point to the expected origins.
The updater fast-forwards, builds, runs each project's Meson tests, and installs
to `~/.local`; it never restarts the compositor underneath the current session.
Log out and back in when the update finishes.

The equivalent terminal commands are:

```bash
nbshell update                 # check nbshell, Umbriel, and the portal
nbshell update umbriel         # update only the compositor stack
nbshell update all             # install every available desktop update
```

These two projects are source builds, not AUR-managed packages. Distribution
and AUR packages remain under the separate **System updates** action.

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
- `nbshell-cursor.toml` — live cursor theme and size from Settings.
- `nbshell-overview.toml` — theme-aware native overview backdrop styling.

The Settings entries for cursor theme and size update Umbriel and GTK live.
Niri keeps its own generated cursor include for fallback sessions. The
Niri-specific **Blur overview** setting is presented as **Overview backdrop**
on Umbriel and controls the native overview tint and workspace-card background;
Umbriel does not need nbshell's additional blurred wallpaper layer.

Umbriel supervises its own Xwayland Satellite process. The setup installs a
systemd condition that keeps Arch's separately enabled
`xwayland-satellite.service` available for Niri without starting a duplicate
inside Umbriel sessions.

If no Umbriel configuration exists, nbshell creates this minimal entry point:

```toml
[include]
files = ["nbshell-colors.toml", "nbshell.toml"]
```

Log out and choose **Umbriel** in the greeter for normal use. The session
starts the normal `graphical-session.target`, so the enabled nbshell service and
portal start with the compositor. Choose **Niri** in the greeter to return to
the established session. Nested validation covers rendering, IPC, outputs,
workspaces, Xwayland startup, and portal screenshots; a native session is still
required to validate DRM, suspend, locking, and the complete streaming workflow
on each new hardware configuration. Choose **Niri** if an Umbriel update blocks
login or a compositor-specific workflow.

When suspend is started through nbshell, the lock helper records Umbriel's
assigned windows before the outputs disappear. After resume it reattaches only
windows that lost that prior workspace and restores the previous focus. This
works around an early Umbriel output-recreation edge case without changing
scratchpad windows or otherwise healthy workspace state.
