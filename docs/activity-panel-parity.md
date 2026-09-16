# Activity panel: Omarchy alignment

The combined notification/clipboard bar popout uses Omarchy Quattro's clipboard
list/preview composition, reference `6ea3215542fbb269dfe5c2be928e6144f9cb6466`:
875 × 600 font-relative outer size, 18 px padding, 50 px rows, 50/50 split,
plain search header, flat selected row and faint preview separator. The frame
clamps to the current output and the shared Popout content-height budget.

## Retained nbshell behavior

The bar/island/pill, bar hover preview, direct notify/clipboard IPC flags,
notification history and full Notification Center stay. This is a bar-anchored
combined panel, not Omarchy's centered clipboard overlay; the notification tab,
DND, explicit actions, footer and scrolling full preview are intentional extras.
Omarchy does not supply an equivalent combined notification-history popout.

Both tabs have search, stable-key selection and a full text/image preview.
All stored clipboard entries are reachable (previous UI caps were 8 images and
30 text rows). Storage limits, secret filtering, capture watchers and notification
persistence remain unchanged. The only service change exposes image-removal
busy state and rejects overlapping removals on its existing single Process.
Clearing from this panel is also blocked while an image removal is running.

- Down from search enters the **current** row; subsequent Up/Down navigates.
  Home/End reaches the first/last item. Navigation does not activate content.
- Enter or left click copies a clipboard item or focuses the notification's app,
  then closes. This preserves the old history app-focus behavior; it does not
  substitute a notification's default action.
- Delete, right click or the separate Remove/Dismiss action removes only that
  item. These paths never also copy/open. Clear requires a second activation,
  expires after three seconds and is cancelled on tab switch or Escape.
- Escape cancels an armed clear first, then clears a search, then closes.
- Tab reaches the full preview; arrows/Page Up/Page Down scroll it. Qt text
  editing remains native in the search field. No private selection-index lookup
  can redirect activation after concurrent additions.
- Notification source, date, repetition and urgent indication remain visible;
  all content is plain text. Image rows use local clipboard paths only.

## Verification

`tests/wayland-lifecycle.py --activity-contract` uses a private headless Umbriel
seat, private home and D-Bus, fake clipboard data and action capture. The actual
image-removal Process runs against a private fixture helper. It never reads,
copies or clears the real user's clipboard or notifications.

The native input contract checks all 57 stored fixture rows, initial search
focus, output/footer fit, End/Delete without Copy, typing and Escape filtering,
long-preview scrolling, two-step clear/cancel/tab-switch, focus return to a real
underlying window, stable geometry/IPC flags, notification filtering, DND,
concurrent prepend selection, exclusive removal, image busy rejection, exact
text/image copy and empty state. Each final run passes 25 checks:
1920 × 1080 dark/standard and 800 × 600 light/Reduced Motion. The shared QML suite
passes 120 tests. The original Omarchy clipboard was separately rendered with
the same font/theme for comparison.

Native AT-SPI/screen-reader use, exhaustive multi-output and bottom-bar cases,
real user clipboard payloads and every image decoder are not claimed verified.
The full Notification Center and passive toast cards are outside this round.
