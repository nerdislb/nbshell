# Keyboard shortcuts: Omarchy alignment

Reference: Omarchy Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`,
`bin/omarchy-menu-keybindings` and `shell/plugins/menu/Menu.qml` select mode.
The upstream command requests an 800px width and a 500px list-height cap. Use
that width and a stable 500px total-card height (a deliberate native adaptation
for grouped variable-height rows and a footer), scaled by Theme.menuScale, with
the centered foreground-bordered surface, menu colors, typography and
flat rows. Native MotionSurface, TextField, ControlButton and InteractiveSurface
provide controls; no global token, custom bar or other approved-surface changes.

Keep Umbriel's Binds service/config parser, all groups and search fields (key,
description, action and group), F5 refresh and Escape-to-clear/close behavior.
Unlike the upstream command, this remains a **read-only reference**; clicking or
pressing Enter/Space never executes a listed command. No Hyprland dispatcher or
new command runner is introduced. Unknown groups are retained after the known
groups instead of silently disappearing.

Intentional native additions: real editable search, grouped list and result
count, explicit focus, visible Refresh, loading/error/empty states and footer.
Long key names and descriptions wrap; below 60 character cells of content width,
the description stacks under its shortcut. This replaces the old two-column
paginated layout with an adaptive scrolling list while retaining every binding.
Rows are keyboard-selectable for reading; groups are skipped. Arrow/Home/End/Page
navigation keeps the selected row visible. Text editing preserves native caret,
selection and clipboard behavior. Tab cycles search, refresh and selected row.
Refresh and live model replacement restore row focus only if the list owned it;
search/button focus is not stolen. Repeated F5 cannot start refresh loops.

## Verification approach

`tests/wayland-lifecycle.py --keys-contract` uses private Umbriel/home/network/
D-Bus state and inert synthetic bindings. The Binds loading boundary is controlled
by the fixture; the production parser/service is unchanged. Tests cover native
search/caret/selection/paste, all four search fields, known/custom groups, long
literal text, small-screen stacking, row/page navigation, refresh insertion and
removal, F5/button/accessibility refresh, loading/error/empty states, cancellation,
reopening and focus return. Enter/Space/accessibility only select a reference row;
no shortcut command is executed.

A first ListView implementation crashed during model replacement in the private
fixture. The shipped view instead uses the established Flickable/Column/Repeater
pattern and deferred focus resolution, with stable binding identity. Refresh
moves focus away from its button before the loading state disables it. The
status text sizes itself instead of creating an implicitHeight/height loop.

The original pinned Menu.qml select dialog was rendered unchanged on private
Umbriel with synthetic binding rows and the actual command's width/height payload.
At 1280×800 and 14px base font it measured 933×617; the native stable card measures
933×583, explicitly retaining grouped rows, refresh and a footer. This is a
visual/control adaptation, not a port of Hyprland binding discovery/dispatch.
No actual user's shortcut descriptions or desktop screenshots are archived in
the reproducible fixture evidence. The live UI is inspected separately.

External IME composition, physical multi-monitor behavior and screen-reader
operation are not separately exercised. Independent model review remains open:
Fable quota plus Sonnet, Haiku and Antigravity/Gemini timeouts already exhausted
the bounded subscription-only attempts in this alignment session; no repeated
probe loop, paid fallback or authentication changes are introduced for this round.

Final results: 39 native checks each at 1280×800/TokyoNight and
420×600/Latte/Reduced Motion (78 total), plus all 120 shared QML tests.
Design/Umbriel contracts, Python compilation, installer shell syntax and
compositor configuration validate. No QML type/reference/binding warnings remain
in the final native fixtures or checked live interval. The full text-format scan
still reports four pre-existing Omamail plugin labels (CalendarSettings:171;
SettingsPage:280/308/316), outside this scope.

Installed source is byte-identical, service active, user configuration hash
unchanged. The live view successfully loaded all 142 configured shortcuts from
the unchanged Binds service and was left open for visual acceptance.
