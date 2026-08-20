# Changelog

## 1.1.0

- Recreate the backend socket after a dropped connection so the player can recover.
- Sign in by copying the YouTube Music session already in Chromium on this computer.
- Keep pasted request headers as a fallback.
- Keep the local mpv process off the Wayland session so tracks actually start.
- Use a D-Bus-safe mpv client name so MPRIS cannot freeze playback.
- Publish the song title to MPRIS instead of the googlevideo stream URL.
- Refresh that MPRIS title when the next track starts, not after the stream URL loads.
- Keep the bar slot as the YouTube Music logo only.

## 1.0.0

- First release: Omarchy bar widget, mini-player, and full player for YouTube Music.
- Started from [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify).
- Local playback through a plugin-owned mpv backend and yt-dlp, not Chromium.
- Library, search, playlists, queue, likes, radio, sleep timer, and Omasing lyrics.
