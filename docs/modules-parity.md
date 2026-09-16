# Bar module arrangement

This editor is a preserved nbshell addition. Omarchy's pinned bar reference
configures layout mainly through bar gestures and CLI; there is no identical
upstream editor. See [the design reference](omarchy-look-and-feel.md).

The main settings panel's plain title, quiet selected surfaces and flat layout
are used here, while the editor remains top-docked near the bar. Configured
modules and the catalogue scroll independently. The four groups remain:
collapsed island, left, center and right. The collapsed island list is separate
from the normal bar layout, so a widget may legitimately appear in both.

- Up/Down selects without saving. Left/Right reorders within the current group.
- Shift+Left/Right moves between groups; Delete or X removes a placement.
- Tab cycles layout, available modules and Close; Shift+Tab reverses it.
- Enter on an empty group enters Available. Enter/click in the catalogue adds
  a module or selects its existing bar placement. Separators remain repeatable.
- Drag a row within a group or onto a group's heading to move it. Releasing
  outside a drop target cancels the drag.
- Escape, Close and outside click dismiss the editor. Hints wrap on small outputs.
- Invalid configuration blocks changes and drag initiation. Config read/write
  errors remain visible. Group moves keep the existing atomic Config.setValues
  transaction; no bar engine, defaults or user layout are changed by installation.

`tests/modules-lifecycle.py`, via `tests/wayland-lifecycle.py --modules-contract`,
uses private configuration and a native virtual pointer/keyboard. It checks real
reorder/drag/cancel, cross-group disk writes, repeat separators, independent
island placement, long catalogues, empty lists, error guards, focus and closing.
It never changes the host's bar layout.
