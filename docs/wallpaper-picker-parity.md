# Wallpaper picker

Open **Wallpaper** from the menu or double-click an empty desktop. The picker
uses Omarchy's image-fan geometry, with nbshell's collections, dynamic wallpaper
settings and per-theme overrides retained. It rescans wallpaper folders on
every opening; no persistent discovery cache is introduced.

## Controls

- Left/Right or Tab/Shift+Tab: browse. Home/End: first/last result.
- Wheel, drag, or click a neighboring slice: browse without saving.
- Type to filter filenames and theme names; Backspace edits, Ctrl+U clears.
- Enter or click the selected image: save it for the current theme.
- Escape: clear the search first, then close. Clicking outside also closes.
- F6: move focus between the image fan and options; Tab traverses options.
- Ctrl+D: dynamic settings. Ctrl+R: restore the current theme's default.

**Current theme / All themes** changes the collection and remembers that choice.
**Desktop preview** temporarily shows the highlighted image on the desktop; it
is off by default and never persists. Closing, opening dynamic settings, or an
external theme change clears it. Video playback pauses during preview; daytime
and video assignments are not modified.

Applying writes the override and current theme's mapping together. Reset removes
only that theme's mapping. The picker waits for the configuration write to
finish; rejection leaves it open with an error and blocks duplicate submissions
while a write is pending. Browsing and cancelling do not change wallpaper state.

## Verification

The native contract uses a private home, configuration writer and fixture images:

```sh
python tests/wayland-lifecycle.py --compositor /path/to/umbriel \
  --render-node /dev/dri/renderD128 --output /tmp/wallpaper-picker-check \
  --cycles 1 --settle-seconds 0 --qt-backend rhi --wallpaper-contract \
  --pointer-client /path/to/umbriel/pointer-client
```

It checks keyboard and pointer selection, filtering, model updates, temporary
preview, settings return, cancellation, atomic disk writes, delayed write
failure, reset, empty states and focus return. Keep its virtual keyboard attached
across pointer/reopening checks to avoid testing keyboard hot-unplug instead of
picker focus. The separate `tests/wayland-wallpaper.py` covers actual video
playback, lock cycles and workspace gating.
