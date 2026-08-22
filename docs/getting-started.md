# Getting started

This guide installs nbshell on an existing Arch Linux or Arch-based Niri
desktop. nbshell is a desktop shell, not a complete Linux distribution or ISO.

## Before you begin

You need:

- a working Niri Wayland session;
- a normal user account with `sudo` access;
- Git and an internet connection;
- a backup of configuration files you care about.

Do not run the setup script as root.

## Install

Open a terminal inside Niri and run:

```bash
git clone https://github.com/nerdislb/nbshell.git
cd nbshell
./setup.sh
```

The default profile installs the shell baseline and lists missing packages
before calling sudo. Optional modules remain visible but disabled when their
tools are unavailable. To install the full capture, calendar, sync, power, and
hardware tool set, use:

```bash
./setup.sh --full
```

Enable the shell and its Niri integration:

```bash
nbshell switch on
```

Log out and back in. To try the shell immediately instead, run:

```bash
nbshell start -d
```

Fresh installations start with the full-width bar and plain, unboxed widgets.
Island and pill modes remain available from Settings or the `nbshell` command.

## Verify the installation

```bash
nbshell switch status
nbshell status
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

The installer keeps an existing Niri configuration and includes nbshell through
its own generated file. Existing `~/.config/nbshell/config.json` settings are
also kept during updates.

If you manage packages yourself, install only the repository files:

```bash
./install.sh
nbshell start
```

## Update later

Open Dashboard → Tools → `nbshell update`. The shell checks only published
GitHub releases, links their release notes, and opens a terminal for explicit
confirmation. Before installation it verifies the release archive against its
published SHA-256 checksum. Personal configuration, themes, plugins, and data
remain in place.

The same flow is available from a terminal:

```bash
nbshell update
nbshell update install
```

To follow stable releases instead of beta releases, use `stable` as the final
argument. From a repository checkout, developers can still update manually:

```bash
git pull --ff-only
./install.sh
```

The separate `System updates` action handles distribution packages. It shows
`Restart recommended` when a kernel or another important component changed.
Plugin updates remain in the plugin manager.

## If something goes wrong

```bash
nbshell log
niri validate
nbshell switch status
```

Run `nbshell switch off` to return to the previous shell integration without
deleting personal nbshell settings.
