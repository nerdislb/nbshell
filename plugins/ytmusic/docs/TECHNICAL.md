# Technical notes

The shell layout, plugin kinds, and much of the player UI started from
[Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify). Catalog access
and local playback are YouTube Music specific.

## Architecture

nbshell YouTube Music runs as a schema-2 plugin inside nbshell's Quickshell
process. It provides a shared service, a bar widget, and a lazy-loaded panel.
There is no embedded website or browser engine.

Catalog data uses the unofficial [`ytmusicapi`](https://github.com/sigma67/ytmusicapi)
client. Local audio is **mpv**, with stream URLs from **yt-dlp**. mpv is launched
headless (`--vo=null`, no Wayland/X display) and uses the D-Bus-safe client
name `omarchy-ytmusic` so MPRIS cannot stall the player. Each track sets
`force-media-title` so MPRIS clients show the song name, not the stream URL.
The plugin
talks to a private Unix socket at `$XDG_RUNTIME_DIR/omarchy-ytmusic/backend.sock`
using versioned newline-delimited JSON.

The backend is a Python process supervised by a static systemd user unit that
is never enabled at login. The plugin starts the unit when a UI is visible or
you press play, and the backend exits after the configured idle period.

nbshell deploys managed plugins from the repository, while the venv and
installed backend remain outside the plugin tree:

- `$HOME/.local/share/omarchy-ytmusic/venv`
- `$HOME/.local/lib/omarchy-ytmusic/`
- `$HOME/.config/omarchy-ytmusic/browser.json`

## Protocol

Requests:

```json
{"v":1,"id":7,"command":"pause"}
```

Successful responses keep that id. Failures set `ok` to false with a stable
error code. The server pushes `state_changed` on connection and whenever
playback state changes.

Commands include `hello`, `setup_auth`, `import_browser`, `logout`, `play`, `pause`, `toggle`,
`next`, `previous`, `seek`, `set_volume`, `set_shuffle`, `set_repeat`, `load`,
`add_to_queue`, `reorder_queue`, `search`, `browse`, `get_playlist`,
`get_album`, `get_artist`, `like`, `create_playlist`, `add_to_playlist`,
`set_eq_band`, `set_eq_preset`, `restore_eq`, and `sleep`.

## Authentication

The usual sign-in path copies the YouTube Music session already in Zen,
Chromium, Chrome, or Brave on this computer. Firefox-compatible Zen cookies
are read from its protected profile database; Chromium-family cookies are
decrypted with the libsecret OSCrypt key. The backend then writes
`ytmusicapi` headers with `ytmusicapi.setup()`. Pasting request headers is
still supported as a fallback. Catalog authentication and stream resolution
are deliberately separate: yt-dlp uses the Android player client without
browser cookies to avoid the web-music PO-token path and related 403 errors.

## Reliability and local state

The resolver uses a 40-second budget after yt-dlp has cached YouTube's player
challenge and 150 seconds for a cold cache. At startup, the backend warms that
cache with a video ID selected from the user's actual catalog. Home shelves are
cached for two minutes, and the QML client recreates dropped sockets and can
restart an unhealthy backend.

Completed tracks are stored in
`~/.config/omarchy-ytmusic/play-history.json` with mode `0600`, limited to 80
items. When signed in, local entries are merged ahead of YouTube history.

The equalizer is a stable ten-filter mpv `lavfi` chain. Keeping its topology
constant avoids restarting the stream while gains change. Preset or custom
band state is persisted through nbshell's plugin settings.

## Local development

```bash
./scripts/test.sh
```

Complete removal:

```bash
./scripts/remove-runtime.sh --purge
nbshell plugin disable ytmusic
```
