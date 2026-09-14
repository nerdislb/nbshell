# Optional integrations

These features are opt-in and depend on the corresponding tools or services.


## Gaming setup

Open **Gaming** from the main menu (`Mod+Space`) for Steam, native
Prism/Minecraft, RetroArch, Moonlight, cloud gaming and controller support.
Battle.net, GOG Galaxy and Epic Games use a shared themed background setup
panel through Faugus; existing Heroic and Lutris installations are preserved.
See [Windows stores through Faugus](gaming-faugus.md) for requirements and limits.

On current `main`, [Minecraft setup](gaming-minecraft.md) installs Prism and Java
in the background and registers a branded Apps shortcut without opening Prism
automatically. First launch still requires account sign-in and a game instance.
This refined setup is newer than beta 12.

Setup behavior depends on the selected integration: the Faugus and Minecraft
panels can request system authentication, while other helpers use a terminal
confirmation flow. Package availability and supported removal behavior are
shown by the respective flow; existing game data is not silently migrated.

```bash
nbshell gaming status
nbshell gaming install steam
nbshell gaming remove steam
```

## Other services

- Calendar data requires `khal`. Online calendar synchronization can be added
  with `vdirsyncer`.
- Task, quick-note, and wallpaper files can be synchronized with Syncthing.
  `Mod+Shift+N` opens the floating notes editor; `Alt+S` saves and closes it.
  Point `notesFile` at a synchronized directory with
  `nbshell set notesFile '~/Sync/nbshell/notes.json'`. nbOS reads the same
  `notes.json` from its existing shared data folder and merges entries by ID
  and update time, including deletion tombstones for offline-safe sync.
- Phone features require KDE Connect. Android mirroring and the optional phone
  webcam require ADB, `scrcpy`, and the separate `nbphone` tool. Webcam setup
  additionally installs `v4l2loopback-dkms`, matching kernel headers, and
  exposes the phone as `/dev/video10` for OBS and conferencing apps. The Phone
  panel can open a low-latency floating preview through `mpv` while capture is
  active.
- Live streaming opens OBS Studio from the Capture menu and therefore requires
  the optional `obs-studio` package. Stream credentials stay in OBS, not nbshell.
- The optional remote Herdr panel requires a read-only bridge; local Work Desk
  sessions use the existing local Herdr monitor. The shell works without either.
- AUR update counts require `paru` or `yay`.
- Umbriel and `xdg-desktop-portal-umbriel` are tracked separately from AUR
  packages. The Desktop updates panel compares clean local checkouts with the
  official noctalia-dev Git repositories, then builds and tests both before
  installing the reviewed root-owned stack below `/usr/local`. A compositor
  update takes effect after the next login.
- After a successful dashboard update, nbshell recommends a restart only when
  core components such as the kernel, systemd, glibc, firmware, or graphics
  drivers changed. The dashboard keeps the English `Restart recommended`
  notice until the machine actually boots again.
- Local dictation is optional. Install `voxtype-bin` from the AUR, download a
  model with `voxtype setup --download --model small`, and enable its user
  service. `F9`, `nbshell dictate`, and `Capture → Toggle dictation` then start
  or stop recording. While recording or transcribing, the AI bar module shows
  the live state and also acts as a stop button. nbshell uses compositor
  control, so Voxtype's evdev hotkey can remain disabled.
- Mail is bundled but disabled by default. Enable it with
  `nbshell plugin enable omamail`, restart nbshell, and open it with
  `Mod+Ctrl+Shift+G` or `nbshell mail`. Gmail uses the official Gmail API;
  HEY uses the separately installed official HEY CLI; IMAP/SMTP supports
  Fastmail, iCloud, Outlook, Yahoo, Zoho, GMX, Proton Bridge, and custom
  servers. Google Calendar and CalDAV views are integrated. Refresh tokens and
  mail passwords stay in the desktop keyring, local contact suggestions are
  opt-in, and Mail claims `mailto:` links only after `nbshell mail handler`.
  Runtime tools and packages are declared by the plugin manifest.
- The native YouTube Music player is also bundled and disabled by default.
  Install `mpv` and `yt-dlp`, enable it with `nbshell plugin enable ytmusic`,
  restart nbshell, then press `Mod+Ctrl+Shift+M`. First launch creates an
  unprivileged Python venv and a systemd user service that is not enabled at
  login. Zen, Chromium, Chrome, and Brave sessions can be imported directly;
  the built-in request-header paste flow remains a fallback. Authentication
  files are stored with mode `0600`.

