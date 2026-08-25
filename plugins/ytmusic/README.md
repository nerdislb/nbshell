# nbshell YouTube Music

YouTube Music runs inside nbshell while audio playback stays in a local,
headless `mpv` process. There is no embedded browser or Electron runtime.

## Features

- Home, search, liked songs, playlists, albums, artists, and song radio
- persistent local play history, merged with YouTube history when signed in
- queue playback and drag-to-reorder
- persistent ten-band equalizer with presets and custom bands
- seek, volume, shuffle, repeat, likes, and sleep timer
- Zen, Chromium, Chrome, and Brave session import
- automatic backend recovery and a cached first-play yt-dlp warm-up
- nbshell theme integration, responsive artwork, tooltips, and keyboard access

The live spectrum experiment from the Wizwam fork is intentionally excluded:
it requires continuous audio capture, FFT processing, and frequent UI updates.

## Install and enable

The plugin is bundled with nbshell. A normal nbshell installation deploys it;
enable it from the plugin settings or with:

```bash
nbshell plugin enable ytmusic
```

`mpv`, `yt-dlp`, and Python are required. The first player launch creates a
private user venv and installs a systemd user service. The service is not
enabled at login: nbshell starts it on demand and it exits after the configured
idle period.

## Sign in

Search and basic browsing work without an account. Library, likes, playlists,
and remote history use a YouTube Music browser session:

1. Sign in to `music.youtube.com` in Zen, Chromium, Chrome, or Brave.
2. Open YouTube Music in nbshell.
3. Choose **Use browser session**.

Pasted request headers remain available as a fallback. Authentication headers
are stored at `~/.config/omarchy-ytmusic/browser.json` with mode `0600`.
Passwords are never read or stored by the plugin.

## Keyboard controls

| Shortcut | Action |
| --- | --- |
| `Ctrl+K` or `/` | Search |
| `Space` | Play or pause |
| `Ctrl+Left` / `Ctrl+Right` | Previous or next |
| `Shift+Left` / `Shift+Right` | Seek ten seconds |
| `Ctrl+Up` / `Ctrl+Down` | Change volume |
| `M` | Mute or restore volume |
| `Ctrl+S` / `Ctrl+R` | Shuffle or repeat |
| `Ctrl+Shift+H` | History |
| `Ctrl+/` | Shortcut reference |

## Runtime data

- backend: `~/.local/lib/omarchy-ytmusic/`
- venv: `~/.local/share/omarchy-ytmusic/venv/`
- authentication and local history: `~/.config/omarchy-ytmusic/`
- socket: `$XDG_RUNTIME_DIR/omarchy-ytmusic/backend.sock`

Remove only generated runtime files with `./scripts/remove-runtime.sh`; pass
`--purge` to also remove authentication, history, cache, and the venv.

## Development

Run the complete plugin validation from the nbshell repository:

```bash
plugins/ytmusic/scripts/test.sh
```

The backend protocol and architecture are documented in
[`docs/TECHNICAL.md`](docs/TECHNICAL.md).

## Credits and license

The player started from the MIT-licensed
[Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify) and
[rlimberger/omarchy-ytmusic](https://github.com/rlimberger/omarchy-ytmusic).
Selected reliability, history, queue, equalizer, and UI work comes from Luke
Morrison's MIT-licensed [Wizwam fork](https://github.com/lukejmorrison/omarchy).
nbshell supplies its host integration, bar widget, Zen authentication, and
additional fixes. See [`LICENSE`](LICENSE) and the repository's
[`THIRD_PARTY.md`](../../THIRD_PARTY.md).

This independent project is not affiliated with YouTube or Google.
