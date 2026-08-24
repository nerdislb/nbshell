# Experimental Umbriel backend

nbshell can keep Niri as the daily compositor while testing
[Umbriel](https://github.com/noctalia-dev/umbriel) as a second backend. Umbriel
replaces the compositor, not Quickshell or the nbshell interface.

This backend is experimental. Umbriel describes its configuration and behavior
as actively evolving, and nbshell does not yet claim feature parity with Niri.

## Current milestone

The shell now detects `UMBRIEL_SOCKET` and exposes one compositor-neutral
service to its UI. The first Umbriel adapter supports:

- live window, focus, and keyboard-layout events through Umbriel JSON IPC;
- occupied workspace display and switching;
- notification window activation and logout;
- shell key bindings and the main floating-window rules;
- native scrolling/dwindle switching through `Mod+Backspace`;
- grim/slurp screenshots;
- theme-synchronized Umbriel colors, borders, and corner radius.

Empty workspaces are not yet reported by Umbriel's current IPC. The first
adapter therefore derives its workspace list from open windows. A later
protocol helper or upstream workspace subscription will complete the model.
Display settings, exact PiP positioning, portal integration, and the special
Niri grid-scroll policy also remain Niri-first at this milestone.

## Safe nested test

Install or build Umbriel and its portal according to the upstream instructions,
then deploy the current nbshell source:

```bash
./install.sh
nbshell compositor nested
```

The command starts Umbriel inside the current desktop and runs a copied
Quickshell configuration inside it. The copied path gives the nested shell a
separate instance identity, so it cannot replace the normal nbshell process.
Umbriel uses `Alt` as `Mod` in this nested profile. Close the experiment with
`Alt+Escape`.

The command does not install packages, modify the active Niri configuration,
or create a display-manager session.

## Native Umbriel session

The installer places three optional files in `~/.config/umbriel/`:

- `nbshell-colors.toml` — generated from the active nbshell theme;
- `nbshell.toml` — shell bindings and window/layer rules;
- `nbshell-nested.toml` — isolated development profile.

For a future native session, include the generated palette first and the shell
integration second from the normal Umbriel configuration:

```toml
[include]
files = ["nbshell-colors.toml", "nbshell.toml"]
```

Keep the existing Niri login available until display handling, screencasting,
locking, NVIDIA/DRM behavior, and the complete streaming workflow have passed
real-hardware tests.
