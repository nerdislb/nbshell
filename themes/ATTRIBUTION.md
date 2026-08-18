# Theme attribution

The `colors.toml` files in this directory come from
<https://github.com/basecamp/omarchy>. They are MIT-licensed,
Copyright (c) David Heinemeier Hansson.

Only the color definitions are included. Preview images, wallpapers, and the
remaining upstream theme files are intentionally excluded.

To refresh the color files from an Omarchy checkout:

```bash
for t in <omarchy-repo>/themes/*/; do
  mkdir -p "themes/$(basename "$t")"
  cp "$t/colors.toml" "themes/$(basename "$t")/"
done
```
