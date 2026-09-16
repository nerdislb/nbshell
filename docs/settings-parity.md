# Settings: main view and navigation

The settings editor is a native nbshell addition, not a pixel-identical copy of
an Omarchy settings window. Its current main view adopts the pinned Omarchy
panel language documented in [the reference map](omarchy-look-and-feel.md).

- Plain title, quiet category labels and subtle selected surfaces.
- Categories and options scroll separately; the title and Close/Back remain fixed.
- All existing options, immediate configuration writes, read/write errors,
  recovery, module arrangement and plugin management remain available.
- The editor starts in categories. Up/Down chooses a category without changing
  configuration; Enter or Right enters its options. Left/Right still changes an
  option; click/right-click and wheel retain their existing adjustment behavior.
- Tab cycles categories, options, recovery (when needed), and Close/Back.
  Shift+Tab reverses it. Escape closes standalone settings or returns to the
  main menu when embedded. An outside click closes the settings surface.
- Focus is revealed after final layout, including category changes and resizing.
  Clearing a configuration read error restores navigation from the recovery area.

This round does not redesign individual setting editors or change the custom bar.
No new shared palette, widget API or global token values were introduced.

## Checks

`tests/settings-lifecycle.py`, through `tests/wayland-lifecycle.py
--settings-contract`, runs under a private home, D-Bus and Umbriel session.
It exercises real native keyboard/pointer events and the real private Config
writer. Coverage includes independent scrolling, stable header/footer, editing,
read-only errors, recovery focus, Escape/focus return, reopening, module handoff,
and embedded menu/plugin-manager navigation. Supply `--pointer-client` as with
the other native lifecycle contracts. No host settings are modified.
