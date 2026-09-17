# Session menu: Omarchy alignment

Scope: standalone `Power/PowerMenu.qml`, not the battery/profile panel.
Reference: Omarchy Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`,
`default/omarchy/omarchy-menu.jsonc` (`system.*`) and `shell/plugins/menu/Menu.qml`.
Use the approved menu's narrow centered frame, monochrome icons, flat rows,
foreground border and Theme.menu metrics. Reuse InteractiveSurface, Line,
MotionSurface and FocusScroll; no global token or bar changes.

Native additions retained: six actions in their existing order (Lock, Log out,
Suspend, Hibernate, Restart, Power off), S/A/B/R/N/X shortcuts, explicit focus,
footer and two-step confirmation with the existing 3.5-second expiry. No new
search field or screensaver action; no Omarchy/Hyprland backend commands.
Session.qml and the lock/suspend wrapper remain unchanged. The menu dismisses
immediately like the approved main menu, keeping its MotionLoader handoff.

Pointer, Enter/Space and accessibility use one ID-based guarded activation path.
Held keys cannot confirm, and selection changes/closing clear the armed state.
Up/Down wrap, Tab follows rows, Home/End and Page keys keep the focused row in
view. Long labels elide with full accessible names; the footer reserves its
maximum height so confirmation does not shift rows under a stationary pointer.

## Verification

`tests/wayland-lifecycle.py --session-contract` runs the real menu, confirmation
expiry and MotionLoader with private Umbriel, home, network and D-Bus namespaces. Only
the Session.run effects boundary is replaced with exact-ID recording. The
fixture covers all six shortcuts, two-step pointer/Enter/Space/accessibility
activation, physical held keys and synthetic autorepeat, timeout, Escape,
outside-click and IPC cancellation, reopen, focus return, navigation, bounds
and long literal labels. It asserts one dispatch after the close request, not
that Session.run waits for destruction of the window tree.

Before/after UI and the archived original Omarchy main-menu rendering are
compared visually. The System subtree is sourced from the pinned menu definition,
not a separately rendered upstream System menu. Dark 1280×800 and light
800×480/Reduced Motion exercise ordinary and scrolling layouts. The partial row
at the fold matches the shared menu convention; focused rows are revealed fully.
No real lock, logout, suspend, hibernate, reboot or shutdown is performed. This
is not a new logind/PAM/hardware or physical multi-monitor/screen-reader proof.

Both native configurations pass 45 checks each (90 total); all 120 shared QML
tests and five security/correctness tests pass. Design/Umbriel contracts, Python
compilation, installer shell syntax and compositor configuration validate.
The full text-format scan still reports four pre-existing Omamail plugin labels
(CalendarSettings:171 and SettingsPage:280/308/316); no changed core label fails.

Installed source matches the repository; service active, user configuration
hash unchanged, live initial menu inspected with no QML type/binding errors in
the checked journal interval. Independent review remains unavailable: Sonnet
65-second timeout and Gemini 3.8 Flash High 65-second timeout/empty response.
No independent approval is claimed and no paid fallback was enabled.
