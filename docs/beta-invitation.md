# Join the nbshell beta

nbshell is an independent, keyboard-first Quickshell desktop for the Umbriel
Wayland compositor. It combines a searchable interface, coherent themes,
system controls, capture tools, and optional device and plugin integrations.

## Who should test

The beta is intended for people who use Arch Linux or an Arch-based system and
are comfortable recovering from a TTY. Commands and configuration may still
change before version 1.0.

Native screen-reader traversal of Quickshell surfaces is not functional in the
current beta. Keyboard operation and internal accessibility contracts are
tested, but the supported Arch Quickshell 0.3.1 package still exports an empty
AT-SPI tree. The lifecycle bug is fixed upstream and awaits a containing
Quickshell release in the supported baseline.

Useful test areas include:

- fresh Umbriel installation, login, update, and TTY/agreety recovery;
- bar, island, and pill layouts at different display scales;
- scrolling, dwindle, and master layouts plus overview;
- multi-monitor output configuration and hotplug;
- native session lock, suspend, and resume;
- capture, portal, PipeWire, and Xwayland behavior;
- optional Mail, WhatsApp, music, AI, phone, and gaming integrations;
- shopping-list draft, parsing, preview, exact-group resolution, and send flow;
- plugin scaffolding, validation, and strict design checks;
- Plugin Porting Lab reports for representative public community sources.

## Install

```bash
git clone https://github.com/nerdislb/nbshell.git
cd nbshell
./setup.sh
nbshell switch on
```

Log out and select Umbriel. The installer preserves personal nbshell settings
during updates. Keep the independent agreety recovery configuration and normal
TTY access available while testing the beta.

## Report feedback

Use a GitHub bug report for reproducible failures and a feature request for a
specific improvement. Include the nbshell revision, Umbriel and Quickshell
versions, display layout, GPU/driver, and the shortest reproduction sequence.
Review logs and screenshots before sharing them; never include credentials,
mail, notifications, clipboard data, network names, or private file paths.

General support is documented in
[SUPPORT.md](https://github.com/nerdislb/nbshell/blob/main/SUPPORT.md).
Vulnerabilities belong in the private path described by
[SECURITY.md](https://github.com/nerdislb/nbshell/blob/main/SECURITY.md).

## Suggested announcement

> I built nbshell, an independent Quickshell desktop shell for Umbriel. Its beta
> brings a searchable keyboard-first UI, native scrolling/dwindle/master
> layouts, coherent desktop theming, capture and system tools, reviewed plugin
> integrations, a local-draft WhatsApp shopping-list flow, a read-only Plugin
> Porting Lab, and a checksum-verified updater. It keeps normal Linux tools
> underneath instead of becoming another full desktop environment. Arch users
> comfortable with beta software and TTY recovery are welcome to test it.

## Media

A useful short clip shows island expansion, launcher search, dashboard,
Umbriel overview and layout switching, theme/wallpaper changes, display
controls, and one optional plugin. Keep it under 90 seconds and use neutral
sample data. Follow [project media](project-media.md) before publishing.
