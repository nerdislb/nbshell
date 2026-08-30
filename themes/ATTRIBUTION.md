# Theme attribution

Except for Hermarchy, the `colors.toml` files in this directory come from
<https://github.com/basecamp/omarchy>. They are MIT-licensed, Copyright (c)
David Heinemeier Hansson.
The complete upstream notice and permission text is retained in
[`LICENSES/THIRD_PARTY_MIT.md`](../LICENSES/THIRD_PARTY_MIT.md).

`themes/hermarchy/colors.toml` and the three converted wallpapers under
`wallpapers/hermarchy/` come from the MIT-licensed community theme
<https://github.com/archer-clawbot/omarchy-hermarchy-theme>, reviewed at commit
`12f3c5257f87237fa3fd549cf7be3f9fba76f9c8`, Copyright (c) 2026 Archer
Clawbot. The original 3840x2400 PNG artwork was center-cropped to 16:9,
resized to 1920x1080, stripped of metadata, and encoded as WebP for nbshell.
Its license is retained in [`themes/hermarchy/LICENSE`](hermarchy/LICENSE).

No Hermarchy agent collector, status widget, Omarchy shell configuration,
Hyprland configuration, or Hyprlock configuration is included. nbshell keeps
its existing native Hermes overview and merely applies the selected palette to
Hermes through the existing optional theme hook.

To refresh the color files from an Omarchy checkout:

```bash
for t in <omarchy-repo>/themes/*/; do
  mkdir -p "themes/$(basename "$t")"
  cp "$t/colors.toml" "themes/$(basename "$t")/"
done
```
