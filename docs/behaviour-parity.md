# Behaviour parity with the pinned Omarchy reference

The look-and-feel work is tracked in [omarchy-look-and-feel.md](omarchy-look-and-feel.md)
and the porting procedure in [ui-porting.md](ui-porting.md). This note covers
**behaviour**: input, dismissal, lifecycle and compositor integration.

It was produced by comparing the pinned reference
(`6ea3215542fbb269dfe5c2be928e6144f9cb6466`, 2026-09-15) with nbshell, source
against source, in two independent passes — input/dismissal and
lifecycle/compositor — plus a direct pass over the layer rules. The pin was
fetched directly for this work; the two local research checkouts are older
shallow clones and were not used as evidence.

## Verified parity

| Area | Behaviour |
|---|---|
| Escape order in menu, launcher, emoji, clipboard and activity | confirmation → search → close, as upstream |
| Pointer motion selects; filtering or scrolling does not steal the keyboard selection | same |
| Wrapping arrow selection in menu, launcher and emoji | same |
| Launcher search failure | upstream does nothing, nbshell runs the input as a shell command — a documented addition in [menu-parity.md](menu-parity.md) |
| Toast lifetime | low 5 s, normal 8 s, critical until closed, sender timeout only extends, hover pauses, a replacement restarts the clock — all matching |
| Layer level | bar top, menus and popups overlay, wallpaper background — as upstream |
| Exclusion and input mask on overlays | `Ignore` throughout; toasts and OSD unfocused with a mask — as upstream |
| Panel residency | upstream keeps first-party panels loaded, nbshell loads them on demand — a documented memory decision |

## Divergences fixed

- **Compositor blur behind full-screen overlays.** The layer rules blurred
  everything under `nbshell:` and switched blur off for the namespaces somebody
  had remembered; the launcher was missing, so opening Apps showed a blurred
  wallpaper instead of the dimmed workspace. The rules are now explicit in both
  directions. Worth recording: the reference has **no blur at all** —
  `decoration.blur.enabled = false` and not a single blur layer rule. Our
  frosted bar popouts are an nbshell invention that runs against the pin.
- **Auto-repeat satisfied the second activation.** Launcher, KdeConnect, Todo
  and Plugin Developer called their action directly on Enter without the
  `isAutoRepeat` guard the shared primitives have always used, so holding the
  key ran Logout, Reboot and Shut down without a deliberate second press.
- **Critical toasts were evicted by the stack cap.** Five harmless toasts
  released a critical warning, contradicting the contract stated in
  `Notifications/Popups.qml`. Critical entries are now exempt from the limit.

## Divergences closed in the follow-up

| # | Was | Now |
|---|---|---|
| 2 | A popout closed 2500 ms after the pointer left even while the keyboard was in use | The leave timer stands down while a control inside holds focus |
| 3 | Submenu search filtered direct children; the root search capped at five apps and seven actions | The whole subtree is searched; the caps are gone (the list scrolls and `maxRowsHeight` bounds it) |
| 4 | Idle lock at 900 s, behind the 600 s screen-off | 300 s, the reference value; the lock now precedes the screen-off |
| 5 | `focus_on_activate` unset, so Umbriel's `false` applied | Set to `true` as the reference does |
| 8 | OSD 2000 ms | 1200 ms, the reference value |
| 9 | Audio and network wrapped, the clipboard bound | Each matches its counterpart: panels bound, the clipboard wraps |
| 10 | `Ctrl+U` / `Ctrl+Backspace` did nothing useful in the menu | `Util.editsFilter`/`editedFilter` are wired in; Backspace on an empty filter still returns a level |
| 1a | Toasts and the OSD appeared with no transition | Both use `MotionSurface`, so they fade in from the shared motion tokens and honour Reduced Motion |
| 1b | Toasts disappeared the instant their lifetime ended | An entry that leaves the model stays in the host list for `Theme.motionExit` flagged `_closing`; the card stands opaque and runs `MotionSurface.dismiss()`, and a timer drops the flagged entries so no ghost cards remain |

