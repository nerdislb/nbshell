# nbshell

nbshell is an independent desktop shell for the
[niri](https://github.com/YaLTeR/niri) Wayland compositor. It is built with
[Quickshell](https://quickshell.org) and takes visual inspiration from
[Omarchy](https://omarchy.org). It does not require a full desktop environment.

The project was created with AI-assisted development. Product decisions,
testing, and the direction of the project remain human-led.

> nbshell is still under active development. It already works as a daily
> desktop, but commands, configuration, and features may still change.

## What does it include?

- Island, pill, or full-width bar with freely arranged modules
- Searchable menu, application launcher, dashboard, themes, and wallpapers
- Clipboard history, notification center, and system tray
- Audio mixer, media controls, Bluetooth, Wi-Fi, batteries, and power profiles
- Floating Picture-in-Picture controls for Zen Browser
- Calendar, tasks, habits, KDE Connect, and Android screen mirroring
- Screenshots, screen recording, OCR, QR scanning, and a screen saver
- AI usage for Codex, Claude, Antigravity, and other providers
- niri key bindings, terminal colors, and systemd autostart
- Optional herdr status inside the System & Plugins dashboard

## Requirements

You need:

- Arch Linux or an Arch-based distribution
- A working niri Wayland session
- Git and an internet connection
- A normal user account with `sudo` access for package installation

The setup script installs Quickshell, the Nerd Font, and the other packages
used by the included modules. Optional hardware features only work when their
matching services or devices are available.

## Simple installation on Arch Linux

Open a terminal inside your running niri session. Do not run the script as
root.

```bash
git clone https://github.com/nerdislb/nbshell.git
cd nbshell
./setup.sh
```

The script shows the missing packages before installing them. It may ask for
your `sudo` password and whether services such as Bluetooth or Syncthing should
be enabled.

When setup has finished, enable nbshell:

```bash
nbshell switch on
```

Then log out and back in. You can also start it immediately without logging
out:

```bash
nbshell start -d
```

Check the installation with:

```bash
nbshell switch status
```

## Install files only

If you manage packages yourself, use:

```bash
./install.sh
nbshell start
```

`install.sh` copies the shell and reports missing programs, but does not
install packages.

The installer keeps an existing niri configuration. If none exists, it creates
a small valid `~/.config/niri/config.kdl`. Existing personal nbshell settings
are not overwritten during later installations.

## First commands

```bash
nbshell menu             # Open the main menu
nbshell settings         # Change appearance and behavior
nbshell modules          # Arrange bar modules
nbshell keys             # Show key bindings
nbshell dashboard        # Open the dashboard
nbshell pip status       # Check Zen Picture-in-Picture
nbshell --help           # Show every command
```

Zen Browser opens its native Picture-in-Picture window with `Ctrl+Shift+]`.
nbshell makes that window floating and remembers its size and corner. Use the
`PIP` module or `Mod+Alt+P` to change its size. Use `Mod+Alt+Shift+P` to move it
to another corner.

## Optional features

- Calendar data requires `khal`. Online calendar synchronization can be added
  with `vdirsyncer`.
- Task and wallpaper files can be synchronized with Syncthing.
- Phone features require KDE Connect. Android mirroring also requires ADB,
  `scrcpy`, and the separate `nbphone` tool.
- The herdr panel requires a separately configured read-only bridge. The shell
  works normally without it.
- AUR update counts require `paru` or `yay`.

## Updating

```bash
cd nbshell
git pull --ff-only
./setup.sh --no-packages
nbshell restart
```

## Removing the integration

```bash
nbshell switch off
```

This disables nbshell autostart and removes its niri integration. It does not
delete your personal configuration or themes.

## Getting help

Run `nbshell --help` for command help. Bug reports and pull requests are
welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.
Report security problems privately as described in [SECURITY.md](SECURITY.md).

## Credits and license

nbshell takes visual and workflow inspiration from Omarchy, but it is an
independent implementation for niri and Quickshell. Theme sources are listed in
[themes/ATTRIBUTION.md](themes/ATTRIBUTION.md). Reused or adapted components
are documented in [THIRD_PARTY.md](THIRD_PARTY.md).

The remaining project is licensed under the [MIT License](LICENSE).
