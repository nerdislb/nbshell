# Troubleshooting and recovery

## Start with the health checks

```bash
nbshell status
nbshell switch status
umbriel validate
nbshell log
```

If the bar disappeared after an update, reinstall the tracked files and
restart the service:

```bash
cd ~/projects/nbshell
git pull --ff-only
./install.sh
nbshell restart
```

## Return to the previous desktop integration

```bash
nbshell switch off
```

This disables the nbshell user service and its Umbriel integration. It does
not delete personal themes, settings, tasks, plugins, or application data.

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
locker's compositor-confirmed secure state before calling systemd. The
`nbshell-sleep-lock.service` uses logind's bounded delay-inhibitor window to
apply the same secure-readiness check to lid-close, power-key, and direct sleep
requests that bypass the shell UI. If the locker cannot become secure before
logind's deadline, the daemon records the failure; logind ultimately owns the
sleep decision for those external requests. After resume the daemon waits for
Umbriel to restore a real output before waking DPMS; inspect it with:

```bash
systemctl --user status nbshell-sleep-lock.service
systemd-inhibit --list
```

## Recover from a failed screen locker

The native locker runs in the dedicated `nbshell-lock.service`, outside the
main `nbshell.service` cgroup. Umbriel deliberately keeps the session concealed
if a session-lock client crashes, and the unit restarts the client after a
failure.

If the lock UI does not return automatically under Umbriel, press
`Ctrl+Alt+Shift+L`. This key is explicitly allowed while locked and only runs:

```bash
systemctl --user restart nbshell-lock.service
```

It cannot unlock the session; only successful PAM authentication can do that.
Do not start Hyprlock while the native client may still own the session lock.

The compositor-independent final recovery path is a TTY. Switch with
`Ctrl+Alt+F2`, log in, identify the active Wayland session, and terminate that
session so the already enabled greetd service can present the login screen:

```bash
loginctl list-sessions
sudo loginctl terminate-session <WAYLAND_SESSION_ID>
```

This intentionally closes applications in that graphical session, so use it
only when restarting the lock client did not restore an authentication UI.
After the next login, inspect:

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

## Configuration migration blocks startup

Inspect the shell-config domain without changing it:

```bash
nbshell migrate status
nbshell migrate status --json
nbshell migrate apply --dry-run --json
```

Migration errors do not reset `~/.config/nbshell/config.json`. A mutating
migration first stores an immutable copy below
`~/.local/state/nbshell/migration-backups/`; the machine-readable status names
the exact backup associated with a pending or failed migration. Stop nbshell
before manually restoring or applying configuration because normal QML writes
do not take the migration lock.

A `pending` migration normally resumes at the next start. A `failed` migration
does not retry automatically, and a malformed ledger is not discarded. Preserve
both config and `~/.local/state/nbshell/config-migrations.json`, inspect the
reported error, and only then restore the named backup or move a damaged ledger
aside explicitly. Restoring shell config does not roll back Umbriel or plugin
state. Full ordering, downgrade limits and ownership boundaries are documented
in [Persistent state and Config Schema v1](persistent-state.md).

## Report a useful bug

Include the nbshell revision, Umbriel and Quickshell versions, graphics
hardware, display layout, exact reproduction
steps, and sanitized logs. Security issues belong in the private reporting
flow described in
[SECURITY.md](https://github.com/nerdislb/nbshell/blob/main/SECURITY.md), not a
public issue.
