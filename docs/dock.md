# Optional auto-hide dock

The dock is an opt-in native surface, not a replacement for the bar. Enable it
in **Settings → DOCK → Enable auto-hide dock**. It appears when the pointer
rests at the center of the bottom screen edge and hides after the pointer leaves.
If the bar is at the bottom, the dock uses the top edge instead. No window space
is reserved. Disabling it unloads its windows and edge input regions immediately.
App-name hover captions are intentionally omitted; accessible names remain available.

**Settings → DOCK** also provides independent **Dock size** (75–200%) and
**Icon size** (50–200%) sliders. Both default to 100%. Dragging updates the actual
dock immediately; values persist on release. Arrow keys and the mouse wheel adjust
by five percentage points. The dock grows enough to fit larger icons without clipping.
While this category is open, the enabled dock is a passive, click-through preview
on the focused output; closing settings or switching categories restores auto-hide.
Adjusting sizes while disabled never enables the dock. The top bar is unchanged.

Click an app to launch or focus it; multiple windows open a chooser. Right-click
an app for windows, pin/unpin, new-instance and **Close** actions. Running groups
with multiple windows offer **Close all windows**. Closing sends normal window
close requests (no force-kill), allowing the app to ask about unsaved changes.
The menu releases keyboard focus first. Non-running pins have no close action.
Pinned apps persist by
desktop-entry ID. The launcher button remains available even with no windows or
pins. Long docks scroll horizontally. `nbshell dock show` opens the dock for
keyboard use; Tab navigates, Menu opens app actions, and Escape dismisses it.
`nbshell dock on|off|toggle|hide|status` controls the same optional feature.

## Design reference and deliberate scope

Omarchy Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`, panel/menu language
(`shell/plugins/menu/`, `shell/Ui/`), and the approved nbshell settings are the
references. There is no exact upstream dock surface in the pinned reference map.
Reuse native PanelSurface, PanelRow, InteractiveSurface, Theme geometry and motion.
The size controls reuse the existing `Ui.PanelSlider`, hosted in native settings
rows; there is no separate native slider primitive. Colors come from Theme.
App icons are intentional domain content. Preserve the custom bar and all approved
surfaces. No magnification, thumbnails, drag reordering or new global design tokens.

The dock runs on each output, with the same global pinned/running app groups.
Fullscreen suppression uses activated foreign toplevels on that output, not an
app-ID join with Umbriel IPC. The IPC remains authoritative for window selection.
Unknown app IDs retain a focusable fallback; ambiguous matches are not guessed.

## Verification

Verified on 2026-09-17:

- `tests/qml.sh`: 120 QML tests passed, plus its Python contract checks.
- `node tests/dock-model.test.js`: desktop IDs, StartupWMClass, ambiguous aliases,
  duplicate pins, multi-window groups and unknown IDs.
- `tests/wayland-dock.py`: real isolated Umbriel/Quickshell, dark 1280×720 and
  light/Reduced Motion 640×480. Hidden start, edge reveal, leave hide, hidden input
  passthrough, pointer context menu, keyboard chooser/pinning/Escape, fullscreen,
  enable/disable surface destruction, persistence and bottom-bar/top-dock behavior.
  Real settings sliders additionally verify independent sizing, live unsaved drag
  state, save-on-release, keyboard stepping, passive preview, auto-hide afterward
  and sizing while the dock remains disabled.
  Context-menu checks cover Close for one window, Close all windows for a group,
  focus release, retained pins and no close action on non-running pins.
- `tests/cli-consistency.py`, text-format contracts, `bash -n` and `umbriel validate`.
- Installed with `./install.sh`; the running desktop's edge reveal/leave and the
  actual Settings switch were exercised. Screenshots inspected for settings,
  dock and chooser. The dock is enabled locally; the shipped default remains off.

Evidence: `/tmp/nbshell-dock-evidence-dark-final/`,
`/tmp/nbshell-dock-evidence-light-small-final/`, and
`/tmp/nbshell-dock-live-{shown,hidden}.png` / `nbshell-dock-settings.png`.
Size-control evidence: `/tmp/nbshell-dock-size-controls/`,
`/tmp/nbshell-dock-size-small/`, and live desktop screenshots
`/tmp/nbshell-dock-size-live-{dockScale,dockIconScale}.png`.
Close-action evidence: `/tmp/nbshell-dock-close-dark4/`,
`/tmp/nbshell-dock-close-light3/`, `/tmp/nbshell-dock-close-live-menu.png`.
A disposable Foot window was closed through the installed context menu by pointer.
Physical multi-monitor hotplug/fractional scaling and long-duration use remain
unverified. Full independent code review is open: Claude Sonnet and Antigravity
Gemini Pro/Flash review attempts timed out. Gemini Pro returned only an architecture
risk check, not approval of the final code.
