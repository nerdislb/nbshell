# Theme gallery

The standalone theme picker follows Omarchy's image fan at upstream commit
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`, using the native nbshell theme store,
configuration and Umbriel layer lifecycle. See `THIRD_PARTY.md` for attribution.

- Large centered preview, skewed neighboring slices, dimmed background and
  title below the fan. No additional panel frame or zoom animation.
- Type to filter by stored or human-readable theme name. Left/Right or
  Tab/Shift+Tab browse; Home/End reach the ends. Backspace edits and Ctrl+U clears.
- Enter applies. Clicking an adjacent slice selects it; clicking the selected
  preview applies it. Wheel and horizontal drag browse without applying.
- Escape first clears a search, then closes. Outside clicks close.
- Reopening selects the configured theme, with a fresh filter. Updates to the
  available list preserve the selected name rather than its numeric index.
- Supplied `preview.png/jpg/jpeg/webp/gif/bmp` files take priority in the gallery;
  otherwise it uses the existing wallpaper or a palette fallback. The separate
  `wallpaper` value and dynamic wallpaper backend are unchanged.
- On small screens the fan shrinks to leave its label and filter visible.
  Only intersecting slices allocate image/mask layers. There is no continuous
  animation; Reduced Motion follows the same immediate transitions.

The bar and its optional theme entry are unchanged. Theme installation, theme
editing and wallpaper selection remain separate surfaces. The picker does not
run Omarchy's helper scripts or change themes while merely browsing.

## Verification

`tests/theme-lifecycle.py` plugs into `tests/wayland-lifecycle.py --theme-contract`.
It uses a private HOME, D-Bus and headless Umbriel session; the apply backend is
record-only and no host themes or wallpaper settings are changed. The native
checks cover keyboard, pointer, filter/no-match, data refresh, loading guard,
reopening, focus return, single activation and output bounds. Use the RHI renderer
for the same `Shape`/`MultiEffect` masks used by the installed Wayland shell.

Example:

```sh
python tests/wayland-lifecycle.py \
  --compositor "$HOME/.local/bin/umbriel" --render-node /dev/dri/renderD128 \
  --output /tmp/theme-gallery-test --cycles 1 --settle-seconds 0 \
  --width 800 --height 600 --theme catppuccin-latte --motion reduced \
  --qt-backend rhi --theme-contract --pointer-client /path/to/pointer-client
```

Native AT-SPI/screen-reader behavior, touch hardware and exhaustive multi-monitor
configurations require separate validation; passing keyboard tests is not a
claim that these are covered.
