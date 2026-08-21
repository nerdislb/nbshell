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
