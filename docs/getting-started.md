# Getting started

This guide installs nbshell with Umbriel on Arch Linux or an Arch-based system.
nbshell is a desktop shell, not a complete Linux distribution or ISO.

## Before you begin

You need:

- a working graphical session or TTY and supported graphics drivers;
- a normal user account with `sudo` access;
- Git and an internet connection;
- a backup of configuration files you care about.

Do not run the setup script as root.

## Install

Open a terminal as your normal user and run:

```bash
git clone https://github.com/nerdislb/nbshell.git
cd nbshell
./setup.sh
```

The default profile installs Umbriel, its portal, the shell baseline, and Niri
as a recovery fallback. It lists missing packages before calling sudo. Optional
modules remain visible but disabled when their tools are unavailable. To
install the full capture, calendar, sync, power, and hardware tool set, use:

```bash
./setup.sh --full
```

Refresh shell autostart and the Niri fallback integration:

```bash
nbshell switch on
```

Log out and select **Umbriel**. Select **Niri** if the primary session needs
recovery. To try the shell immediately in the current session instead, run:

```bash
nbshell start -d
```

Fresh installations start with the full-width bar and plain, unboxed widgets.
Island and pill modes remain available from Settings or the `nbshell` command.

## What a clean installation creates

On a minimal, updated Arch installation with a normal user, working graphics,
network access, `git`, and `sudo`, the default `./setup.sh` flow does the
following:

1. Installs Quickshell, Niri, the shell's core service dependencies, and the
   Umbriel build/runtime dependencies from Arch repositories.
2. Clones the official Umbriel and xdg-desktop-portal-umbriel repositories to
   `~/.cache/nbshell/umbriel-sources`, builds them in release mode, runs their
   Meson tests, and installs them below `~/.local`.
3. Deploys nbshell atomically to `~/.config/quickshell/nbshell`, creates the
   Umbriel and Niri integration includes, and preserves existing personal
   configuration on later runs.
4. Adds the Umbriel greeter session and keeps the distribution's Niri session
   available for recovery. Umbriel owns Xwayland Satellite in its session;
   Niri may keep its separate service without starting a duplicate.
5. Installs the Umbriel screenshot/screencast portal and keeps compositor,
   nbshell-release, system-package, and plugin updates as separate paths.

The installer does not configure private accounts, copy secrets, remove an
existing desktop, or choose hardware drivers. Use `./setup.sh --full` for the
larger optional tool set and `./setup.sh --niri-only` when Umbriel should not be
built. After setup, run `nbshell switch on`, log out, and choose Umbriel. A
machine without a display manager can start the installed session from a TTY
with `start-umbriel`; the optional `./setup-greeter.sh` path assumes greetd is
already installed.

## Verify the installation

```bash
nbshell switch status
nbshell status
umbriel validate
niri validate
```

Open the main interfaces:

```bash
nbshell menu
nbshell dashboard
nbshell settings
nbshell modules
nbshell keys
```

## Existing configuration

The installer keeps existing Umbriel and Niri configurations and uses separate
nbshell-owned includes. Existing `~/.config/nbshell/config.json` settings are
also kept during updates.

If you manage packages yourself, install only the repository files:

```bash
./install.sh
nbshell start
```

## Update later

Open Dashboard → Tools → `Desktop updates`. nbshell itself still updates only
from published GitHub release archives and verifies their SHA-256 checksums.
The same panel also compares
Umbriel and its desktop portal with their official Git repositories. Their
updates are built and tested locally before installation; they become active
after the next login. Personal configuration, themes, plugins, and data remain
in place.

The same flow is available from a terminal:

```bash
nbshell update
nbshell update install
nbshell update umbriel
nbshell update all
```

To follow stable releases instead of beta releases, use `stable` as the final
argument. From a repository checkout, developers can still update manually:

```bash
git pull --ff-only
./install.sh
```

Umbriel is deliberately not treated as an AUR package: the compositor stack is
installed from its official source repositories, and dirty or unexpected
checkouts are refused. The separate `System updates` action handles
distribution packages. It shows
`Restart recommended` when a kernel or another important component changed.
Plugin updates remain in the plugin manager.

## Optional login screen

nbshell can replace an existing greetd frontend with either the established
ReGreet recovery client or the native Orbital QML frontend. Both authenticate
exclusively through greetd and `/etc/pam.d/greetd`; nbshell does not implement
PAM, store passwords, or launch arbitrary commands. Niri and Umbriel remain in
a root-owned session allowlist.

```bash
./setup-greeter.sh install orbital
```

Preview Orbital inside the current desktop without authentication, session
launch, or power actions:

```bash
nbshell greeter preview
```

After changing the theme or choosing a different wallpaper, synchronize the
currently staged frontend:

```bash
nbshell greeter sync
```

Inspect or switch the staged frontend without restarting the current graphical
session:

```bash
nbshell greeter status
nbshell greeter activate orbital
nbshell greeter activate regreet
```

The sync updates only public root-owned QML/CSS, compositor color, session
allowlist, and the copied wallpaper. It does not rewrite PAM. ReGreet remains
installed as the recovery frontend.

The installer keeps a recovery copy at
`/etc/greetd/config.toml.before-nbshell-greeter` and does not interrupt the
current session. greetd cannot reload its configuration while running, so a
frontend switch appears after a reboot; logging out before that still opens the
frontend already loaded by greetd.

## If something goes wrong

```bash
nbshell log
umbriel validate
niri validate
nbshell switch status
```

Choose Niri in the greeter to bypass an Umbriel regression. Run `nbshell switch
off` to return to the previous shell integration without deleting personal
nbshell settings.
