# Features

This page is a map of nbshell. Most features are available from the searchable
main menu, the bar, or the `nbshell` command.

## Desktop shell

- Island, expanding pill, or full-width bar
- Freely arranged and optional bar modules
- Searchable application launcher and an eight-category main menu whose root
  search reaches nested actions and installed applications
- Launcher providers for open windows (`#`), existing clipboard history (`^`),
  calculator expressions (`=`), and explicitly requested file search (`@`)
- One lazy Library for installed themes, all wallpaper collections, and the
  reviewed plugin path
- Settings rendered directly inside the Personalize menu flow, with breadcrumb
  and Back navigation; the direct shortcut and CLI entry remain available
- Dashboard for media, calendar, tasks, habits, system information, and tools
- Local-draft shopping-list editor with free-text parsing, an exact WhatsApp
  preview, explicit clearing, and guarded delivery to one configured group
  through the optional `wacli` integration. The default group is `Einkauf`;
  change it with `nbshell set shoppingListTarget 'Groceries'`.
- Theme and wallpaper selection based on Omarchy-compatible color files
- A bundled original wallpaper collection and a global picker that can use an
  image from any theme collection without changing the active color theme
- Theme-accent frames shared by menus, overlays, popouts, and notifications
- Reduced, standard, and expressive motion profiles shared by the bar,
  controls, menus, popouts, Library, and wallpaper picker
- Automatic palette synchronization for Zen Browser and Brave, with an
  optional live-theme bridge for Zen updates
- Optional Hermes Agent skin generation through the example theme hook, with
  atomic live updates for Hermes CLI, TUI, and desktop surfaces
- Notification center, clipboard history, system tray, and on-screen displays
- Optional 1Password actions in the System > Security menu and searchable
  command catalog, with global Quick Access on `Ctrl+Shift+Space`; all vault
  handling remains inside the official 1Password client

The Library keeps search and list navigation while presenting the selected
theme as a responsive animated preview with previous/next theme cues. Motion
uses short opacity, scale, position, and list-scroll transitions only; the
reduced profile disables them without changing layout or functionality.

## System controls

- Wi-Fi, saved NetworkManager VPN and WireGuard profiles, Bluetooth pairing
  and removal, audio devices, brightness, batteries, and power profiles
- Optional Buds Control plugin for per-earbud and case batteries plus live ANC,
  transparency, and off modes through pbpctrl or BudsLink; adaptive appears
  when the selected backend supports it
- Persistent Umbriel display setup for resolution, scale, rotation,
  refresh rate, and position
- Update workflow with restart recommendations for important system packages
- Process viewer, power menu, screen saver, and session controls
- Native Orbital session locker using dedicated PAM authentication, the current
  palette, and either the current wallpaper or a private solid background;
  Hyprlock remains an independent fallback
- Lock-before-suspend and configurable idle locking

## Lock screen

`Mod+Alt+L`, the session menu, and idle automation all use the same lock path.
The native locker runs as a separate Quickshell `WlSessionLock` service and
authenticates through `/etc/pam.d/nbshell-lock`. Suspend waits until the
compositor confirms the secure session lock. At lock time, the launcher checks
for Quickshell, the native QML payload, and the dedicated PAM service; if any
are unavailable, it starts Hyprlock instead. nbshell never reads or stores the
password.

Settings → Lock Screen controls the background mode, wallpaper blur and dim
strength, date, and user/host label. Notification text, clipboard contents,
calendar entries, and agent data are intentionally never rendered. A custom
`lockCommand` remains available in `config.json` for advanced users and takes
precedence over both the native locker and Hyprlock fallback.

## Window workflow

- Native Umbriel scrolling and dwindle layouts
- Umbriel overview, workspace navigation, and floating-window rules
- Floating Picture-in-Picture management for Zen Browser
- Floating windows for tools such as quick translation and phone preview

## Capture and media

- Screenshots by area, output, or selected window
- Screen recording and OBS launcher
- Focused demo recording with on-demand Reddit, Discord, and GitHub exports
- Fast start/end trimming through the nbshell-themed Video Trimmer
- OCR, QR scanning, and optional local dictation
- Browser and application media controls through MPRIS

## Phone integration

- KDE Connect actions, status, battery, clipboard, files, SMS, and ping
- Android mirroring through the separate `nbphone` CLI and scrcpy
- Android front or rear camera as a V4L2 webcam
- Low-latency floating camera preview and direct OBS launch

See the [phone webcam guide](phone-webcam.md) for setup and daily use.

## AI and development

- Agent Center for Codex, Claude Code, OpenCode, Gemini, Copilot, and Pi
- Explicit safe, balanced, and autonomous approval profiles
- Local-model routing through OpenCode and Ollama
- Quick floating agent, project selection, pair workspaces, and Herdr sessions
- Supervised Hermes teams with bounded parallel work, cross-provider review,
  revisions, isolated integration, checks, recovery, and human-only deployment
- Reviewed Second Brain proposals with append/create-only note boundaries,
  privacy review, exact diffs, and human-only commit and push
- Explicit autonomous Hermes sessions starting at Home, with optional project
  targeting, YOLO terminal access, code execution, planning, delegation, and skills
- Provider-focused AI dashboard with subscription limits, reset times, local
  seven-day/model token summaries, agent state, and launch controls
- Privacy-conscious Markdown or JSON system report for agents and support

## Optional tools

- Guided gaming setup for Steam, Heroic, Lutris, Prism Launcher, RetroArch,
  GeForce NOW, and supporting tools
- Plugin system with managed examples such as Mail, YouTube Music, and Pit
  Wall
- Read-only Plugin Porting Lab for bounded static inspection of public GitHub
  repositories and Omarchy marketplace sources; it produces findings and a
  porting plan without executing, installing, or modifying third-party code,
  then offers an explicit coding-agent handoff for suitable reports
- Calendar synchronization through `khal` and `vdirsyncer`
- Syncthing-backed tasks, habits, and wallpapers
- Faster screen-saver rendering through
  [`ttfx` 0.3.2+](https://github.com/omacom-io/ttfx); Python TTE and the
  built-in renderer remain automatic fallbacks

Optional features are discovered at runtime. Missing software should disable a
feature cleanly instead of preventing the shell from starting.

## Performance

Large on-demand surfaces are lazy loaded, and the service includes a
conservative jemalloc policy for lower idle memory. See
[Performance](performance.md) for the measurement method and allocator
override.
