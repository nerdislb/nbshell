# Changelog

All notable user-facing changes to nbshell are documented here. The project
uses [Semantic Versioning](https://semver.org/); beta releases may still change
configuration and plugin interfaces before `1.0.0`.

## [Unreleased]

### Changed

- The bundled email client is now presented simply as Mail across the shell,
  launcher, notifications, setup, and window title. Its stable `omamail`
  plugin ID and storage namespaces remain unchanged, preserving existing
  accounts, credentials, caches, and integrations.

## [0.1.0-beta.4] - 2026-08-26

### Changed

- The screen saver now prefers the faster Rust `ttfx` renderer when version
  0.3.2 or newer is installed, while retaining Python TTE and the built-in
  renderer as automatic fallbacks. Older ttfx releases are rejected because
  they can abort when the hosting terminal closes.
- The battery popout now presents exactly three clear power modes: Power saver,
  Balanced, and Performance. Friendly IPC names map safely to the matching
  tuned profiles without exposing tuned's long specialist profile list.
- Bar hover previews and click popouts now replay the shared motion lifecycle
  when their Wayland surface is mapped, combining a soft fade, subtle scale,
  and edge-aware slide while honoring the selected motion profile.
- The native WhatsApp client now uses a compact sidebar, lighter header, and
  wider message bubbles at medium tiling widths without changing its mobile
  single-column mode. A selected unread chat is marked read after a short,
  uninterrupted viewing delay instead of requiring the overflow menu; the
  optimistic local state prevents duplicate receipts from cycling background
  sync, and setup now guarantees that sync is running afterward.

## [0.1.0-beta.3] - 2026-08-25

### Fixed

- Dashboard-triggered nbshell and Umbriel updates now run their terminal in a
  separate transient systemd user unit. Restarting `nbshell.service` during
  installation can no longer terminate the updater and its terminal midway.
- Ghostty updater windows use a dedicated process instead of handing the
  window to a singleton instance whose lifecycle may be unrelated to the
  transient update unit.

## [0.1.0-beta.2] - 2026-08-25

### Added

- The AI bar module now opens a provider dashboard with subscription windows,
  reset times, seven-day token history, model totals, agent state, and direct
  launch controls. Token summaries are derived locally without exposing prompt
  content and providers can be switched by tab, keyboard, wheel, or middle click.
- Completed agent work triggers a soft AI-symbol pulse and opens the affected
  Herdr task directly; visiting that task acknowledges its indicator.
- Umbriel is now the recommended compositor and default full-setup path, with
  compositor-neutral window/workspace actions, native portal integration,
  TOML rules, theme export, source-based updates, and Niri retained as the
  selectable recovery fallback.
- Transactional shell installation with a single-writer lock, preflight
  validation, atomic runtime switching, restart watchdog, and automatic
  rollback when the new shell does not stay active.
- A shared nbshell system skill is installed for Claude Code, Codex, Gemini
  CLI, Pi, OpenCode, and other Agent Skills-compatible tools, with a local
  discovery status command.
- Optional Omazen integration applies nbshell palette changes to an open Zen
  Browser through its separately installed, privileged live-theme bridge.
- Rarely used full-screen surfaces now load only while open, and the service
  tunes Quickshell's jemalloc arenas and huge-page policy to reduce idle memory
  without slowing IPC calls.
- A lazy Library brings installed themes, wallpaper collections, and reviewed
  plugins into one surface. Theme entries preview their default wallpaper with
  a centered terminal in the selected palette and show the wallpaper count.
- Launcher providers find and focus open windows (`#`), reuse clipboard history
  (`^`), evaluate calculations (`=`), and perform capped, on-demand file search
  (`@`) without adding a resident indexer.
- An agent-safe Markdown or JSON system report exposes stable diagnostic state
  while excluding window titles, clipboard and notification content, network
  addresses, and credentials.
- A focused demo workflow records through the existing capture stack, opens
  Omacut for trimming, and exports presets for Reddit, Discord, and GitHub.
- A native theme-aware calculator and a reversible native WhatsApp provider,
  with the existing PrettyZap route retained as a fallback.
- A native nbshell greetd login session and compact, collapsible display-mode
  selection for outputs with many available resolutions.

### Changed

- Umbriel animations use a slightly softer 300 ms duration while preserving
  the compositor's efficient native transitions.
- `Mod+Shift+Y` opens the new Library on Umbriel and the Niri fallback.
- Theme changes now restore each theme's selected wallpaper automatically and
  Aether's Apply action imports its generated palette through nbshell's native
  theme path.
- Zen Browser palettes can update live through the optional Omazen bridge.
- AI usage follows a provider-focused dashboard with local token history and
  clearer subscription windows.

### Fixed

- Suspend through nbshell now restores Umbriel windows that lose their
  workspace while outputs are recreated, preventing a resumed application
  from remaining visually stuck above newly focused windows.
- Capture operations survive closing the menu that started them, spawned
  Umbriel keybindings resolve the nbshell executable reliably, and duplicate
  Xwayland startup is avoided.
- Theme, plugin, and resume integration paths were hardened for repeated
  updates and normal daily use.

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

- Umbriel's display-off shortcut now waits for its triggering keys to be
  released before sending DPMS-off, preventing the release event from waking
  the display immediately.
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

[Unreleased]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.3...HEAD
[0.1.0-beta.3]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.2...v0.1.0-beta.3
[0.1.0-beta.2]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.1...v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/nerdislb/nbshell/releases/tag/v0.1.0-beta.1
