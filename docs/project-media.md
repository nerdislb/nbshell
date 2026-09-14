# Project media checklist

Release screenshots and videos must use neutral sample data. Do not capture
mail addresses, private notifications, clipboard contents, calendar URLs,
network addresses, API usage, device names, or browser profiles.

Use nbshell's own name and visual identity. Do not include Omarchy logos,
upstream preview images, or third-party wallpapers without explicit
redistribution permission. Captions should describe nbshell as independent and
Omarchy-inspired, never as an official edition, port, or 1:1 clone.

Recommended release set:

1. Full desktop with the current Umbriel menu and a bundled neutral wallpaper.
2. Library wallpaper and theme views with no local filenames visible.
3. Quick Notes containing synthetic text only.
4. Umbriel overview or display controls using neutral windows and sanitized output labels.
5. UI Gallery, Calculator, Plugin Manager, or Capture Menu without account-backed content.

Do not publish live account-backed Mail, WhatsApp, notification, clipboard,
terminal, Agent Center, AI usage, network/device, calendar, task, browser,
greeter, or lock-screen captures. Work Desk may be shown only from an isolated
session with fully synthetic fixtures and an explicit demo-data caption; this
exception is not permission to use a live account snapshot. Keep original captures outside Git. Add metadata-stripped WebP files
below `docs/assets/` only after OCR and full-pixel privacy review. A 16:9 overview
and three focused UI views are enough; avoid an oversized gallery.


## Current gallery · 2026-09-14

The README gallery is rendered from real nbshell QML in a disposable Umbriel
headless session, using `tools/capture-project-media.py`. The host home directory,
network and system D-Bus are not available to the capture process. Session,
project, activity, quota and machine values are injected as synthetic fixtures
in the disposable source copy; production QML and the live desktop are unchanged.
These images illustrate UI, not performance or supported-provider benchmarks.

- `assets/nbshell-work-desk.webp`: nbdark Work Desk, synthetic data.
- `assets/nbshell-work-desk-light.webp`: nblight Work Desk, synthetic data.
- `assets/nbshell-umbriel-menu.webp`: current searchable menu, no account data.
- `assets/nbshell-library.webp`: current Library with bundled themes.

The captures use the owner-contributed `nbdark/1.webp` and `nblight/1.webp`
wallpapers; the Library also previews bundled `catppuccin-latte` artwork. See [theme attribution](https://github.com/nerdislb/nbshell/blob/main/themes/ATTRIBUTION.md) and
[wallpaper provenance](https://github.com/nerdislb/nbshell/blob/main/wallpapers/MIDJOURNEY-PROVENANCE.md). The images are
metadata-free WebP conversions of real captures, not generated UI mockups.
Full-resolution originals remain outside Git. OCR and visual inspection precede
publication. Older launcher/UI Gallery assets remain available but are not the
current README's headline screenshots.

Example (paths point to your installed tools):

```sh
python3 tools/capture-project-media.py \
  --quickshell /usr/bin/quickshell --compositor /path/to/umbriel \
  --render-node /dev/dri/renderD128 --theme nbdark \
  --screenshots /tmp/nbshell-public-dark
```

Use `--theme nblight` and a new output directory for the light set. Capture output
is not automatically copied, committed, or uploaded.
