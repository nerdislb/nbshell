# Features

This page is a map of nbshell. Most features are available from the searchable
main menu, the bar, or the `nbshell` command.

## Desktop shell

- Island, expanding pill, or full-width bar
- Freely arranged and optional bar modules
- Searchable application launcher and an eight-category main menu whose root
  search reaches nested actions and installed applications
- Settings integrated into the Personalize menu flow, with breadcrumb and
  Back navigation; the direct shortcut and CLI entry remain available
- Dashboard for media, calendar, tasks, habits, system information, and tools
- Theme and wallpaper selection based on Omarchy-compatible color files
- Theme-accent frames shared by menus, overlays, popouts, and notifications
- Automatic palette synchronization for Zen Browser and Brave
- Notification center, clipboard history, system tray, and on-screen displays

## System controls

- Wi-Fi, saved NetworkManager VPN and WireGuard profiles, Bluetooth pairing
  and removal, audio devices, brightness, batteries, and power profiles
- Persistent Niri display setup for resolution, scale, rotation, and position
- Update workflow with restart recommendations for important system packages
- Process viewer, power menu, screen saver, and session controls
- Theme-synchronized Hyprlock screen using PAM authentication, the current
  palette, and either the current wallpaper or a private solid background
- Lock-before-suspend and configurable idle locking

## Lock screen

`Mod+Alt+L`, the session menu, and idle automation all use the same lock path.
nbshell generates the visual configuration immediately before locking, while
Hyprlock owns authentication and the compositor's secure session-lock
protocol. nbshell never reads or stores the password.

Settings → Lock Screen controls the background mode, wallpaper blur and dim
strength, date, and user/host label. Notification text, clipboard contents,
calendar entries, and agent data are intentionally never rendered. A custom
`lockCommand` remains available in `config.json` for advanced users, but the
default and supported path is Hyprlock.

## Window workflow

- Native Niri scrolling layout
- Optional workspace-local 2x2 grid progression with `Mod+Backspace`
- Floating Picture-in-Picture management for Zen Browser
- Floating windows for tools such as quick translation and phone preview

## Capture and media

- Screenshots by area, output, or selected window
- Screen recording and OBS launcher
- Fast start/end trimming through the nbshell-themed Omacut fork
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
- AI usage status in the bar and Dashboard

## Optional tools

- Guided gaming setup for Steam, Heroic, Lutris, Prism Launcher, RetroArch,
  GeForce NOW, and supporting tools
- Plugin system with managed examples such as Omamail, YouTube Music, and Pit
  Wall
- Calendar synchronization through `khal` and `vdirsyncer`
- Syncthing-backed tasks, habits, and wallpapers

Optional features are discovered at runtime. Missing software should disable a
feature cleanly instead of preventing the shell from starting.
