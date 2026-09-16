# Notification toasts: Omarchy alignment

The passive notification cards follow Omarchy Quattro reference
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`: font-relative 380 px width,
2 px border, 12/10 px content insets, local app icon or glyph, bold title,
three-line body and a close control revealed on hover. Body-less messages
use compact vertical padding. Liberation Sans is scoped to toast titles/bodies,
as in the reference; the rest of nbshell keeps its existing typography.

Source, age, repetition and full notification information remain in history
and accessibility descriptions, instead of a separate toast header. The
searchable center, bar notification/clipboard panel, DND, actions, persistence,
critical lifetime and bar/island/pill are not redesigned by this round.

## Preserved behavior and intentional differences

- Toasts never request keyboard focus. Keyboard interaction remains in history.
- Left click uses the existing default action/window-focus behavior. Right click
  or the hover close control dismisses only the toast; history is retained.
  Parent/child tap handlers explicitly exclude the close hit box from activation.
- Hover pauses the service-owned timeout, including replacement notifications.
  Same-key updates refresh existing delegates rather than recreating the array
  model's entire view; clicks resolve the current live entry by key.
- Critical notifications keep nbshell's visible warning border and explicit
  dismissal. Existing sender timeouts, DND and multi-output lifetime accounting
  remain in the unchanged Notify service.
- Both title and body stay plain text. No remote icon fetches, markup adoption,
  new image cache or new notification daemon. Missing images use a known glyph
  when available, otherwise omit the icon slot.
- Existing top/bottom placement and bounded stack remain; overflow opens full
  history. We retain the narrow input surface, not Omarchy's full-screen masked
  notification layer, whose input assumptions differ under Umbriel.

## Verification

`tests/wayland-lifecycle.py --notification-contract` runs real notification
D-Bus messages on a private headless Umbriel seat. It verifies local/missing/
remote icons, compact and long cards, actual hover during twenty replacements,
expiry after leaving, replacement default actions, exclusive close-button
activation, right-click dismissal, bounded burst/history, restart snapshots and
server-ID reuse, output fit, passive typing focus, history Tab/Escape and focus
return, plus overflow accounting and history activation where overflow applies.

Dark/standard and small light/Reduced Motion renders are compared with a
separate rendering of the original reference component. A bottom-corner run
also checks the existing placement override. No test messages or clears from
this suite reach the real desktop notification history.

Installed runtime matches the source and the user configuration is unchanged.
Transient real-desktop test cards were inspected with and without a local
`appIcon`; no existing notifications were cleared. Image/thumbnail hints are
not newly captured by this round: the existing Notify snapshot supplies
`appIcon` and known-source glyphs, not Omarchy's separate avatar/image cache.
A native screen-reader and exhaustive boundary-pixel touch testing remain out
of scope; the tested close-button click targets its center.
