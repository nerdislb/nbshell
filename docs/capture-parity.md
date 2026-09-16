# Capture menu: Omarchy alignment

Scope: the standalone capture menu and its window selector. Reference: Omarchy
Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`,
`default/omarchy/omarchy-menu.jsonc` (`trigger.capture`) and
`shell/plugins/menu/Menu.qml`. Reuse the approved menu geometry and native
InteractiveSurface, MotionSurface, Line and ControlButton primitives; no new
global tokens or changes to the bar or approved main menu.

The narrow centered card, plain heading, monochrome icon slots, quiet selected
rows, foreground border and scrolling fold follow the reference. The complete
nbshell action list stays flat: screen/window/region screenshots, OCR, QR,
dictation, recording, trimming, streaming studio, editing and the output folder.
Existing direct letter shortcuts remain an intentional difference from Omarchy's
search-first capture menu. Long window titles use a wider selector and retain
full accessible labels. Window capture stays on Umbriel; no Hyprland tools or
additional capture backends are installed.

Both levels dismiss immediately, matching the approved main menu. Delayed work
belongs to CaptureService because the lazy menu is destroyed on close. Window
capture joins the existing service-owned delay, so its overlay is unmapped
before capture begins. Recording settings, helper commands and direct IPC
capture operations are unchanged.

## Interaction and verification

Stable action/window IDs bind selection and activation. Up/Down wrap, Home/End
reach list edges, Page Up/Down move six rows, and Tab follows visible controls.
Physical pointer movement aligns selection and focus; list mutations under a
stationary pointer do not override keyboard selection. Enter/Space, pointer and
accessibility activation share the same guarded path. Auto-repeat cannot launch
action chains. Right opens only the window submenu; Escape/Left return from it.
A visible Back control supports pointer-only navigation and empty window lists.
The existing IPC window entry also switches an already-open capture menu.

The explicit focus outline, footer/shortcuts, flat eleven-action list and wider
native window picker are deliberate nbshell additions. Window titles and app IDs
remain plain text, with full labels available through accessibility. Live window
changes reconcile by ID; a stale row cannot activate a different window.

`tests/wayland-lifecycle.py --capture-contract` runs on private Umbriel, home,
network and D-Bus namespaces. Each of 1280×800/dark and
800×600/light/Reduced Motion passes 38 checks. The real service-owned timer is
retained; terminal capture/app effects are replaced with exact-target recording.
The fixture verifies all existing shortcuts dispatch once after the lazy menu
is destroyed, stable selection on concurrent window arrivals/removal, stale
activation rejection, native pointer/keyboard/Tab/focus return, bounds, scrolling,
long titles, recording labels, empty state and direct-window IPC handoff.
This is a UI/dispatch proof, not a new end-to-end test of screenshot encoders,
recording hardware, OCR, QR, dictation, OBS or the existing capture helper.

All 120 shared QML tests, five security/correctness tests, design and Umbriel
contracts, Python compilation, shell syntax and compositor validation pass.
Before/after private/live UI and the archived original Omarchy main-menu
rendering were inspected; the Capture subtree itself was compared from pinned
source, not separately rendered upstream. Physical multi-monitor, exhaustive
scaling and native screen-reader operation remain outside this round.
