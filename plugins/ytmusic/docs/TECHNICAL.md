# Technical notes

The shell layout, plugin kinds, and much of the player UI started from
[Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify). Catalog access
and local playback are YouTube Music specific.

## Architecture

Omarchy YouTube Music runs as a plugin inside Omarchy's existing `omarchy-shell`
Quickshell process. It provides a shared service, a bar widget, and a
lazy-loaded panel. There is no embedded website or browser engine.

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

Omarchy hot-reloads plugins on any write inside their directory, so the venv
and installed backend live outside the plugin tree:

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
`add_to_queue`, `search`, `browse`, `get_playlist`, `get_album`, `get_artist`,
`like`, `create_playlist`, `add_to_playlist`, and `sleep`.

## Authentication

The usual sign-in path copies the YouTube Music session already in Chromium
(or Chrome/Brave) on this computer: decrypt the browser cookie database with
the libsecret OSCrypt key, then write `ytmusicapi` headers with
`ytmusicapi.setup()`. Pasting request headers is still supported as a
fallback. Cookies are exported to a Netscape cookie file so yt-dlp can
resolve member-only or region-locked streams when the session allows it.

## Local development

```bash
./scripts/install-local.sh
./scripts/test.sh
```

Complete removal:

```bash
./scripts/remove-runtime.sh --purge
omarchy plugin remove quickshell.ytmusic --yes
```
