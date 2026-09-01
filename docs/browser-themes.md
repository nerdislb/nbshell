# Browser theme synchronization

nbshell can synchronize its current palette with Zen Browser and Brave. The
integration is optional and preserves existing browser profiles.

## Set it up

```bash
nbshell browser-theme setup
```

The command performs two explicit changes:

- Zen receives a single managed import in each existing `userChrome.css` and a
  generated `nbshell-theme.css`. Existing personal CSS stays in place.
- Brave receives a managed Linux policy under
  `/etc/brave/policies/managed/nbshell-color.json`. Creating that file asks for
  sudo once; the file is then owned by the current user so normal theme changes
  never need elevated privileges.

Restart Zen once after the first setup. Later nbshell theme changes rewrite the
managed CSS automatically. Zen's Browser Toolbox can reload `userChrome.css`
live during development, but a normal browser restart remains the reliable
fallback.

## Optional live Zen themes

The current supported bridge is Omazen 1.5.0. nbshell keeps Omazen as a
separately installed GPL program and builds its pinned Rust source with a narrow
Arch external-provider compatibility patch. Install or update that reviewed
stand with:

```bash
nbshell browser-theme install-zen-live
```

The command requires `git`, `rustup`, and the pinned Rust 1.98.0 toolchain. It
checks out the exact reviewed revision, applies the repository-owned patch, runs
Cargo and upstream lifecycle tests, and only then activates the new installation.
It does not bypass Zen package, ownership, path, symlink, or integrity checks.

After installation, set up the live bridge with:

```bash
nbshell browser-theme setup-zen-live
```

The setup asks for privilege only when installing Zen's program-level loader.
Restart Zen once to load that bridge; subsequent nbshell theme changes are
written atomically and applied without restarting the browser. nbshell removes
only its own legacy `userChrome.css` import after setup and `omazen doctor` both
succeed.

Run `nbshell browser-theme doctor-zen-live` after every Zen package update.
If the package replaced the bridge loader, repeat `setup-zen-live`. This remains
an optional integration: the upstream project is GPL-3.0-only and stays a separately
installed component rather than being copied into nbshell's MIT source.

Brave reloads its color policy while running. Dark themes seed Brave from the
theme background, because a bright accent can otherwise generate a light
Chromium surface even with dark mode enabled. On Arch, nbshell also maintains
a marked block in `~/.config/brave-flags.conf`: dark themes add
`--force-dark-mode`, while a
theme explicitly declaring `mode = "light"` removes that block. Existing
personal flags outside the marked block remain untouched. Changing the mode
requires restarting Brave; accent-only changes do not.

## Commands

```bash
nbshell browser-theme status
nbshell browser-theme setup-zen
nbshell browser-theme install-zen-live
nbshell browser-theme setup-zen-live
nbshell browser-theme doctor-zen-live
nbshell browser-theme setup-brave
nbshell browser-theme apply
```

Removing the managed import from Zen's `userChrome.css` disables the Zen
integration. Removing `nbshell-color.json` with sudo disables the Brave policy.