## Still open

| # | Severity | Divergence | Why it is still open |
|---|---|---|---|
| 6 | medium — open, diagnosis corrected | A click on bare background does not dismiss a bar popout; a click on a window does | **My earlier "the compositor is not the cause" was not supported by its evidence, and is withdrawn.** The check that settled it — `515_popup_focus` — clicks bare background with the harness client's popup, whose grab is a real xdg-popup grab created from an input event; wlroots dismisses that by itself. It cannot represent a nbshell popout, so passing with *and* without the candidate patch proved nothing about this case, and the candidate patch was also scoped too narrowly (`surface == nullptr` only, while the press may land on nbshell's full-screen wallpaper layer surface). What the live behaviour tells us: a window click dismisses (Umbriel's `View::raiseToTop` ends the keyboard grab), a background click does not — so the popout holds a keyboard grab but **no pointer/popup grab** for wlroots to route the click through. Two ways out, both needing a decision: patch Umbriel to end the keyboard grab on any press that does not land on the grabbing popup's own surface (`isXdgPopupSurface` already exists as the discriminator), or give the shell a full-screen dismiss surface as the reference does. Reproducing it in the harness means mapping a popup **without** an input serial |
| 7 | medium | No per-monitor screensaver: one window starts, the other outputs keep the desktop | Feasible now, but not verifiable here. Umbriel's `WindowRule` has `defaultOutput` (TOML key `output`), so the shape is: launch one process per output with a per-output window title, and let a generated rule place each on its output — `ThemeExport` already writes the per-output config. Two reasons it is not done: it needs a title convention, N tracked processes and generated rules, and **this machine has a single output (`eDP-1`)**, so multi-monitor placement cannot be observed. It needs a machine or VM with two outputs |
| 7 | medium | No per-monitor screensaver: one window starts, the other outputs keep the desktop | Feasible now, but not verifiable here. Umbriel's `WindowRule` has `defaultOutput` (TOML key `output`), so the shape is: launch one process per output with a per-output window title, and let a generated rule place each on its output — `ThemeExport` already writes the per-output config. Two reasons it is not done: it needs a title convention, N tracked processes and generated rules, and **this machine has a single output (`eDP-1`)**, so multi-monitor placement cannot be observed. It needs a machine or VM with two outputs |
| 1b | — | **Closed.** Toasts fade out again | The OSD does too: its window stays mapped for `Theme.motionExit` while the surface dismisses, and a re-show cancels that. `PowerMenu` already animated through `MotionSurface`. The only surface left in that finding is the lock preview, which lives in the separate lock shell — see the note under this table |

Two more need a live probe rather than a code read: whether Umbriel reports
activity when the screensaver window maps (the reference guards that with a 3 s
grace period), and whether moving a monitor misplaces long-lived layer surfaces
(the reference remaps them through `ScreenMoveRemap`).

## Constraint behind #1

Umbriel's `LayerRule` carries only `blur`, `blurPopups`, `ignoreAlpha` and
`optimized` — there is **no per-rule animation switch**, so the reference's
`no_anim` cannot be reproduced. Layer animation is all-or-nothing.

Because the bar and the full-screen overlays animate themselves in QML, the
global "off" is currently the only way to keep them instant. That is why the
fix went into QML instead: the surfaces that should fade now do it themselves.
**Window open and close animations are a different group** — Umbriel gates
`animation.windows_in`/`windows_out` separately from `animation.layers`, so the
window popin and fade are untouched by any of this.

#1b is complete for the surfaces that matter: `Popups.qml` holds a removed
entry for `Theme.motionExit` and calls `MotionSurface.dismiss()` before the
delegate goes away, and the OSD window stays mapped for the same interval while
its surface dismisses. The one surface still without a transition is the lock
preview, which runs inside the separate lock shell; giving it one means the same
delayed-unmap treatment in `shell/lock/shell.qml`.
