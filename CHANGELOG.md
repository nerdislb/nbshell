# Changelog

All notable user-facing changes to nbshell are documented here. The project
uses [Semantic Versioning](https://semver.org/); beta releases may still change
configuration and plugin interfaces before `1.0.0`.

## [Unreleased]

### Added

- Main-menu search now includes installed desktop applications and launches
  the selected app directly.
- The connection popout can connect and disconnect saved NetworkManager VPN
  and WireGuard profiles without handling their credentials itself.
- The main menu now starts with eight focused categories, while root search
  finds actions at every nested level alongside installed applications.
- Menus, overlays, bar popouts, notifications, OSD surfaces, plugin popups,
  and tooltips now share the active theme's accent frame; inner cards retain
  neutral borders for visual hierarchy.

### Changed

- Fresh installations now start with the full-width bar, plain unboxed
  widgets, and a neutral core-module layout.

## [0.1.0-beta.1] - 2026-08-21

First public beta candidate.

### Added

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
