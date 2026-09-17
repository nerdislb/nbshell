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

## Open divergences

| # | Severity | Divergence | Where |
|---|---|---|---|
| 1 | high | Layer animations are globally **off**. The reference has them on and disables them only for the bar and its keyboard-driven panels, so toasts, OSD, polkit and the power/lock previews pop hard here and fade there. | `umbriel/nbshell-motion.toml` |
| 2 | medium | A click popout closes 2500 ms after the pointer leaves even while the keyboard is in use. The reference's click panels stay open on pointer leave. | `shell/Widgets/Cell.qml`, `Popout.qml` |
| 3 | medium | The main menu searches less than the reference: submenus filter direct children only, and the root search caps at five applications plus seven actions. Upstream walks every descendant with no cap, so existing actions stay unreachable through the same search. | `shell/Menu/Menu.qml` |
| 4 | medium | Idle: screensaver 180 s, dim 240 s, screen off 600 s, lock 900 s. The reference locks at 300 s. Between 600 s and 900 s the machine is dark but unlocked. | `shell/Services/Idle.qml` |
| 5 | medium | `focus_on_activate` is unset, so Umbriel's default `false` applies where the reference sets `true`. Compensated by a per-window `default_focused` list that does not cover third-party applications. | `umbriel/nbshell.toml` |
| 6 | medium | Click-outside is not equivalent: a background with no client surface does not dismiss, where the reference has explicit full-screen dismiss surfaces. | documented in [bluetooth-parity.md](bluetooth-parity.md) |
| 7 | medium | No per-monitor screensaver. One window starts; the other outputs keep showing the desktop, where the reference starts one per monitor. | `shell/Services/Idle.qml` |
| 8 | low | OSD lifetime is 2000 ms; the reference uses 1200 ms and allows a per-call override. | `shell/Services/Osd.qml` |
| 9 | low | Arrow navigation wraps in audio and network but stops at the ends in the clipboard. The two nbshell behaviours also disagree with each other. | `AudioPanel`, `NetworkPanel`, `ActivityPanel` |
| 10 | low | `Ctrl+U` and `Ctrl+Backspace` do nothing useful in the main menu; upstream clears the search and deletes a word. `Util.editsFilter` and `editedFilter` are already ported for exactly this and are unused there. | `shell/Menu/Menu.qml` |

Two more need a live probe rather than a code read: whether Umbriel reports
activity when the screensaver window maps (the reference guards that with a 3 s
grace period), and whether moving a monitor misplaces long-lived layer surfaces
(the reference remaps them through `ScreenMoveRemap`).

## Constraint found while acting on #1

Umbriel's `LayerRule` carries only `blur`, `blurPopups`, `ignoreAlpha` and
`optimized` — there is **no per-rule animation switch**, so the reference's
`no_anim` cannot be reproduced. Layer animation is all-or-nothing.

Because the bar and the full-screen overlays animate themselves in QML, the
global "off" is currently the only way to keep them instant. The price is that
toasts, OSD and polkit do not fade. Fixing #1 therefore means adding the fade in
QML with the shared motion tokens — which also brings those surfaces under
Reduced Motion, where they currently have nothing to reduce.
