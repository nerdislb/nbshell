# Omarchy YouTube Music

**YouTube Music in Quickshell—not Chromium.**

Omarchy YouTube Music brings search, your library, playlists, and a mini player
into the Omarchy shell. Audio plays locally through **mpv** and **yt-dlp**, so
you are not keeping a browser-sized desktop client running. Colors follow your
active Omarchy theme, including light themes.

This plugin started from [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify)
by [stappmus](https://github.com/stappmus). The layout, shell integration, and
much of the player UI come from that project.

Pair it with **Omasing** and lyrics for the song you are playing are fetched
for you, ready when you want them.

![Omarchy YouTube Music full player](preview.png)

## Why you will love it

- **Lightweight by design.** Playback is mpv, not an Electron YouTube Music
  client.
- **Made for Omarchy.** Every color follows your current theme automatically.
- **Always within reach.** Play, pause, skip, seek, change volume, or open
  lyrics from the mini player in your bar.
- **Your YouTube Music library.** Search, browse home shelves, liked songs,
  playlists, albums, and artists, then build a queue.
- **Lyrics with Omasing.** Open the current song in Omasing and let it find
  the right lyrics and playback position automatically.

## Familiar from the first click

Library and playlists live in the sidebar, search stays at the top, and the
player stays at the bottom.

| Shortcut | What it does |
| --- | --- |
| `Ctrl+K` or `/` | Jump to search |
| `Space` | Play or pause |
| `Ctrl+Left` / `Ctrl+Right` | Previous or next song |
| `Shift+Left` / `Shift+Right` | Seek 10 seconds |
| `Ctrl+Up` / `Ctrl+Down` | Change volume |
| `M` | Mute or restore volume |
| `Ctrl+S` / `Ctrl+R` | Shuffle / repeat |
| `Ctrl+Shift+L` | Open lyrics in Omasing |
| `Ctrl+/` | See every keyboard shortcut |

The mini-player takes keyboard focus when it is opened from a shortcut. Use
`Tab` or the arrow keys to select every control, `Enter` to activate buttons,
left/right to adjust a selected slider, and `Esc` to close.

## Install

```bash
omarchy plugin add https://github.com/rlimberger/omarchy-ytmusic.git --enable
```

Requires **Omarchy 4**, **Python 3**, **mpv**, and **yt-dlp**:

```bash
omarchy pkg add mpv yt-dlp
```

The first time you open the player, the plugin installs a user venv with
[`ytmusicapi`](https://github.com/sigma67/ytmusicapi) and a systemd user unit
that is **never enabled at login**. The plugin starts it when you play music
and stops it after the configured idle period. No `sudo` or `pkexec` is
required.

From a local checkout:

```bash
./scripts/install-local.sh
```

To replace Omarchy's existing **Super+Shift+M · Music** binding, add this to
`~/.config/hypr/bindings.lua`:

```lua
  hl.unbind("SUPER + SHIFT + M") -- previously: Music
  o.bind("SUPER + SHIFT + M", "Omarchy YouTube Music",
    "omarchy shell -q quickshell.ytmusic.player togglePlayer")
```

Run `hyprctl reload` and check `hyprctl configerrors` after saving. In Settings,
choose whether that shortcut launches Omarchy's Music app, toggles the full
player, or toggles the mini-player.

## Sign in

YouTube Music has no public desktop API. Library, likes, and playlists use the
session already in Chromium:

1. Sign in at [music.youtube.com](https://music.youtube.com) in Chromium if you
   have not already.
2. Click the bar icon → **Set up and continue** → **Use Chromium session**.

Home shelves and search work without signing in. If you already use
`~/.config/ytmusicbar/browser.json`, first setup copies it. Pasting request
headers is still available as a fallback.

Your password is entered only on Google's own page. Headers are stored in
`~/.config/omarchy-ytmusic/browser.json` with mode `600`.

## Remove

While the plugin is still installed:

```bash
~/.config/omarchy/plugins/quickshell.ytmusic/scripts/remove-runtime.sh --purge
omarchy plugin remove quickshell.ytmusic
```

That stops the user unit and deletes:

- `~/.config/systemd/user/omarchy-ytmusic.service`
- `~/.local/lib/omarchy-ytmusic/`
- `~/.local/share/omarchy-ytmusic/`
- `~/.config/omarchy-ytmusic/`
- `~/.cache/omarchy-ytmusic/`

It does not change Hyprland bindings or other Omarchy config. Remove the
optional `SUPER + SHIFT + M` binding yourself if you added it.

## More music, less app

- Browse Home, Liked Songs, library songs/albums/artists, and playlists.
- Queue tracks, start song radio, shuffle, and repeat.
- Set a sleep timer from the full player.
- The bar slot is the YouTube Music logo only. Choose whether a click opens
  the mini-player or the full player, and whether the keyboard shortcut
  launches either of those or Omarchy's Music app.
- Choose 96, 160, or 320 kbps for local streams.

Want the details? Read the [technical notes](docs/TECHNICAL.md).

## Credits

Started from [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify) by
stappmus. Catalog and playback for YouTube Music use
[ytmusicapi](https://github.com/sigma67/ytmusicapi), **mpv**, and **yt-dlp**.

Omarchy YouTube Music is an independent project and is not affiliated with
YouTube or Google. YouTube Music is a trademark of Google LLC.

Licensed under the [MIT License](LICENSE).
