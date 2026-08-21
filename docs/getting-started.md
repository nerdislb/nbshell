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

The script lists missing packages before installing them. It may ask for your
sudo password and whether optional services should be enabled.

Enable the shell and its Niri integration:

```bash
nbshell switch on
```

Log out and back in. To try the shell immediately instead, run:

```bash
nbshell start -d
```

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

From the repository checkout:

```bash
git pull --ff-only
./install.sh
```

The Dashboard update action can update system packages. It shows `Restart
recommended` when a kernel or another important system component changed.

## If something goes wrong

```bash
nbshell log
niri validate
nbshell switch status
```

Run `nbshell switch off` to return to the previous shell integration without
deleting personal nbshell settings.
