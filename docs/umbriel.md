# Umbriel compositor

nbshell uses [Umbriel](https://github.com/noctalia-dev/umbriel) as its supported
Wayland compositor. Umbriel owns window management, workspaces, output
configuration, Xwayland, compositor motion, and the screenshot/screencast
portal; Quickshell provides the nbshell interface.

## Installation model

`./setup.sh` builds the reviewed Umbriel and portal revisions, runs both Meson
test suites, and installs the root-owned stack below `/usr/local`. The system
session entry is `/usr/share/wayland-sessions/umbriel.desktop` and launches
`/usr/local/bin/start-umbriel`.

The installation baseline is recorded in `setup-umbriel.sh` and
`shell/Catalog/external-sources.json`. `nbshell upstream-audit` reports newer
upstream commits without installing them automatically.

The shell-facing integration is defined by
[`Umbriel capability contract v1`](umbriel-capability-contract.md). Inspect it
without querying private compositor state:

```bash
nbshell compositor capabilities
nbshell compositor capabilities --json
```

The contract keeps Umbriel as the supported compositor, exposes only named and
validated operations, and reports missing capabilities and fallbacks explicitly.

A files-only installation expects Umbriel to exist already:

```bash
./install.sh
nbshell switch on
```

## Configuration

nbshell writes only its own files below `~/.config/umbriel`:

- `nbshell.toml` — key bindings and window/layer rules;
- `nbshell-colors.toml` — active semantic palette;
- `nbshell-motion.toml` — motion profile;
- `nbshell-overview.toml` — overview backdrop;
- `nbshell-cursor.toml` — cursor theme and size;
- `nbshell-outputs.toml` — persistent output state.

The personal `config.toml` includes the nbshell files; unrelated user settings
are not rewritten. Validate after any manual change:

```bash
umbriel validate
umbriel msg config-reload
```

## Window and workspace workflow

Umbriel provides scrolling, dwindle, and master layouts. `Mod+Backspace` or
`nbshell layout toggle` cycles the focused workspace; choose one directly with:

```bash
nbshell layout scrolling
nbshell layout dwindle
nbshell layout master
```

The default vocabulary uses `Mod+F` for maximize, `Mod+Shift+F` for fullscreen,
`Mod+Shift+V` for floating, `Mod+Tab` for overview, and `Mod+O` for the shell
island. `Mod+K` opens the searchable view of the active Umbriel bindings.

## Outputs and capture

The display panel reads live output state through `wlr-randr`, applies changes
through Umbriel-compatible output management, and persists accepted values in
`nbshell-outputs.toml`. Mode changes are transactional: rejected DRM modes
restore the prior live and saved state.

nbshell uses `grim`, `slurp`, and `wf-recorder` for explicit capture actions.
Umbriel's portal serves application-driven screenshots and screencasts. The
window selector uses Umbriel's window geometry instead of compositor-specific
screen scraping.

## PiP

Zen Picture-in-Picture windows open floating in the lower-right corner through
an Umbriel window rule. The PIP module and `Mod+Alt+P` cycle the floating window
width with Umbriel IPC. Umbriel does not currently expose arbitrary corner
movement for an already open floating window; move it directly with the normal
floating-window pointer controls.

## Login and recovery

The Orbital greetd frontend runs in an isolated root-owned Umbriel instance.
Only `/usr/local/bin/start-umbriel` is allowed as a graphical login session.
An independent agreety configuration is staged at
`/etc/greetd/config.toml.nbshell-recovery`; it does not depend on Umbriel,
Quickshell, the wallpaper, or Orbital QML.

The native in-session locker remains a separate `WlSessionLock` process in
`nbshell-lock.service`. Suspend waits for compositor-confirmed secure coverage.
TTY recovery remains available when the graphical session cannot start.

## Updating

```bash
nbshell update
nbshell update umbriel
```

The Umbriel updater compares both clean source checkouts with their upstream
default-branch heads. After explicit confirmation it fetches the exact revisions
reported by the check, builds and tests both projects, then installs both. This
uses isolated detached worktrees and rejects remote history that does not
fast-forward the installed source checkout. Both DESTDIR trees are merged before
live files change and deployed as one rollback-capable transaction. The running compositor is not
restarted; the new binary becomes active at the next login.

Use the nested profile for a non-DRM development smoke test:

```bash
nbshell compositor nested
```

A real login is still required to validate DRM, suspend/resume, locking,
multi-monitor behavior, and streaming on each hardware configuration.
