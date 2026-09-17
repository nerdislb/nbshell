# Notification Center: Omarchy alignment

Scope: the separate full Notification Center, not the approved Activity popout
or passive toasts. Reference: Omarchy Quattro
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`, `shell/plugins/notifications/Service.qml`,
`components/NotificationCard.qml`, and `shell/plugins/clipboard/Clipboard.qml`.
At this revision history is replayed as toasts; there is no complete searchable
Notification Center to copy. This is an intentional nbshell extension, using
Omarchy's centered history panel and notification content hierarchy.

Reuse the existing activity panel geometry/padding, menu selection and shared
native text fields, action controls, overlay/motion lifecycle. Keep a single
scrolling notification list with source, time, repetition, urgency, app icons,
Open, live actions and Dismiss. Monospace typography and persistent actions are
intentional differences from passive upstream toasts. No bar, Activity panel,
toast, notification service or storage policy changes.

**Amended 2026-09-17:** the claim that no shared token changes is superseded.
`Theme.selectedSurface()` and `Theme.hover` moved to the pinned reference's
values, which reaches this panel's DND and Clear-all chips through
`ControlButton`. The DND chip carries its state in its label ("DND on"), so
the neutral wash costs no meaning there; see [ui-porting.md](ui-porting.md).

Native search preserves ordinary text editing; list shortcuts do not consume
search letters. Selection follows stable notification keys during new arrivals.
Clear all retains two-step confirmation; Escape cancels it before clearing the
query or closing the center. All content stays plain text and icons local-only.

Verification results are recorded after implementation below.

## Verified behavior

`tests/wayland-lifecycle.py --notification-center-contract` uses a private
Umbriel seat, private home and D-Bus. Thirty checks pass at 1280×800/dark and
800×600/light/Reduced Motion. No user notifications, clipboard or settings are
read or cleared by the fixture. The real Notify methods run against synthetic
history and live-action objects; only app focus is intercepted for exact-target
assertions. Search, native editing, stable-key selection, End/Delete, selected
row Tab actions, long custom-action focus visibility, DND, confirmation timeout,
Escape cancellation, default/custom actions, outside click and focus return are
exercised. All 120 shared QML tests pass; design contracts and diff checks pass.
Before/after were inspected in running private Wayland sessions; the previously
rendered pinned Omarchy clipboard reference was also inspected. No original
Notification Center rendering exists to compare. Physical multi-monitor,
exhaustive scaling and screen-reader interaction are not claimed verified.

The repository-wide plain-text check has four pre-existing failures in
`plugins/omamail/ui/components/{CalendarSettings,SettingsPage}.qml`. The changed
notification files use the shared plain-text Line control and add no exceptions.
Loading/error states do not apply to this synchronous view of Notify.history;
empty history, no matches, urgent and disabled Clear states are covered.
