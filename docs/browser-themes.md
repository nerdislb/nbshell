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

Brave reloads its platform policy while running. Its toolbar follows the
nbshell accent, and `BrowserColorScheme=device` follows the system light/dark
preference.

## Commands

```bash
nbshell browser-theme status
nbshell browser-theme setup-zen
nbshell browser-theme setup-brave
nbshell browser-theme apply
```

Removing the managed import from Zen's `userChrome.css` disables the Zen
integration. Removing `nbshell-color.json` with sudo disables the Brave policy.
