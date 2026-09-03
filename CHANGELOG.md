# Changelog

All notable user-facing changes to nbshell are documented here. The project
uses [Semantic Versioning](https://semver.org/); beta releases may still change
configuration and plugin interfaces before `1.0.0`.

## [Unreleased]

### Added

- Suitable Plugin Porting Lab reports now offer a `START PORT` action that opens
  the configured coding agent in the nbshell source tree with a guarded prompt
  containing the source, verdict, findings, and ordered implementation plan.
- Twenty-four original Catppuccin Latte, Catppuccin Mocha, Tokyo Night, Nord,
  and Osaka Jade wallpapers add realistic, flat, and pixel-art landscapes,
  mountain scenes, sunsets, and fogbound cities to their matching theme
  collections, with retained Midjourney generation provenance.

### Fixed

- Lid-close, power-key, and other logind sleep requests now wait for Orbital's
  compositor-confirmed secure coverage before suspending. Resume waits quietly
  for a real Umbriel output and wakes DPMS instead of flooding failed workspace
  repairs while the internal panel is absent.
- Agent Center launches interactive coding agents in independent transient
  systemd scopes, so restarting nbshell no longer terminates their terminals or
  in-progress work.

## [0.1.0-beta.9] - 2026-09-02

### Fixed

- Release installation archives now omit the internal ISO build tree, which is
  not needed by `setup.sh` or `install.sh` and contains a systemd service link
  intentionally rejected by the hardened extractors. This restores bootstrap
  and updater installation; beta.8 is superseded because its signed archive
  included that link and was rejected before changing the system.

## [0.1.0-beta.8] - 2026-09-02

### Added

- A local shopping-list tool turns commas, lines, and natural-language input
  into a WhatsApp checklist, keeps an atomic local draft, previews the exact
  message, and sends only after resolving one unambiguous configured group
  through the optional `wacli` integration. The default `Einkauf` target can be
  changed with `nbshell set shoppingListTarget <name>`.
- The Plugin Center now includes a read-only Porting Lab for public GitHub and
  Omarchy marketplace sources. It fetches bounded source text without running
  it, reports deterministic compatibility and safety findings, and recommends
  an ordered native nbshell porting path without installing or modifying code.
- A one-command bootstrap selects a published beta or stable release, downloads
  its archive, checksum, and Sigstore bundle without piping network content into
  a shell, rejects unsafe archive paths, and hands the verified source tree to
  the complete `setup.sh` flow that installs Umbriel and nbshell.
- An internal x86_64 UEFI Archiso experiment builds a pinned offline package
  closure, local Umbriel/portal/nbshell packages, original nbshell branding,
  and a guarded whole-disk Archinstall flow for QEMU and empty spare disks. It
  remains explicitly unsupported for public installation.

### Fixed

- The Umbriel updater now compares the compositor and portal checkouts with
  their live upstream heads and installs the exact revisions it reported after
  confirmation, instead of treating the static installation baseline as the
  latest available version.
- The motion contract now follows the filtered visible right-side widget list
  used by the unified desktop update surface.
- Audio output lists collapse stale PipeWire nodes with the same stable node
  name while preserving the preferred default object, so a noisy host graph no
  longer renders several identical speaker rows.
- The optional Pit Wall live-timing environment now excludes vulnerable
  `msgpack` releases and requires the patched 1.2.1-or-newer line.
- System Hub opens dynamic Arch News and Herdr targets as structured argument
  lists instead of shell text, and limits feed-provided links to Arch Linux
  HTTPS origins.
- The documented `nbshell media` MPRIS command is no longer shadowed by the
  legacy music-window alias.
- Agent Center no longer refreshes selected job or proposal details after its
  lazy surface closes, and the native lock clock falls back to a one-second
  update cadence when its smooth seconds ring is disabled.
- Active background agent work uses the same five-second status cadence as the
  visible Agent Center instead of launching the multi-provider status helper
  every two seconds; idle cadence remains 30 seconds.
- Git-managed third-party plugins now show incoming commits and files and
  require an interactive confirmation or explicit `--yes` before their
  unsandboxed checkout can move.
- Shopping-list content travels to nbshell's sender over stdin instead of
  remaining in the wrapper process arguments during recipient lookup. The
  downstream `wacli --message` argument remains documented as an external CLI
  limitation.
- Shell release downloads and extraction now enforce compressed size, member
  count, per-file size, expanded size, entry-type, link, traversal, and
  single-root limits before the installer can run.
- Top-right notification popups now use nbshell's compact character-grid
  surface instead of the rounded Omarchy-style card treatment, while retaining
  urgency-aware timeouts, hover pause, guarded opening, and right-click dismiss.
- Notification popup timeouts are now consumed once by the notification
  service instead of once per monitor. Non-transient `notify-send` messages
  remain in history while Do Not Disturb suppresses their popup.
- Umbriel source updates distinguish a safely blocked dirty checkout from an
  operational error, list the paths that block installation, and keep the
  update action available once confirmed generated files are quarantined.
- The standalone Orbital locker no longer imports modules from the main shell
  configuration, preventing its isolated service from entering a restart loop.
- Installation rollback remains available until late configuration, plugin,
  integration, and post-install work has completed successfully.

## [0.1.0-beta.7] - 2026-08-31

### Added

- Public support, privacy, and private security-reporting policies now use the
  verified `nbsystems.dev` role addresses.
- The plugin golden path now includes a stable design contract, shared native
  and compatibility APIs, real panel/overlay/service/bar templates, strict
  design checks, and an expanded live UI Gallery.
- Hermarchy is available as a restrained near-black nbshell theme with a more
  colorful Catppuccin-leaning semantic palette and three original converted wallpapers.
  Its optional compact comparison widget is disabled by default and reuses the
  existing Hermes service without adding a collector or polling process. Hermes
  session state, tokens, resources, jobs, and launch affordances now live only
  in the compact widget or Agent Center; the original AI popout remains focused
  on provider limits, usage history, and non-Hermes agent activity. The theme
  hook continues to update Hermes itself.

### Changed

- nbshell now supports Umbriel exclusively. The former fallback backend,
  compositor-specific grid controller, duplicate configuration payloads, and
  related installer paths have been removed. Workspace layout control now uses
  Umbriel's native scrolling, dwindle, and master modes.
- Umbriel and its portal are installed as one root-owned reviewed stack below
  `/usr/local`, allowing user sessions and the isolated greetd frontend to use
  the same validated binaries.
- Orbital now runs inside an isolated Umbriel greeter profile. A compositor-free
  agreety configuration provides the independent recovery path.
- GitHub workflows and the documentation toolchain now use their current
  supported releases through immutable action revisions. Tag publication now
  waits for the complete validation workflow instead of release metadata alone.
- The optional native WhatsApp client now tracks upstream 0.11.2, adding
  account controls, safer cross-account and media handling, keyboard reply
  actions, and guarded local-notification clearing while retaining nbshell's
  responsive layout and bounded refresh path.
- Mail now tracks upstream 0.6.0 with HEY and IMAP providers, attachments,
  drafts and undo-send, calendar views and event editing, bounded remote-image
  handling, and native `mailto:` routing through nbshell.
- The optional Omazen bridge now tracks the Rust-based 1.5.0 generation. A
  narrow tested compatibility patch supports Arch only in nbshell's explicit
  external-palette-provider mode, and installation builds and tests the pinned
  source before replacing an existing bridge.
- The optional Hermes pilot now tracks upstream `936b970` on Hermes 0.20.6.
  Its locked all-feature environment and isolated security audit complete
  without known vulnerabilities; existing nbshell permission profiles and the
  13-tool broker boundary remain unchanged.
- The retired Node/Baileys WhatsApp bridge and built-in widget have been removed;
  existing widget slots migrate to the selected wacli or PrettyZap provider.
- Umbriel and its portal now install as one reviewed, immutable revision pair;
  both projects must build and pass tests before either is installed.
- Video Trimmer installation now builds an explicit reviewed revision instead
  of an unreviewed moving branch.
- Pit Wall metadata now points to its actual maintained upstream repository.

### Fixed

- The UI Gallery remains fully keyboard-scrollable at large text sizes through
  arrows, J/K, Page Up/Down, Home, and End, with Escape preserved.
- Long WhatsApp drafts remain reachable in both the full client and compact
  composer, and setup defers a shell restart when invoked from nbshell itself.

## [0.1.0-beta.6] - 2026-08-30

### Added

- Shared buttons and interactive panel rows now expose native Qt accessibility
  roles, names, states, assistive-technology press actions, visible keyboard
  focus, and guarded Return/Enter/Space activation without key-repeat actions.
- Omarchy-compatible plugin buttons and inline actions now expose native Qt
  names, states, and press actions without adding new physical Tab stops or
  changing the plugins' existing keyboard routers.
- The UI Gallery is scrollable and documents typography, control and action
  states, selected-focus behavior, static versus interactive accessibility
  roles, long-content handling, active theme mode, motion, and surface levels.
- The right side of the bar can collapse at its configured separator into a
  persistent chevron. Widgets to the left remain visible, the complete tail
  slides back out on the next click, and the tray keeps its own independent
  expanded or collapsed state.
- Fresh installations now offer the native Orbital login screen by default.
  Existing installations and file-only updates preserve their current display
  manager frontend unless Orbital is requested explicitly; ReGreet remains the
  independent recovery path. Autologin is never inferred from an installed
  session launcher and requires a separate explicit option.
- A native Orbital session locker runs in its own restartable service, uses a
  dedicated PAM profile, waits for compositor-confirmed output coverage before
  suspend, and provides a locked-session recovery binding. Hyprlock remains an
  independent fallback.
- A bounded AT-SPI diagnostic probe records privacy-protected accessibility
  snapshots and focus events. Its unit tests also document the current external
  Quickshell window-proxy limitation.
- The optional example theme hook can generate a validated `nbshell` skin for
  Hermes Agent and update the active CLI, TUI, and desktop palette atomically.

### Changed

- Dashboard tabs now use the shared accessible `ControlButton` contract while
  preserving their four-column geometry, muted inactive labels, page shortcuts,
  and selected-state styling.
- Audio-output rows now use the shared accessible `PanelRow` contract while
  preserving dense popout geometry, current-output markers, and sink switching.
- Motion now distinguishes short visual effects from spatial movement. Bar
  popouts and the most-used overlays keep their content mounted through a real
  exit animation, fade their scrims with the surface, and unload only after the
  transition completes. Reduced motion also stops attention and spinner loops.
- Umbriel uses event-specific motion instead of one global 300 ms duration:
  opening, closing, moving, workspaces, overview, and focus-border transitions
  have separate timings and curves. Layer-shell animation stays disabled so
  nbshell's QML surfaces are never double-animated by the compositor.
- Theme, network, VPN, Bluetooth, KDE Connect, notification, dashboard, plugin
  text-field, and plugin-slider controls now share the same keyboard, pointer,
  focus, scrolling, and assistive-technology contracts while retaining their
  existing layouts and actions.
- Network counters and Pit Wall snapshots are read in-process instead of
  spawning hot-path helper commands. The public CLI catalog now validates all
  180 documented commands against help and Markdown references.

### Fixed

- The audio popout now acquires keyboard focus before mapping and explicitly
  focuses its first accessible output row once Wayland activates the popup, so
  Tab traversal and Enter or Space work reliably when switching sinks.
- Omarchy-compatible plugin buttons, icon actions, and sliders resolve motion
  timing through the explicit nbshell Theme adapter instead of an undefined
  global `Theme`; isolated public-API and pointer/keyboard contract tests now
  cover the `qs.Ui`/`qs.Commons` compatibility layer.
- Process-list actions remain bound to the selected process identity across
  two-second refreshes and CPU-based reordering. Signals now verify PID plus
  start time and use a Linux pidfd, so a recycled PID cannot redirect a stop or
  force-stop action to a different process.
- Umbriel window opening now uses a longer, more even ease-out and a subtler
  pop-in scale, avoiding the abrupt initial jump of the previous motion profile.
- WhatsApp chat refreshes no longer feed SQLite WAL notifications back into the
  same database query several times per second. The resident service now uses
  its bounded 12-second refresh interval, eliminating the short-lived Python
  process storm while keeping unread counts current.
- Display refresh-rate changes are verified after Umbriel reloads them and roll
  back transactionally when DRM rejects a mode.
- Bar popouts are claimed by exactly one output, preventing binding loops and
  missing audio or network panels on multi-monitor Umbriel sessions.
- Gemini implementation jobs use a bounded long-running timeout and an isolated
  private credential copy, so completed transactions are not lost at the old
  five-minute boundary.
- Installer staging, runtime swaps, rollback discovery, and recovery now handle
  interruption after either rename without leaving an empty or nested runtime.
- The Orbital login screen creates a fresh writable password prompt after a
  failed authentication attempt.
- Audio popouts recover keyboard focus after Wayland activation and pointer
  entry, keep focused controls visible, and preserve normal Tab traversal.
- Process actions verify PID plus process start time and use pidfds, preventing
  a recycled PID from receiving a stop or force-stop intended for another task.
- Plugin compatibility adapters resolve exported icons and theme members
  explicitly, and line-style meters no longer reference an undefined Config
  singleton at runtime.

### Security

- The native locker is isolated from the desktop shell cgroup, its installed
  PAM payload is verified, and suspend waits for compositor-confirmed secure
  output coverage. The startup crash window cannot pass through unlocked.
- Installer reservations are private and atomic, recovery validates runtime
  contents instead of trusting rename state, and fault-injection covers the
  first-swap interruption boundary.

### Known limitations

- Quickshell's proxied window integration currently exposes only an empty
  application root to AT-SPI even though the same Qt accessibility stack works
  for ordinary Qt Quick windows. The new probe diagnoses this external limit;
  it does not make Orca traversal of nbshell windows available yet.

## [0.1.0-beta.5] - 2026-08-27

### Added

- Optional 1Password desktop integration adds Quick Access on
  `Ctrl+Shift+Space` for Umbriel and Niri, plus Open, Quick Access, and Lock
  actions in the searchable command catalog and System > Security menu. The
  shell only launches the official client and never reads vault data.
- An optional native Orbital QML login screen authenticates through greetd,
  keeps ReGreet as an independent recovery frontend, restricts sessions to a
  root-owned allowlist, and installs transactionally without restarting the
  active graphical session. A dedicated password-first PAM service avoids
  blocking password input behind greetd's serial fingerprint conversation
  while leaving existing PAM services untouched.
- Optional phone approval uses certificate-pinned TLS, an Android
  hardware-backed signing key, biometric confirmation, short-lived one-time
  grants, and explicit per-service PAM activation for `sudo` or Polkit.
- The Agent Center can run an isolated Hermes pilot with Codex, Claude, or
  Gemini lanes, bounded cross-provider advisory calls, disposable
  implementation jobs, independent reviews, supervised multi-agent teams, and
  human-confirmed apply/install/push boundaries.
- Hermes can prepare narrowly scoped Second Brain additions for independent
  review and explicit human application without receiving direct vault access.
  An opt-in Trusted workspace mode supports normal project work, while the
  shipped default remains the restricted profile.
- Native Hermes activity, token, tool-call, process, CPU, and proportional
  memory summaries are available in the Agent Center and existing AI bar
  module without exposing prompt or response contents.
- `nbshell upstream-audit` and a low-frequency user timer report reviewed
  upstream changes without automatically importing external code.

### Changed

- Remaining Omarchy-derived product labels are simplified across the visible
  shell: Command center, Lyrics, Video Trimmer, and Zen theme bridge. Stable
  upstream IDs and paths remain unchanged for compatibility and attribution.
- The bundled email client is now presented simply as Mail across the shell,
  launcher, notifications, setup, and window title. Its stable `omamail`
  plugin ID and storage namespaces remain unchanged, preserving existing
  accounts, credentials, caches, and integrations.
- The WhatsApp integration tracks its reviewed upstream more closely, uses a
  native responsive toggle, and records external source revisions explicitly.
- Umbriel updates no longer carry the compatibility patch that was accepted
  upstream, and dashboard-triggered compositor updates require the same clear
  install confirmation as other privileged update paths.
- The Hermes Trusted launcher synchronizes the selected workspace with the TUI
  gateway before startup, and the stable desktop IPC layer owns Agent Center
  launch commands even while the heavy panel is unloaded.

### Fixed

- Num Lock is enabled consistently in Umbriel sessions.
- Vertically arranged outputs retain their configured positions under Umbriel.
- The Orbital clock now advances clockwise at normal time speed; the accidental
  360-degree authentication spin was removed.
- The Orbital greeter requests and focuses a real password prompt immediately
  instead of presenting a fingerprint/password switch that one serialized PAM
  conversation cannot provide.

### Security

- Hermes advisory providers receive text only and no project tools. Autonomous
  jobs run in provider-separated disposable workspaces; applying, installing,
  pushing, and Brain writes remain unavailable to agents and require explicit
  human confirmation after an independent review.
- Greeter deployment validates dependencies, QML, compositor configuration,
  file ownership, fallback activation, mock greetd IPC, and a temporary-root
  install before committing the frontend selector.

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

[Unreleased]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.9...HEAD
[0.1.0-beta.9]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.8...v0.1.0-beta.9
[0.1.0-beta.8]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.7...v0.1.0-beta.8
[0.1.0-beta.7]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.6...v0.1.0-beta.7
[0.1.0-beta.6]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.5...v0.1.0-beta.6
[0.1.0-beta.5]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.4...v0.1.0-beta.5
[0.1.0-beta.4]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.3...v0.1.0-beta.4
[0.1.0-beta.3]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.2...v0.1.0-beta.3
[0.1.0-beta.2]: https://github.com/nerdislb/nbshell/compare/v0.1.0-beta.1...v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/nerdislb/nbshell/releases/tag/v0.1.0-beta.1
