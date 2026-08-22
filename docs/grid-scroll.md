# Grid-scroll development

nbshell keeps Niri's scrolling layout and adds an optional workspace policy:
one or two windows remain normal columns, while three or more windows are
paired into two-tile columns. `Mod+Backspace` enables or disables the policy
for the focused workspace.

## Backends

The stable backend works with stock Niri and remains the default:

```bash
nbshell grid backend stable
nbshell grid status
```

It sends one public Niri IPC action at a time and waits for every confirmed
layout transition. This is reliable, but an uncommon full regroup can expose
an intermediate frame because Niri returns to its event loop between actions.

The experimental backend sends the same operations as one raw IPC `Actions`
request:

```bash
nbshell grid backend status
nbshell grid backend atomic
```

It requires the
[`nbshell/atomic-actions`](https://github.com/nerdislb/niri/tree/nbshell/atomic-actions)
branch of the nbshell Niri prototype.
nbshell checks support before enabling it, so the command cannot silently turn
on against stock Niri. Return to the supported path at any time with:

```bash
nbshell grid backend stable
```

When the separate prototype binary is installed, the compositor used for the
next login can also be selected without replacing `/usr/bin/niri`:

```bash
nbshell grid compositor status
nbshell grid compositor atomic
```

Log out and back in, confirm `atomic available`, then enable the backend:

```bash
nbshell grid backend status
nbshell grid backend atomic
```

The recovery path only changes the next login and leaves the current session
running:

```bash
nbshell grid backend stable
nbshell grid compositor stable
```

## Prototype design

The compositor patch is intentionally small and generic. It adds an
`Actions(Vec<Action>)` IPC request, validates the complete list before making
changes, advances animations once, and executes the list in one event-loop
turn. It does not add a Hyprland layout tree or change Niri's normal behavior.

The prototype also accepts a workspace-local `SetColumnPairing` request. When
grid mode is active, the third normal tiled window starts the first pair and
each following even window completes the next pair before Niri starts the
opening animation. Windows 5, 7, and so on remain the first tile of a new
column.
This removes the brief 50% column that an external event watcher cannot avoid.
Dialogs, floating, maximized, and full-width windows remain on Niri's normal
mapping path.

This separation keeps three useful layers:

1. Niri owns window layout, rendering, focus, and animation.
2. The generic batch request provides an atomic compositor primitive.
3. nbshell owns the optional grid policy and can evolve it independently.

The first evaluation should cover three to eight windows, closing a window in
every position, opening a replacement, moving a window manually, toggling
floating/fullscreen, switching workspaces, and switching grid mode off again.
The stable backend is the recovery path if any sequence is incorrect.

## Upstream direction

Niri issue [#914](https://github.com/niri-wm/niri/issues/914) already tracks
batched actions. The prototype should therefore be treated as a proving ground
for a generic upstream contribution, not as the beginning of a permanently
divergent compositor. A full dwindle implementation would be considered only
if batch actions cannot provide the intended result.
