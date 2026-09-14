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

## Current source preview

The new [Work Desk](work-dashboard.md) is available on `main`, after beta 12:
optional transparent desktop cards for OpenClaw/Herdr sessions, Git projects,
quotas and machine status, plus a compact daily CLI activity view. No AI account
is required for the rest of the desktop. The [README gallery](https://github.com/nerdislb/nbshell)
shows this current source UI with synthetic data, not real account screenshots.

## Suggested announcement

> I'm building nbshell, an independent Quickshell desktop shell for Umbriel on
> Arch Linux. It combines a bar/island/pill layout, coherent themes, everyday
> system controls and an optional Work Desk for sessions, Git and machine
> status. It's MIT-licensed and still beta. The Work Desk is on current main,
> newer than the beta 12 archive. I use AI-assisted development and would love
> feedback on the workflow, small-screen layouts and clean installs.

## Media

A useful short clip shows island expansion, launcher search, dashboard,
Umbriel overview and layout switching, theme/wallpaper changes, display
controls, and one optional plugin. Keep it under 90 seconds and use neutral
sample data. Follow [project media](project-media.md) before publishing.
