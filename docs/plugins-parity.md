# Plugin manager presentation

The pinned Omarchy tree has no identical nbshell installed/store/porting manager.
This is a native adaptation of the approved settings and panel language, not a
claim of pixel-identical upstream UI. Follow [the reference map](omarchy-look-and-feel.md).

A plain heading, separate unframed search, quiet two-line list rows and a flat
split view replace accent markers and overlapping three-line summaries. Full
descriptions remain in the independently scrollable detail pane. Action buttons
wrap, keyboard focus reveals them, and a fixed Close action remains reachable.
The existing Porting Lab content and confirmation modal are retained.

- Search and Up/Down select without executing plugins; a row click selects only.
- Tab traverses tabs, search, the selected row, detail actions and Close.
- Alt+1/2/3 switches sections. F5 refreshes. Enter in search retains the existing
  primary-action shortcut; it is blocked while busy or confirming another action.
- Escape first cancels confirmation, then clears search, then closes.
- Installed/store data, enable controls, source links, update preview, confirmation,
  uninstall protection and Porting Lab behavior remain available. Not-installed
  store entries expose no Remove action and report their state accurately.
- Update diffs scroll inside confirmation, leaving Cancel/Confirm visible.
  Arrow/Page keys scroll the preview without moving the underlying selection.
- No plugin host, backend, catalog, bar layout or user configuration is migrated.

`tests/plugins-lifecycle.py` uses a private Wayland session, synthetic plugin
metadata and no executable plugin entries. Install/update/remove commands are
intercepted in the disposable UI copy. Native mouse and keyboard checks validate
scrolling, action focus, confirmation/cancel, search, tab switching, empty/error
states, closing and focus return. They do not prove external download/install
success; existing plugin backend tests cover its separate contract.
