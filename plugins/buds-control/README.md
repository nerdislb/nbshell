# Buds Control

Native nbshell controls for advanced Bluetooth earbuds. Pixel Buds are controlled
directly through [pbpctrl](https://github.com/qzed/pbpctrl); other compatible
headsets can use [BudsLink](https://flathub.org/apps/io.github.maniacx.BudsLink).
The bar shows the current noise-control mode and combined battery level. Its popout provides:

- individual left, right, and case battery levels;
- every noise-control mode exposed by the connected device;
- read-back-confirmed Pixel Buds mode changes;
- live updates and full settings for BudsLink-backed devices.

Google Pixel Buds Pro 2 expose Off, Transparency, and Noise Cancellation with
the stable pbpctrl release. Adaptive is shown automatically when the installed
pbpctrl version supports it. Other devices use the controls and labels reported
by BudsLink.

## Backend

Install pbpctrl for Pixel Buds. On Arch Linux it is available from the AUR:

```sh
paru -S pbpctrl
```

Install the optional BudsLink fallback for other supported headsets from Flathub:

```sh
flatpak install --user flathub io.github.maniacx.BudsLink
```

Only one Pixel Buds backend can own the device protocol at a time. For connected
Pixel Buds, the plugin releases a running BudsLink Flatpak before using pbpctrl.
Unsupported or disconnected devices do not expose noise-control actions.

## Develop

```sh
nbshell plugin validate .
nbshell plugin design-check . --strict
```

Visible plugins use `qs.Common` / `qs.Widgets` or the compatibility modules `qs.Commons` / `qs.Ui`. Keep colors, spacing, typography, motion, focus, and surfaces on shared semantic tokens.

## Install locally

```sh
nbshell plugin add .
nbshell plugin enable io.github.nerdislb.buds-control
```

Plugins run unsandboxed inside the long-running shell process. Review dependencies and commands before enabling them.
