# Menu and launcher: Omarchy alignment

The main menu and launcher follow the default Omarchy Quattro menu presentation
at upstream commit `6ea3215542fbb269dfe5c2be928e6144f9cb6466`. nbshell keeps its
own menu actions, launcher providers and Umbriel integration. This is not a
replacement of the shell or a promise that every Omarchy theme override is
supported.

## Presentation

Both surfaces use the same scoped Theme menu tokens: a narrow centered card,
plain search heading, foreground border, quiet selection fill, monochrome menu
icons, and consistent row typography. Descriptions appear while searching;
full descriptions remain in the accessible labels. The card's top edge stays
in place after the first search or submenu change. Long lists scroll with a
partial row at the fold. Opening and selecting have no decorative zoom.

The user's configured font, font size, palette and corner radius remain in
use. The bar, island, pill, dashboard, embedded settings and other panels retain
their existing appearance. Our extra menu categories remain, so card height
and content need not match Omarchy's different list of categories.

## Navigation

- Type to search; **Up/Down** wrap through results, **Page Up/Down** move six rows.
- **Enter** opens the selected action. The main menu also accepts **Right**.
- **Escape** clears the search first, then closes the surface. In the main menu,
  **Left/Backspace** with an empty search returns to the parent category.
- Pointer motion selects a row. Merely filtering or scrolling rows beneath a
  stationary pointer does not take selection away from the keyboard.
- The launcher retains **Ctrl+N/P**, native text editing and search prefixes:
  `>` commands, `!` applications, `#` windows, `^` clipboard, `@` files and `=`
  calculator. Empty-result command execution is retained with a visible hint.
- Commands marked for confirmation still need a second Enter. Escape dismisses
  that confirmation before clearing the search or closing the launcher.

## Verification

`tests/menu-lifecycle.py`, used by `tests/wayland-lifecycle.py --menu-contract`,
exercises real surfaces in a private Wayland/D-Bus/network namespace. It checks
bounds, scrolling, keyboard focus return, wrapped selection, pinned search
geometry, all launcher prefixes and cancellation of guarded commands. No test
sends keys to the user's session or runs a destructive command.

Original-source rendering establishes the baseline geometry and default style;
an end-to-end comparison on a separate Hyprland/Omarchy installation remains
useful for compositor effects and theme-specific overrides.
