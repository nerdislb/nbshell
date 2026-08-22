# Changelog

All notable user-facing changes to nbshell are documented here. The project
uses [Semantic Versioning](https://semver.org/); beta releases may still change
configuration and plugin interfaces before `1.0.0`.

## [Unreleased]

No changes yet.

## [0.1.0-beta.1] - 2026-08-22

First public beta candidate.

### Added

- A dashboard and CLI updater for published nbshell releases, with release
  notes, an explicit terminal confirmation, SHA-256 verification, beta/stable
  channels, and preservation of personal configuration and extensions.
- Versioned installer archives and checksums generated automatically by the
  release workflow.
- Fourteen original 1920×1080 nbshell wallpapers across seven theme
  collections, spanning moody landscapes, bright scenes, and abstract patterns.
- A global wallpaper picker that browses every installed and synchronized
  theme collection without changing the active color theme.
- A persistent `CURRENT THEME` / `ALL` scope switch in the wallpaper picker,
  also available from the keyboard with `Tab`.
- A theme-synchronized Hyprlock screen with an accent-framed nbshell layout,
  privacy-safe defaults, configurable wallpaper treatment, lock-before-suspend,
  and a Niri recovery binding that remains available while locked.
- Complete third-party MIT notices, an explicit independent-project and
  non-endorsement statement, release-media branding guidance, and automated
  release checks that prevent those notices from being dropped.
- Main-menu search now includes installed desktop applications and launches
  the selected app directly.
- The connection popout can connect and disconnect saved NetworkManager VPN
  and WireGuard profiles without handling their credentials itself.
- The main menu now starts with eight focused categories, while root search
  finds actions at every nested level alongside installed applications.
- Menus, overlays, bar popouts, notifications, OSD surfaces, plugin popups,
  and tooltips now share the active theme's accent frame; inner cards retain
  neutral borders for visual hierarchy.
- Synced floating quick notes with `Mod+Shift+N`, `Alt+S`, per-note conflict
  merging, deletion tombstones, and an optional nbOS companion view.
- Workspace-local grid pairing keeps the first two windows stacked when a
  third window opens in the next scrolling column.

### Changed

- Shell releases, distribution packages, and plugin updates are presented as
  three distinct update paths.
- Settings is now rendered directly inside the Personalize menu flow instead
  of opening a second overlay window. Direct shortcut and CLI entry points
  remain available as a standalone view.
- Fresh installations now start with the full-width bar, plain unboxed
  widgets, and a neutral core-module layout.
- Full-screen wallpapers decode at the active output size, and hidden launcher
  rows no longer rasterize application icons at startup, reducing the tested
  idle shell PSS by roughly 60 MiB.
- Battery health falls back to Linux power-supply design capacity when the
  Quickshell UPower API does not provide it.
- Optional WhatsApp IPC remains dormant until its local bridge is installed.
- Built-in module names and descriptions are consistently English, and the
  plugin CLI sizes its columns for long identifiers.

### Fixed

- The lock screen now receives the wallpaper currently rendered by the live
  shell, avoiding a stale image when locking immediately after a selection.
- Lock-screen panels, password field, borders, and supporting typography now
  use the shell's configured corner radius, border width, font, and text scale.
- Clipboard decoding no longer uses Qt's deprecated string `atob` overload.
- Hidden launcher SVG rendering no longer emits oversized-buffer warnings at
  shell startup.

### Foundation

- Collapsible island, pill, and full-width bar layouts for Niri.
- Launcher, dashboard, notifications, clipboard, calendar, capture, display,
  network, Bluetooth, media, update, AI-agent, and gaming interfaces.
- Omarchy-inspired theme collection with synchronized terminal and browser
  colors.
- Workspace-local grid-scroll mode with stable two-window columns.
- Curated plugin manager and optional first-party plugins for mail, YouTube
  Music, Formula 1 timing, weather, and supported headset batteries.
- Reproducible fresh-install, plugin, documentation, and release audits.

### Security

- Third-party plugins install disabled and expose their source, license, and
  declared dependencies before activation.
- Credentials remain outside the repository and plugin configuration.

[Unreleased]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/nerdislb/nbshell/releases/tag/v0.1.0-beta.1
