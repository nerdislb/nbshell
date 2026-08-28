# Troubleshooting and recovery

## Start with the health checks

```bash
nbshell status
nbshell switch status
niri validate
nbshell log
```

If the bar disappeared after an update, reinstall the tracked files and
restart the service:

```bash
cd ~/nbshell
git pull --ff-only
./install.sh
nbshell restart
```

## Return to the previous desktop integration

```bash
nbshell switch off
```

This disables the nbshell user service and removes its Niri include. It does
not delete personal themes, settings, tasks, plugins, or application data.
The installer keeps a `config.kdl.vor-nbshell` backup when it first changes the
Niri include.

## A module is empty

Run `./install.sh` to see missing optional programs. The Plugin Manager shows
declared dependencies for bundled and external plugins. Installing a plugin
does not install packages or enable the plugin automatically.

## Native Orbital session locker

The in-session locker is a Quickshell `WlSessionLock`, visually matched to the
Orbital login screen but architecturally separate from greetd. It authenticates
one password at a time through `/etc/pam.d/nbshell-lock`; only PAM success
releases the Wayland session lock. `./setup.sh` installs that dedicated profile.
`./install.sh` only stages it at
`~/.local/share/nbshell/locker/nbshell-lock.pam`, because the files-only
installer never changes `/etc`.

Preview the visuals safely, without acquiring a session lock or invoking PAM:

```bash
~/.config/quickshell/nbshell/scripts/lockscreen.py preview
```

The launcher selects the native locker when Quickshell, its QML payload, and
the dedicated PAM service are all available. Otherwise it starts Hyprlock.
An explicit `lockCommand` remains an override. Suspend waits for the native
locker's compositor-confirmed secure state before calling systemd.

## Recover from a failed screen locker

Both the native locker and Hyprlock use the secure session-lock protocol. If a locker exits while
the session is locked, Niri deliberately shows a red security screen instead
of exposing the desktop. Press `Mod+Alt+L` to start the locker again; this
binding remains enabled while locked.

If the binding itself is unavailable, switch to a TTY with `Ctrl+Alt+F3`, log
in, and restart the locker on the active Wayland display. Do not terminate
Niri to bypass the red screen. After returning, inspect:

```bash
journalctl --user --since "10 minutes ago" | grep -Ei 'nbshell.lock|hyprlock|quickshell'
```

Hyprlock remains an independent fallback. Its generated configuration is
`~/.config/nbshell/generated/hyprlock.conf`. It is replaced on every lock, so
put persistent choices in nbshell Settings or `~/.config/nbshell/config.json`
rather than editing that file.

## The shell fails after enabling a plugin

Disable it from a terminal, then restart:

```bash
nbshell plugin disable plugin.id
nbshell restart
```

Third-party QML shares the shell process. Report the plugin source and the
relevant lines from `nbshell log`, but remove tokens, addresses, message text,
and other personal data first.

## Report a useful bug

Include the nbshell revision, Niri and Quickshell versions, graphics hardware,
display layout, exact reproduction steps, and sanitized logs. Security issues
belong in GitHub's private vulnerability reporting flow, not a public issue.
